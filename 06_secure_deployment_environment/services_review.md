# Services Review Script

## Description

This script audits running processes, network-exposed services, and the configuration of key daemons: SSH, MySQL/MariaDB, Apache, Nginx, and the cron scheduler.

## Features & Security Rationale

### Running Process Audit

- **Functionality**: Runs `ps -edf` to enumerate all active processes with their owning users, parent PIDs, and full command lines.
- **Security Problem**: A full process listing reveals unexpected daemons, rogue interpreters, or tools an attacker may have staged. It also identifies services running under privileged accounts that should be running as a dedicated low-privilege user instead.

---

### TCP/UDP Listening Service Enumeration

- **Functionality**: Uses `lsof -i TCP -n -P` and `lsof -i UDP -n -P` to list all open TCP and UDP sockets alongside the owning process name, PID, and user. Falls back to `ss` or `netstat` if `lsof` is unavailable.
- **Security Problem**: Every listening port is an attack surface. Package post-install scripts can silently open ports, and developers frequently start services during testing and forget to stop them. `lsof` makes the full network exposure of the host explicit — including which user owns each socket — so it can be compared against what is actually required.

---

### Services Exposed on All Interfaces

- **Functionality**: Filters the `ss` output for sockets bound to `0.0.0.0`, `*`, or `:::` (all IPv4/IPv6 interfaces) rather than a specific loopback or internal address.
- **Security Problem**: Services bound to all interfaces are reachable from any network the host participates in, including public-facing ones. Services that only need to be reachable locally (databases, cache daemons, internal APIs) should be explicitly bound to `127.0.0.1` to eliminate unnecessary exposure.

---

### SSH Daemon Configuration Audit

- **Functionality**: Parses `/etc/ssh/sshd_config` and all included `.d/` drop-in files to evaluate five directives: `PermitRootLogin`, `AllowTcpForwarding`, `Protocol`, `MaxAuthTries`, and `PasswordAuthentication`.
- **Security Problem**:
  - **PermitRootLogin**: Allowing direct root login via SSH merges authentication and privilege escalation into a single step. A successful brute-force or stolen key immediately grants full system control with no intermediate audit trail.
  - **AllowTcpForwarding**: When enabled, an authenticated user can tunnel arbitrary TCP traffic through the SSH connection. This is routinely abused to bypass network-layer controls and reach internal hosts that would otherwise be unreachable.
  - **Protocol**: SSHv1 contains fundamental cryptographic flaws and is considered broken. Modern OpenSSH no longer supports it, but explicitly auditing this directive catches legacy configurations.
  - **MaxAuthTries**: The default value of 6 allows an attacker significant latitude to test credentials within a single connection before being disconnected. Reducing this to 3 halves the window of opportunity per connection and makes brute-force campaigns slower and more detectable.
  - **PasswordAuthentication**: Password-based authentication is vulnerable to brute-force and credential-stuffing attacks. Key-based authentication is significantly more resistant because private key material is never transmitted over the network.

---

### MySQL/MariaDB Configuration Audit

- **Functionality**: Checks whether a MySQL or MariaDB process is running (`mysqld` or `mariadbd`). On Debian, `mysql-server` is not available and `mariadb-server` is installed instead — MariaDB runs under the `mysqld` process name and uses `/etc/mysql/my.cnf`, so the checks are fully compatible with both. Reads the `bind-address` directive from `/etc/mysql/my.cnf`, confirms via `ss` that port 3306 is not reachable on external interfaces, and audits the permissions on `/etc/mysql/debian.cnf`.
- **Security Problem**:
  - **bind-address**: By default, MySQL may listen on all interfaces, exposing the database engine directly to the network. A database server should virtually never need to accept direct connections from outside the host; binding to `127.0.0.1` eliminates this attack surface entirely.
  - **External port exposure**: A misconfigured or missing `bind-address` directive is confirmed by checking the actual socket state. The configuration file alone is insufficient — the live socket state is the ground truth.
  - **debian.cnf permissions**: On Debian-based systems, `/etc/mysql/debian.cnf` contains the plaintext password for the `debian-sys-maint` maintenance account. If this file is readable by unprivileged users, an attacker with any local access can extract these credentials and gain full administrative access to the database.

---

### Apache Web Server Configuration Audit

- **Functionality**: Detects running Apache processes, checks the user running worker processes, audits `ServerTokens` and `ServerSignature` in the security configuration file, and scans enabled site configs for the `Indexes` option.
- **Security Problem**:
  - **Worker process user**: If Apache worker processes run as `root`, any code execution vulnerability in a web application or in Apache itself grants immediate root access to the host. Worker processes should always run as a dedicated low-privilege user such as `www-data`.
  - **ServerTokens / ServerSignature**: These directives control how much version information Apache includes in HTTP response headers and error pages. Verbose banners (e.g., `Apache/2.4.51 (Debian)`) give an attacker the exact version number needed to look up known CVEs and select a targeted exploit without probing.
  - **Directory listing (Indexes)**: When `Indexes` is active on a directory with no `index.html`, Apache renders a full listing of all files in that directory. This can expose configuration files, backup archives, credentials, or application source code to any visitor.

---

### PHP Configuration Audit

