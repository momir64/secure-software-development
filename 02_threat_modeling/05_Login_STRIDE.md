# MegaTravel – Login Flow: STRIDE Threat & Mitigation Report

## 1. Diagram Overview

The login flow involves five elements connected by four data flows:

| # | Element | Type |
| --- | ------- | ------ |
| 1 | **Web Client** | External Actor |
| 2 | **Web APP** | Process |
| 3 | **Auth Processor** | Process |
| 4 | **Credentials DB** | Data Store |
| 5 | **Auth Configuration** | Data Store |

| # | Flow | Protocol | Direction |
| --- | ------ | ---------- | ----------- |
| F1 | Web Client -> Web APP: *Login Request / Response* | HTTPS / TLS 1.3 (public) | Bidirectional |
| F2 | Web APP -> Auth Processor: *Auth Request / Response* | mTLS / internal RPC | Bidirectional |
| F3 | Auth Processor -> Credentials DB: *Credential Lookup* | TLS / DB driver | Bidirectional |
| F4 | Auth Processor -> Auth Configuration: *Read Auth Config* | TLS / internal | Unidirectional |

Trust boundaries cross at:

- **Internet Boundary:** between Web Client and Web APP
- **Internal Service Boundary:** between Auth Processor and its backing stores

---

## 2. STRIDE Analysis

STRIDE categories: **S**poofing | **T**ampering | **R**epudiation | **I**nformation Disclosure | **D**enial of Service | **E**levation of Privilege

---

### 2.1 Web Client (External Actor)

| STRIDE | Threat ID | Description | Likelihood | Impact | Mitigation |
| -------- | ----------- | ------------- | ----------- | -------- | ------------ |
| **S** | S-WC-01 | An attacker steals a valid session cookie or JWT and replays it to impersonate a legitimate user (session hijacking). Even with TLS, client-side malware or XSS can exfiltrate tokens. | Medium | High | Issue short-lived JWTs (≤15 min) with refresh-token rotation. Set `Secure`, `HttpOnly`, and `SameSite=Strict` on session cookies. Enforce HSTS. Bind tokens to client fingerprint where feasible. |
| **S** | S-WC-02 | An attacker creates a lookalike phishing site to harvest credentials before the user reaches the real Web APP. | Medium | High | Deploy HSTS preloading. Implement MFA so stolen passwords alone are insufficient. Educate users to verify domain. |
| **T** | T-WC-01 | A client-side script injection (XSS) modifies the login form to capture credentials before they are sent, or alters the POST target. | Medium | Critical | Enforce Content-Security-Policy headers. Input sanitisation and output encoding on Web APP. Subresource Integrity on all CDN assets. |
| **R** | R-WC-01 | A user denies having initiated a login event (e.g., to repudiate an account access). | Low | Medium | Log all login attempts with IP, user-agent, timestamp, and result. Provide users with login-history visibility in their account portal. |
| **I** | I-WC-01 | Credentials entered by the user are exposed in browser history, proxy logs, or server access logs if accidentally logged in clear text on the Web APP side. | Low | High | Never log credential values. Ensure login endpoints use POST. Strip sensitive query parameters from access logs via WAF/reverse proxy. |
| **D** | D-WC-01 | An attacker flood-submits login requests from a botnet, locking out legitimate users via account lockout policies or exhausting Web APP connection pools. | High | Medium | Rate-limiting per IP and per account (e.g., 5 failed attempts -> CAPTCHA, 10 -> temporary lockout). WAF with bot-detection rules. CDN-layer DDoS absorption. |
| **E** | E-WC-01 | A client exploits a vulnerability in the Web APP's session management to obtain a token with higher privilege than the authenticated user possesses. | Low | Critical | Enforce principle of least privilege on token claims. Validate all privilege-escalation paths server-side. Separate tokens for different privilege levels. |

---

### 2.2 Web APP (Process)

