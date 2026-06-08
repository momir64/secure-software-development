# Security Code Review And Analysis

This directory contains the code and documentation for the security code review and analysis of the [TUDO](https://github.com/bmdyy/tudo.git) project.

## Setup and Analysis

1. Clone the TUDO repository:

   ```bash
   git clone git@github.com:bmdyy/tudo.git
   ```

2. Clone the ProgPilot repository:

   ```bash
   git clone git@github.com:designsecurity/progpilot.git
   ```

3. Build and run the TUDO project using Docker Compose:

   ```bash
   cd tudo
   docker compose up -d
   ```

4. Build the ProgPilot Docker image:

   ```bash
   cd progpilot
   docker build -t progpilot:latest .
   ```

5. Run the ProgPilot analysis on the TUDO application:

   ```bash
   cd tudo
   docker run --rm -v "$(pwd)/app:/workspace" progpilot /workspace
   ```

## Findings

The analysis will generate a report of potential security vulnerabilities and issues found in the TUDO application. TUDO is an intentionally vulnerable web application that may be used to prepare for the OSWE/AWAE certification exam. More about this app could be found in the app [README](https://github.com/bmdyy/tudo/blob/main/README.md).

Progpilot revealed several vulnerabilities in the TUDO application. Full report can be found in the [`progpilot_output.json` file](./progpilot_output.json).

## Attacks and Exploitation

### 1. Login Bypass

Login bypass vulnerabilities allow attackers to gain unauthorized access to an application without providing valid credentials. This can be achieved through various techniques, such as SQL injection, weak authentication mechanisms, or exploiting logic flaws in the login process. In the case of TUDO, we identified a potential login bypass vulnerability that could allow an attacker to access user accounts without proper authentication.

[**Instructions**](login_bypass/INSTRUCTIONS.md) show how to exploit this vulnerability and gain unauthorized access to the application.

### 2. Admin Privilege Escalation

Privilege escalation vulnerabilities allow attackers to gain elevated access within an application beyond what is intended for their account. In the case of TUDO, we identified a XSS vulnerability that allows a regular authenticated user to steal the administrator's session cookie. Because a cronjob simulates the admin logging in and visiting the homepage every minute, this can be exploited reliably without any direct interaction from the admin.

[**Instructions**](privilege_escalation/INSTRUCTIONS.md) show how to exploit this vulnerability and gain unauthorized access to the admin account.

### 3. Remote Code Execution (RCE)

## Full Exploitation Script

The `exploit.py` script contains the full exploitation process for the identified vulnerabilities in the TUDO application. It automates the steps required to exploit the login bypass, privilege escalation and remote code execution vulnerabilities.

To run the exploitation script, ensure you have Python installed and execute the following command:

```bash
python exploit.py
```