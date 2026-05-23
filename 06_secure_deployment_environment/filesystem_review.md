# Filesystem Review Script

## Description

This script audits filesystem configuration, permissions, executable privilege settings, and backup exposure.

### Mounted Partition Audit

- **Functionality**: Checks for the existence of `/.dockerenv` to flag container environments. It parses `/etc/fstab` (ignoring comments) to specifically check for `noexec` and `nosuid` flags on `/tmp` and `/home`, and alerts if the global `noatime` option is utilized.
- **Security Problem**: Missing `noexec` on world-writable/user-controlled paths like `/tmp` or `/home` allows local users or compromised applications to drop and execute binaries. Missing `nosuid` allows the execution of malicious Set-User-ID binaries that can exploit system resources. Activating `noatime` suppresses file access updates, directly limiting an incident response team's forensic visibility during timeline reconstruction.

---

### Sensitive File Permission Audit

- **Functionality**: Programmatically extracts the numeric octal permissions of targeted system secrets using `stat -c "%a"`. It enforces a strict upper limit of `640` for `/etc/shadow` and database configs like `/etc/mysql/my.cnf`, while explicitly validating if `/etc/passwd` maintains its exact standard `644` baseline.
- **Security Problem**: `/etc/shadow` contains hashed credentials, and my.cnf often houses database passwords in plain text. Permissions exceeding `640` mean non-privileged accounts can read hashes for offline brute-forcing or steal database access. Deviations from `644` on `/etc/passwd` expose the system to unauthorized structural modification of local account profiles.

---

### Shadow Backup Detection

- **Functionality**: Searches the root directory structure using `find`, ignoring the virtual `/proc` filesystem, to catch stray file items ending with loose backup extensions (`*.backup`, `*.old`, `*.bak`).
- **Security Problem**: System administrators frequently duplicate files like `shadow` or configurations manually before making structural modifications. While the active production files are heavily secured, these raw artifact copies often preserve careless default directory permissions, completely bypassing the OS access policies protecting the system secrets. They bypass the policies because they are often stored outside controlled application directories and may inherit overly permissive default filesystem permissions.

---

### SETUID File Review

- **Functionality**: Locates all system binaries possessing the `4000` (SETUID) permission flag. It counts the specific subset owned by user `root` via `find / -user root -perm -4000` and throws a warning flag if the aggregate baseline count exceeds 30 total entries.
- **Security Problem**: SETUID binaries execute with the permissions of the file owner (e.g., `root`) rather than the calling context of the low-privileged user. Any logical vulnerability or command injection flaws inside a root-owned SETUID binary provide a trivial local privilege escalation path. A count spikes past 30 often reveals backdoors or rogue shells left behind by threat actors to persist privileges.

---

### World-Writable and Readable File Audit

- **Functionality**: Launches system-wide searches via find (safely ignoring `/proc`) targeting files open to everyone. It checks for files where the "others" group has both read and write permissions via octal mask `-006`, alongside a dedicated sweep for general world-writable files via mask `-002` (others have write access).
- **Security Problem**: World-writable configurations, script sources, or binary locations allow any local threat vector or low-level application service to inject arbitrary code. When executed automatically by povišene/privileged system tasks (like root cronjobs), this grants an attacker full system takeover. Files combining read and write properties expose local app contexts to lateral manipulation.

---

### Backup Exposure Audit

- **Functionality**: Iterates directly through dedicated system archive locations (`/backup` and `/var/backups`). It explicitly probes inside these folders for active file items matching octal masks `-004` (read permission for others) or `-002` (write permission for others).
- **Security Problem**: Backup archives generally pool flat-file copies of full application architectures, secrets, databases, and keyrings. If these directory repositories are world-readable, low-privileged local accounts can simply parse old archives to extract production passwords and system keys, invalidating the active hardening implementations of the live environment.
