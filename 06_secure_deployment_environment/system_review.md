# System Review Script

## Description

This script performs a deep-dive security audit of the Linux operating system layer.

## Features & Security Rationale

### OS & Kernel Fingerprinting

- **Functionality**: Identifies exact OS version and kernel release.
- **Security Problem**: Outdated kernels are vulnerable to known exploits (e.g., Dirty Pipe, PwnKit). This check helps identify if the system is running a version that lacks critical security patches.

### Kernel Uptime Analysis

- **Functionality**: Reads `/proc/uptime` and calculates how many days the system has been running continuously.
- **Security Problem**: A system that has been running for more than 30 days without a reboot has almost certainly not applied any kernel updates during that period. Kernel patches require a reboot to take effect. High uptime is therefore a strong indicator of an unpatched kernel, even if the package was downloaded.

---

### Time Synchronization (NTP/Chrony) Audit

- **Functionality**: Verifies the presence and status of time-sync daemons.
- **Security Problem**: Without synchronized time, security logs become legally and technically useless for incident response (forensics). Moreover, protocols like Kerberos or TLS can fail if system time drifts significantly.

### NTP Peer Connectivity Check

- **Functionality**: Runs `ntpq -p -n` (or `chronyc tracking`) to list configured NTP peers and check whether at least one is actively synchronized (marked with `*` in ntpq output).
- **Security Problem**: A running `ntpd` process does not guarantee that time is actually being synchronized. If all upstream peers are unreachable (e.g., due to firewall rules), the daemon runs but the clock drifts freely. This check catches that scenario.

---

### Package Management & Integrity Check

- **Functionality**: Analyzes the state of all installed packages via dpkg.
- **Security Problem**: Identifies "broken" or partially installed packages. Such states often mean security triggers or post-install hardening scripts failed to run, leaving the software in a vulnerable, default, or unstable state.

### Available Security Updates Check

- **Functionality**: Runs `apt-get --just-print upgrade` (dry-run, no changes made) and filters the output for packages tagged as coming from a security repository.
- **Security Problem**: A system may have packages installed from security repositories that have since received patches. If `unattended-upgrades` is not configured or has failed silently, the system may be running known-vulnerable software versions without any visible indication. This check makes pending security updates explicit.

### Residual Config File Detection

- **Functionality**: Lists packages in `rc` state — packages that were removed but whose configuration files were left on disk.
- **Security Problem**: Configuration files for removed packages can contain sensitive information (passwords, API keys, private keys, database connection strings). They can also leave insecure defaults behind that affect other services. An attacker reading leftover config files may gain credentials or insight into the system's previous role and layout.

---

### Logging & Remote Syslog Verification

- **Functionality**: Checks if `rsyslog` is active and if it's configured to send logs to a remote server.
- **Security Problem**: Local logs are the first thing an attacker deletes to hide their tracks. This functionality helps detect the absence of centralized logging, which is a critical failure in detecting persistent threats.

### Log File Permission Audit

- **Functionality**: Uses `find` to scan `/var/log` for files that are world-readable or world-writable.
- **Security Problem**:
  - **World-readable logs**: Log files often contain sensitive information — usernames, failed authentication attempts, internal IP addresses, application errors with stack traces, and database query fragments. If any user on the system (or an attacker who has gained low-privilege access) can read these files, that information becomes available to them.
  - **World-writable logs**: A log file that any user can write to can be tampered with. An attacker can append, truncate, or overwrite entries to erase traces of their activity or to inject false events that mislead incident responders.

### Log Rotation Configuration Check

- **Functionality**: Verifies that `/etc/logrotate.conf` exists and checks whether compression is enabled.
- **Security Problem**: Without log rotation, log files grow without bound and eventually fill the filesystem. A full `/var/log` partition causes rsyslog to stop writing, which creates a silent gap in the audit trail — an attacker can exploit this by generating large amounts of traffic to fill the disk and then act without being logged. Additionally, uncompressed logs that are kept indefinitely consume space and make forensic review slower.