| STRIDE | Threat ID | Description | Likelihood | Impact | Mitigation |
 | -------- | ----------- | ------------- | ----------- | -------- | ------------ |
| **S** | S-WA-01 | An attacker spoofs the Auth Processor by intercepting the internal F2 channel (e.g., via ARP poisoning on a misconfigured internal network) and returning a forged successful auth response. | Low | Critical | Use mTLS on F2 – Web APP must verify Auth Processor's certificate. Pinning the Auth Processor's CA reduces MITM risk even within the internal network. |
| **T** | T-WA-01 | An attacker or malicious insider tampers with the Web APP configuration (security headers, allowed redirect URIs, token-signing algorithm) to weaken authentication. | Low | Critical | Sign configuration files; verify signature on startup. Deploy config changes exclusively via CI/CD with peer review. Alert on runtime config hash mismatch. |
| **T** | T-WA-02 | SQL/NoSQL injection via the login form manipulates backend queries rather than relying on the Auth Processor flow. | Medium | High | Use parameterised queries / ORM throughout. Web Application Firewall with OWASP CRS. Input validation on all fields before forwarding. |
| **R** | R-WA-01 | The Web APP itself fails to log successful/failed authentication events, making it impossible to reconstruct what happened during a security incident. | Medium | High | Emit structured audit events for every login attempt (success, failure, MFA bypass) to an immutable, centralised SIEM. |
| **I** | I-WA-01 | Verbose error messages on failed login reveal whether a username exists, enabling user enumeration. | High | Medium | Return a generic "Invalid credentials" message regardless of failure reason. Ensure response timing is uniform (constant-time comparison). |
| **I** | I-WA-02 | Internal stack traces or debug headers are exposed to the client in error responses, leaking internal architecture details. | Medium | Medium | Disable debug mode in production. Strip `X-Powered-By` and stack-trace bodies. Use a custom error handler. |
| **D** | D-WA-01 | The Web APP's auth endpoint is overloaded by a high-volume credential-stuffing campaign, exhausting thread pools and degrading service for all users. | High | High | Implement token-bucket rate limiting at the WAF/API gateway layer before requests reach the application. Scale horizontally behind a load balancer. |
| **E** | E-WA-01 | A vulnerability in the Web APP's session handling allows an authenticated low-privilege user to obtain an admin-level session token. | Low | Critical | Separate authentication from authorisation. Validate roles on every request server-side. Employ automated security testing (DAST) in the CI pipeline. |

---

### 2.3 Auth Processor (Process)

| STRIDE | Threat ID | Description | Likelihood | Impact | Mitigation |
| -------- | ----------- | ------------- | ----------- | -------- | ------------ |
| **S** | S-AP-01 | An attacker replays a previously captured valid Auth Request on F2 to force the Auth Processor to issue a fresh JWT without the user re-authenticating. | Low | High | Include a per-request nonce and timestamp in every Auth Request; Auth Processor rejects requests outside a 30-second window or with a reused nonce. |
| **T** | T-AP-01 | An attacker modifies Auth Configuration (token expiry, signing key, MFA requirements) to weaken the policies the Auth Processor enforces. | Low | Critical | Auth Processor verifies the config file's asymmetric signature before every read. Only signed configs are accepted. Config writes require admin CI/CD approval. |
| **T** | T-AP-02 | An attacker compromises the Auth Processor process and alters in-memory credential comparison logic to always return success (logic tampering at runtime). | Very Low | Critical | Run Auth Processor in a hardened container with read-only filesystem, no shell access, and runtime integrity monitoring (e.g., eBPF-based anomaly detection). |
| **R** | R-AP-01 | The Auth Processor does not produce tamper-evident logs, so a malicious insider could clear auth logs after a brute-force session. | Medium | High | Auth Processor logs to an append-only, off-process SIEM. Logs include: username (hashed), timestamp, IP, outcome, and MFA status. |
| **I** | I-AP-01 | The Auth Processor exposes internal error details (e.g., DB connection strings, exception traces) in its response to the Web APP, which may propagate to the client. | Medium | Medium | Catch all exceptions internally. Return only typed error codes to the Web APP. Log full details locally. |
| **I** | I-AP-02 | Side-channel timing differences in credential comparison allow an attacker to determine whether a username is valid. | Medium | Medium | Use constant-time string comparison for hash verification. Always perform the full bcrypt/Argon2 hash operation even for non-existent usernames. |
| **D** | D-AP-01 | The Auth Processor is flooded with auth requests, exhausting its connection pool to the Credentials DB and causing authentication failures for all users. | Medium | High | Rate-limit incoming requests from the Web APP (circuit breaker pattern). Deploy multiple Auth Processor replicas behind an internal load balancer. Queue auth requests with back-pressure signalling. |
| **E** | E-AP-01 | A vulnerability in the JWT library (e.g., algorithm confusion – `alg: none` attack) allows an attacker to forge tokens accepted by the Web APP. | Low | Critical | Pin the JWT signing algorithm (`RS256` or `EdDSA`) explicitly; reject tokens specifying `none` or unexpected algorithms. Rotate signing keys on a schedule. Validate all claims (iss, aud, exp, nbf). |

