# Users & Authentication Review Script

## Description

This script performs a security audit of user accounts, password policies, authentication mechanisms, and privilege escalation configurations on a Linux system.

## Features & Security Rationale

### UID 0 Account Review

- **Functionality**: Parses `/etc/passwd` and identifies all users with a User ID (UID) equal to `0`.
- **Security Problem**: On Linux systems, only the `root` account should possess UID `0`. Any additional user with UID `0` receives identical privileges to root and effectively bypasses normal privilege separation. Attackers frequently create hidden UID `0` accounts as persistence backdoors after compromising a system.

---

### Interactive Shell Review

- **Functionality**: Evaluates column 7 of `/etc/passwd` using `awk` to flag any account whose assigned terminal wrapper does not terminate in a non-interactive token string (`nologin` or `false`).
- **Security Problem**: Service accounts such as `mysql`, `www-data`, `ntp`, or `daemon` generally should not provide interactive shell access. If a vulnerable service is compromised and its account has shell access enabled, an attacker can gain direct command execution on the host.

---

### Duplicate UID Detection

- **Functionality**: Extracts all UIDs from `/etc/passwd` and identifies duplicate values using a combination of `cut`, `sort`, and `uniq`.
- **Security Problem**: Multiple users sharing the same UID are treated by the kernel as the same identity. This can allow one user to access another user's files and privileges, bypassing intended access controls.

---

### Duplicate Username Detection

- **Functionality**: Searches for repeated usernames inside `/etc/passwd`.
- **Security Problem**: Duplicate usernames may indicate filesystem corruption, manual account manipulation, or unauthorized account creation. User identity ambiguity can also interfere with authentication systems.

---

### Empty Password Detection

- **Functionality**: Reviews `/etc/shadow` using `awk` and identifies active user entries with null fields where password hashes should reside.
- **Security Problem**: Empty passwords may allow direct authentication without credentials depending on PAM configurations and enabled peripheral network services, presenting an immediate security risk.

---

### Password Hash Algorithm Review

- **Functionality**: Parses the hash prefixes within `/etc/shadow` to track encryption types, treating non-tokenized values that are not disabled (`!`) or locked (`*`) as legacy DES.

| Prefix Identifier | Algorithm | Security |
|-------------------|------------|-----------|
| Raw string (no `$`) | DES | Very weak |
| `$1$` | MD5 | Weak |
| `$2$`,`$2a$` | Blowfish/Bcrypt | Good |
| `$5$` | SHA-256 | Good |
| `$6$` | SHA-512 | Strong |
| `$y$` | Yescrypt | Strong (modern default on many systems) |

- **Security Problem**: Weak hashing algorithms such as DES and MD5 are vulnerable to modern high-throughput brute-force or dictionary attacks. Legacy algorithms limit input sizes and can be easily cracked using commodity parallel processing units.

---

### PAM Password Hash Configuration Review

- **Functionality**: Extracts `pam_unix.so` parameters from `/etc/pam.d/common-password` and checks whether modern password hashing algorithms such as `SHA-512`, `yescrypt`, or `bcrypt` are configured.
- **Security Problem**: Weak password storage algorithms allow attackers to brute-force credential databases more efficiently. Modern algorithms intentionally increase computational cost and resistance against GPU-based attacks.

---

### Password Complexity Review

- **Functionality**: Scans PAM rules to see if the engine references enforcement frameworks like `pam_cracklib` or `pam_pwquality` inside the local rule stacks.
- **Security Problem**: Without active configuration constraints (e.g., `minlen`, `ucredit`, `dcredit`), users frequently default to predictable passwords. Weak passphrase properties heavily compress the time required for automated dictionary attacks.

---

### Password Expiration Policy Review

- **Functionality**: Uses `chage -l` inside a loop to evaluate aging profiles, focusing closely on the "Maximum" password validity life configuration for system profiles.
- **Security Problem**: Accounts with indefinite password thresholds preserve compromised credentials' usability permanently. Enforcing structural expiration reduces an leaked credential's lifecycle window.

---

### Locked Account Review

- **Functionality**: Leverages `awk` to parse `/etc/shadow` lines beginning with token delimiters `!` or `*` to yield a comprehensive list of explicitly disabled user profiles.
- **Security Problem**: Locked accounts themselves are not a risk. The purpose of this review is to verify that unused accounts are properly disabled and that unexpected accounts have not remained active.
  
---

### Sudo NOPASSWD Review

- **Functionality**: Recursively searches system rule configuration directories (`/etc/sudoers` and `/etc/sudoers.d/`) to detect active `NOPASSWD` execution blocks.
- **Security Problem**: `NOPASSWD` bypasses critical secondary context confirmation. If an operator's standard session is hijacked or an application execution flaw surfaces under that user, an actor acquires unauthenticated administrative execution paths.

---

### Dangerous Sudo Commands Review

- **Functionality**: Probes sudo system structures recursively using extended regular expressions (`grep -r -E`) to enforce strict word boundaries (`\b`) around high-risk binary strings (`chown`, `chmod`, `vi`, `less`, `find`, `awk`, `python`, `perl`).
- **Security Problem**: Granting users sudo rights to generic utilities or scripting interpreters often permits trivial shell escapes. Attackers leverage these binary paths to escalate privileges or manipulate system assets outside intended rule boundaries.

---

### Privileged Group Review

- **Functionality**: Evaluates group access components across directory service calls using `getent` to inspect identities assigned to privileged system namespaces like `sudo` or `wheel`.
- **Security Problem**: Unmonitored administrative group memberships widen privilege boundaries. Any user added to these core management groups inherits root-equivalent authority over local configurations.

---

### SSH Access Configuration Review

- **Functionality**: Reviews SSH daemon configuration and extracts access-control directives such as `PermitRootLogin`, `AllowUsers`, and `DenyUsers`.
- **Security Problem**: Enabling unrestricted SSH access or allowing direct root logins increases exposure to brute-force attacks and credential theft.

---

### Home Directory Permissions

- **Functionality**: Employs `find` across `/home` with maximum depth adjustments to trap directories exposing world-writable profiles matching octal criteria `-002`.
- **Security Problem**: If a user's base path profile remains world-writable, other local identities or system tools can drop malformed dotfiles (`.bashrc`, `.ssh/authorized_keys`) inside the directory structure, enabling straightforward lateral movement or privilege hijacking.

---

### Dormant Accounts Review

- **Functionality**: Query system session trackers via the `lastlog` binary utility to isolate profile communication records and verify identity interactions.
- **Security Problem**: Service wrappers or employee context blocks left unattended for extended intervals offer hidden exploitation surfaces. Identifying long-stale accounts helps administrators prune unnecessary credentials.