- **Functionality**: Locates the active `php.ini` file (searching versioned Apache and CLI paths, falling back to `php -r "echo php_ini_loaded_file();"`) and checks seven directives: `expose_php`, `display_errors`, `log_errors`, `safe_mode`, `allow_url_include`, `error_reporting`, and `disable_functions`. For `disable_functions` it also checks whether specific high-risk functions (`eval`, `exec`, `system`, `shell_exec`, `passthru`, `proc_open`, `popen`) are individually present in the list.
- **Security Problem**:
  - **expose_php**: When `On`, PHP adds an `X-Powered-By` header to every HTTP response disclosing the exact PHP version. This lets an attacker instantly identify the runtime and look up known CVEs without any active probing.
  - **display_errors**: Showing errors to end users in production leaks internal file paths, database structure, class names, and stack traces. This information materially assists an attacker in understanding the application's internals.
  - **log_errors**: If error logging is disabled, PHP failures are silent. Errors that indicate exploitation attempts (type errors from unexpected input, failed includes, etc.) leave no trace for incident response.
  - **safe_mode**: Although it can be bypassed, `safe_mode` adds restrictions on file access, command execution, and environment variables that increase the effort required for an attacker to move laterally after exploiting a PHP vulnerability. It should be enabled to slow down attackers even if it cannot stop them entirely.
  - **allow_url_include**: Permits `include` and `require` to load files from remote URLs. This is the direct enabler of Remote File Inclusion (RFI) attacks, where an attacker supplies a URL pointing to their own malicious PHP code and the server executes it.
  - **error_reporting**: Should be set to `E_ALL` so that all error classes are captured in logs, even in production where `display_errors` is off. Suppressing error classes hides bugs that may be security-relevant.
  - **disable_functions**: Functions like `eval`, `exec`, `system`, `shell_exec`, `passthru`, `proc_open`, and `popen` allow PHP code to execute arbitrary OS commands or evaluate arbitrary PHP. If a web application has a code execution vulnerability, these functions are what an attacker uses to break out of the PHP context and run commands on the underlying server. Disabling them at the interpreter level removes this capability regardless of application-level flaws.

---

### Suhosin PHP Extension Audit

- **Functionality**: Searches for a Suhosin `.ini` file across common PHP configuration paths. If found, it strips comments and blank lines to display the active configuration (mirroring `egrep -v '^;|^$'`), then checks four specific directives: `suhosin.log.syslog`, `suhosin.executor.include.max_traversal`, `suhosin.executor.disable_eval`, and `suhosin.executor.disable_emodifier`.
- **Security Problem**: Suhosin is a hardening patch and extension for PHP that adds a second layer of protection against common PHP exploitation techniques. Its absence or default (unconfigured) state means several attack vectors are left unmitigated at the interpreter level:
  - **suhosin.log.syslog**: Without syslog logging enabled, Suhosin's attack detection events are silent. Setting it to `S_ALL` ensures all blocked attempts are recorded and visible to the system's log aggregation.
  - **suhosin.executor.include.max_traversal**: Limits the number of directory traversal components (`../`) allowed in an `include` path. Without this, an attacker who can influence include paths can traverse arbitrarily deep into the filesystem. A value of `3` prevents deep traversal while keeping normal application includes working.
  - **suhosin.executor.disable_eval**: Disables the `eval()` function at the interpreter level. Even if `eval` is not in `disable_functions`, Suhosin can block it independently. `eval()` is the most direct path for injecting and executing arbitrary PHP code.
  - **suhosin.executor.disable_emodifier**: Disables the `/e` modifier in `preg_replace()`, which causes the replacement string to be evaluated as PHP code. This modifier is a well-known code execution vector that has been used in numerous real-world PHP application exploits.

---

### Nginx Web Server Configuration Audit

- **Functionality**: Detects running Nginx processes, checks the user running worker processes, and audits the `server_tokens` directive across all Nginx configuration files.
- **Security Problem**:
  - **Worker process user**: Same risk as Apache — Nginx workers running as `root` mean any exploitation of the web layer gives full system access immediately.
  - **server_tokens**: When set to `on` (the default), Nginx includes its version number in `Server` response headers and error pages. Setting it to `off` prevents version disclosure and removes a trivial reconnaissance step for attackers.

---

### Crontab Audit

- **Functionality**: Reads and displays the system crontab (`/etc/crontab`), iterates through all `cron.d` and `cron.*` directories to list scheduled job files, and dumps user crontabs from `/var/spool/cron/crontabs`. It then extracts file paths of scripts invoked by these jobs and checks each one for world-writable or group-writable permissions.
- **Security Problem**:
  - **Crontab enumeration**: Scheduled tasks often run as `root` and are therefore a high-value privilege escalation target. Reviewing them identifies tasks whose necessity is unclear, tasks running on overly broad schedules, and tasks that execute scripts in locations attackers may be able to write to.
  - **World-writable cron scripts**: If any user on the system can write to a script that is automatically executed by `root` via cron, that user can insert arbitrary commands and achieve full privilege escalation the next time the job runs. This is one of the most common and reliable local privilege escalation paths on Linux systems.
  - **Group-writable cron scripts**: Even group write access is dangerous if group membership is not tightly controlled, since any member of the group can modify the script and wait for the next scheduled execution.