---

### 2.4 Credentials DB (Data Store)

| STRIDE | Threat ID | Description | Likelihood | Impact | Mitigation |
| -------- | ----------- | ------------- | ----------- | -------- | ------------ |
| **S** | S-CD-01 | An attacker spoofs the Auth Processor's identity to connect to the Credentials DB directly and exfiltrate password hashes. | Low | Critical | DB access is restricted by IAM role and network whitelist to the Auth Processor's IP range only. mTLS client certificates authenticate the caller. |
| **T** | T-CD-01 | An attacker who gains write access to the Credentials DB modifies stored hashes to implant a known password, enabling account takeover. | Very Low | Critical | Restrict write access to an authorised migration/IAM service account only. Enable DB-level audit logging on all write operations. Detect unexpected hash changes via integrity monitoring. |
| **R** | R-CD-01 | No audit trail exists for queries to the Credentials DB, so exfiltration via the Auth Processor service account cannot be attributed. | Medium | High | Enable database activity monitoring (DAM) logging all queries with identity, timestamp, and row count. Alert on bulk reads exceeding a threshold. |
| **I** | I-CD-01 | An attacker extracts the database file (e.g., via compromised backup) and runs offline brute-force attacks against password hashes. | Medium | High | Use Argon2id (or bcrypt with work factor ≥12). Enforce unique per-user salts. Rotate DB encryption keys via KMS. Hashes alone are not sufficient for login without the Auth Processor flow. |
| **I** | I-CD-02 | A misconfigured DB backup is stored unencrypted in cloud object storage, leaking all credential hashes. | Medium | High | Encrypt all backups with KMS-managed keys. Apply bucket policies restricting access. Scan backup destinations with cloud security posture tooling. |
| **D** | D-CD-01 | The Credentials DB is overwhelmed by high-frequency queries from a compromised Auth Processor instance, causing authentication failures platform-wide. | Low | High | Connection pooling with maximum pool size limits. Auth Processor implements exponential back-off on DB errors. DB replicas for read-heavy workloads. |
| **E** | E-CD-01 | SQL injection via a poorly sanitised query constructed in the Auth Processor grants the attacker DB admin access. | Low | Critical | Auth Processor uses parameterised queries exclusively. DB account operates with minimum privilege (SELECT on the users table only). WAF and static analysis in CI catch injection patterns. |

---

### 2.5 Auth Configuration (Data Store)

