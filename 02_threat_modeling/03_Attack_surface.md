# Attack Surface

Attack surface is a set of all entry points through which the users and external systems interact with the system, and are thus entrypoints for malicious parties. Mapping it starts by identifying every actor that interacts with MegaTravel, both human and automated, and then tracing the interfaces each one relies on.

## Users

Each user has to interact with the system through one or multiple entry points, so identifying all the users helps systematically cover all entry points. The following user categories were identified (including both humans and external systems):

| User | Type | Description |
|---|---|---|
| Customer | Human (external) | Uses web/mobile app to explore and book trips. Unauthenticated during browsing, authenticated during booking and account management. |
| Customer support agent | Human (internal) | Uses internal Customer Relationship Management (CRM) to look up accounts and handle customer calls. Has broad read access to customer PII. |
| Business expert | Human (internal) | Uses analytics data to make business decisions and marketing campaigns. Handles proprietary business data. |
| System administrator | Human (internal) | Manages server infrastructure and deploys updates. Holds the highest privilege level in the system. |
| Finance staff | Human (internal) | Manages payroll, personnel records, and financial transactions through back-office systems. |
| Payment provider | External system | Handles payments on MegaTravel's behalf. Integration is bidirectional: outbound payment requests and inbound webhook callbacks. |
| Accommodation partners | External system | Manages hotel bookings for our clients. |
| Transportation partners | External system | Manages transport tickets for our clients. |
| Tour guide partners | External system | Manages tours for our clients. Typically smaller organizations with weaker security postures. |
| Maps API | External system | Provides geolocation information. |
| Email / SMS provider | External system | Sends outbound booking confirmations, receipts, password-reset links, and OTP codes on MegaTravel's behalf. |

## Entry points

Entry points are grouped by trust zone: public-facing interfaces exposed to the internet, internal interfaces accessible only within the corporate network, and indirect channels that do not expose a direct interface but still carry attacker-relevant data into the system.

### Public-facing

| Users | Entry Point | Interface Type | Exposed To | Attacks |
|---|---|---|---|---|
| Customers | REST API (unauthenticated endpoints) | REST API over HTTPS | Public Internet | Enumeration, scraping, injection, DDoS against search/catalog endpoints |
| Customers (prospective and existing) | Authentication & account-recovery endpoints | REST API over HTTPS | Public Internet | Credential stuffing, account takeover, reset-token abuse, OAuth redirect tampering, multi-factor authentication bypass |
| Customers | REST API (authenticated endpoints) | REST API over HTTPS | Public Internet (authenticated) | Token forgery, user impersonation, Insecure Direct Object Reference (IDOR) |
| Customers | Customer file upload endpoints | Multipart HTTPS upload to REST API | Public Internet (authenticated) | Malware upload, image-parser exploits, path traversal, Server-Side Request Forgery (SSRF) via URL-based uploads, storage exhaustion |
| Customers | Payment API | REST API over HTTPS + payment processor call | Public Internet (authenticated) | Cardholder data exposure via tokenization/redirect misconfig, payment tampering, Payment Card Industry Data Security Standard (PCI DSS) scope violations |
| Payment provider | Payment provider webhook callback | HTTPS webhook | Public Internet | Forged callbacks confirming fraudulent bookings or manipulating payment state when signature validation is missing |
| Accommodation / Transport / Tour partners | Partner API gateway | REST API over HTTPS | Public Internet (authenticated) | Malicious data submission or lateral movement via compromised partner credentials |

### Internal

| Users | Entry Point | Interface Type | Exposed To | Attacks |
|---|---|---|---|---|
| Customer support agent | Customer support CRM Portal | Internal web app | VPN / Internal network | PII exfiltration, phishing foothold |
| Business manager | Analytics dashboard | Internal web app | VPN / Internal network | Business intelligence data exfiltration, USB malware |
| Finance staff | Back-office / Business & Finances Platform | Internal web app | VPN / Internal network | Financial data exfiltration, payroll tampering, insider fraud |
| System admin | Admin management interface (SSH, cloud console, CI/CD pipelines), Backups (DB snapshots, object storage, offline media) | SSH, cloud console, CI/CD, storage buckets, tape, archive systems | VPN / Internal network, Ops / Database Administrator | Privilege escalation, full system compromise, full-data breach via misconfigured bucket ACLs, weak at-rest encryption, or leaked backup credentials |
| All internal staff | Physical access (offices, workstations) | Physical | London / Boston / Hong Kong offices + branches | Tailgating, badge cloning, USB drops, rogue Wi-Fi, lost/stolen laptops |

### Indirect

| Users | Entry Point | Interface Type | Exposed To | Attacks |
|---|---|---|---|---|
| All users | Email (inbound + outbound) | Email | Public internet | Inbound phishing (primary initial-access vector); compromise of the sending provider enabling brand-impersonation phishing and reset-token interception |
| Customers | Mobile app binary | Distributed APK via app stores | Anyone who downloads the app | Reverse engineering to discover undocumented endpoints, hardcoded secrets, or bypass certificate pinning; tampered re-distributed builds targeting sideload-friendly markets |
| Maps API provider | Maps / geolocation API | REST API (outbound) | Internet (outbound) | Fake / poisoned data |
| Accommodation partners | Accommodation partners API | REST API (outbound) | Internet (outbound) | Fake / poisoned data; MITM |
| Transportation partners | Transportation partners API | REST API (outbound) | Internet (outbound) | Fake / poisoned data; MITM |
| Tour guide partners | Tour guide partners API | REST API (outbound) | Internet (outbound) | Fake / poisoned data; MITM |

## Attacker and attack surface mapping

Cross-referencing the attacker classes from Task A against the entry points above highlights which surfaces need the most attention and which attackers share entry points.

| Attacker | Primary entry points |
|---|---|
| Cyber-criminals | Public REST API (auth and unauth), auth/account-recovery endpoints, Payment API, payment webhook, file upload endpoints, email (phishing → internal) |
| Script kiddies | Public REST API (unauthenticated endpoints), auth endpoints (credential stuffing from leaked lists) |
| Hacktivists | Public REST API (DDoS); web frontend / DNS (defacement) |
| Competitors | Email (phishing → CRM / business intelligence dashboard), partner API scraping |
| Malicious insiders | CRM, analytics dashboard, admin interface, internal APIs, backups — via legitimate credentials |
| Malicious business partners | Partner API gateway (inbound), webhook abuse, poisoned outbound responses |
| Nation-state actors | Admin / DevOps interfaces, customer database (long-dwell), backups, email (phishing → internal), mobile app binary (supply-chain tampering) |

Two observations follow from this mapping:

- **Email is a cross-cutting vector.** It's the initial foothold for cyber-criminals, competitors, and nation-state actors alike, even though it isn't a "system interface" in the traditional sense.
- **Internal interfaces are the insider's attack surface.** Malicious insiders rarely need to bypass controls — their attack surface is the set of tools they are already authorized to use, abused beyond their intended purpose.

## References

- OWASP Attack Surface Analysis Cheat Sheet - https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html