| STRIDE | Threat ID | Description | Likelihood | Impact | Mitigation |
| -------- | ----------- | ------------- | ----------- | -------- | ------------ |
| **S** | S-AC-01 | An attacker replaces a legitimate config file with a maliciously crafted one (e.g., allowing weak algorithms, disabling MFA) to weaken the Auth Processor's policy. | Low | Critical | Config files are signed with an asymmetric key. Auth Processor verifies the signature on every read and refuses to start if verification fails. |
| **T** | T-AC-01 | An insider with write access to the Auth Configuration alters token expiry or allowed algorithm settings without detection. | Low | Critical | Write access is restricted to the System Administrator role via CI/CD only. All changes are logged with before/after values to an immutable audit log. A second administrator approval (four-eyes policy) is required for production changes. Runtime hash monitoring alerts the security team on unexpected configuration drift. |
| **R** | R-AC-01 | An administrator modifies authentication policy and later denies responsibility. | Low | High | Individual administrator accounts (no shared credentials). Append-only audit log records identity, timestamp, and changed values for every config write. |
| **I** | I-AC-01 | The Auth Configuration file is stored in plain text in a version control system, exposing signing key references or internal endpoint addresses. | Medium | Medium | Store only non-secret policy values in the config file. Reference secrets (signing key IDs) via environment variables or a secrets manager (e.g., AWS Secrets Manager / HashiCorp Vault). Restrict repository access. |
| **D** | D-AC-01 | The Auth Configuration store becomes unavailable (e.g., NFS mount failure), preventing the Auth Processor from reading policy and halting all authentications. | Low | High | Cache the last-known-good configuration in memory. Define a safe fallback policy for short outages. Monitor config store availability with automated alerting. |
| **E** | E-AC-01 | An attacker modifies the configuration to grant the Auth Processor (or a spoofed service) elevated DB permissions or to bypass MFA for administrative accounts. | Very Low | Critical | Config changes require code-review in CI/CD and a second-admin sign-off. IAM roles enforced at the infrastructure layer are not controlled by the application config file; they require separate infrastructure-level changes. |

---

## 3. Risk Summary

| Threat ID | Element | Category | Likelihood | Impact | Priority |
| ----------- | --------- | ---------- | ----------- | -------- | ---------- |
| E-AP-01 | Auth Processor | Elevation | Low | Critical | **HIGH** |
| T-AC-01 | Auth Configuration | Tampering | Low | Critical | **HIGH** |
| S-AP-01 | Auth Processor | Spoofing | Low | High | **HIGH** |
| D-WC-01 | Web Client | DoS | High | Medium | **HIGH** |
| D-WA-01 | Web APP | DoS | High | High | **HIGH** |
| I-CD-01 | Credentials DB | Info Disclosure | Medium | High | **MEDIUM** |
| T-WA-01 | Web APP | Tampering | Low | Critical | **MEDIUM** |
| I-WA-01 | Web APP | Info Disclosure | High | Medium | **MEDIUM** |
| T-CD-01 | Credentials DB | Tampering | Very Low | Critical | **MEDIUM** |
| S-WC-01 | Web Client | Spoofing | Medium | High | **MEDIUM** |
| R-AP-01 | Auth Processor | Repudiation | Medium | High | **MEDIUM** |
| I-AP-02 | Auth Processor | Info Disclosure | Medium | Medium | **LOW** |

---

## 4. Top Remediation Priorities

1. **JWT algorithm pinning (E-AP-01):** Fix the `alg: none` / algorithm-confusion class of attack in the Auth Processor. This is a single-line configuration change with critical impact.
2. **Signed Auth Configuration with four-eyes approval (T-AC-01):** Compromise of auth policy is a platform-wide catastrophe; the signing + approval gate is the primary control.
3. **Rate limiting + CAPTCHA on login endpoints (D-WC-01, D-WA-01):** Credential-stuffing and DoS are high-likelihood; WAF-layer controls stop them before they reach application code.
4. **mTLS on F2 internal channel (S-AP-01, S-WA-01):** Prevents internal network spoofing attacks even if the perimeter is breached.
5. **Argon2id with unique salts + encrypted backups (I-CD-01):** Ensures exfiltrated hashes remain computationally infeasible to crack offline.
