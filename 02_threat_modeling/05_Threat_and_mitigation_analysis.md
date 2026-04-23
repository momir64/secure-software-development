# Threat and Mitigation Analysis

## Spoofing

Spoofing involves an attacker falsely claiming to be another user, system, or component.

### Spoofing of Web / Mobile Client

- **Description:** An attacker forges a valid user session or impersonates a legitimate customer to access the booking platform. Session tokens or credentials could be stolen and replayed.

- **Mitigation:** Short-lived, signed JWT with strict expiry and rotation should be used. Multi-factor authentication should be required, especially for financial actions. Cross-site request forgery protection should be implemented on all state-changing endpoints.

### Spoofing of External Provider

- **Description:** A malicious actor pretends to be a legitimate service provider (e.g., accommodation or transport partner) and injects fraudulent availability, pricing, or booking confirmation data into the Web APP. The same risk applies to the Email/SMS provider, where an attacker impersonating the notification service could deliver fraudulent password reset links, fake booking confirmations, or capture one-time passwords intended for legitimate users.

- **Mitigation:** All third-party integrations, including provider and notification service APIs, should be authenticated using API keys, OAuth 2.0 client credentials, or mutual TLS (mTLS). All incoming provider data should be validated against expected schemas and business rules, and anomalous behaviour (e.g., sudden price changes or unusual booking patterns) should be monitored. For the Email/SMS provider specifically, DomainKeys Identified Mail and Sender Policy Framework records should be configured to allow recipients to verify email authenticity, and delivery receipts should be validated to detect potential interception or redirection.

### Spoofing the Payment Service Provider

- **Description:** An attacker impersonates the payment gateway, redirecting payment flows to fraudulent endpoints or injecting false payment confirmation responses to confirm bookings without actual payment.

- **Mitigation:** Payment gateway identity should be validated using TLS certificate pinning or mutual TLS. All payment confirmation messages should be cryptographically signed and verified before updating booking state. Webhook secrets should be used to validate callbacks from the payment provider, and a payment confirmation should never be trusted solely based on a callback without independent status verification via the provider's API.

## Tampering

Tampering involves the unauthorised modification of data in transit or at rest.

### Tampering with Auth Configuration

- **Description:** An attacker modifies authentication policy settings (e.g., password policies, token expiry, allowed algorithms), weakening security controls across the entire platform.

- **Mitigation:** Configuration files should be signed with an asymmetric key, with the Auth Processor verifying signatures on startup and at read time. Write access to configuration stores should be restricted to the System Administrator role with mandatory approval workflows, and all configuration changes should be recorded in immutable audit logs.

### Tampering with Web APP Configuration

- **Description:** An attacker alters Web APP configuration to redirect users to phishing endpoints, disable security headers, or enable debug features in production.

- **Mitigation:** The same controls as for Auth Configuration apply: signed configs and strict write-access role-based access control. Configuration changes should be deployed exclusively via CI/CD pipeline with peer review, not edited in-place. Configuration hashes should be monitored at runtime with alerts triggered on unexpected changes.

## Repudiation

Repudiation involves a user or system denying that an action was performed, without the ability to prove otherwise.

### System Administrator Denying Configuration Changes

- **Description:** An administrator makes a malicious or erroneous configuration change and later denies responsibility. The absence of an audit trail on configuration stores enables plausible deniability.

- **Mitigation:** Individual administrator accounts should be enforced with shared credentials prohibited. All configuration changes should be logged with the authenticated identity, timestamp, and before/after values to an append-only audit log. A four-eyes approval policy should be implemented requiring a second administrator to approve sensitive configuration changes, and real-time alerts should be sent to the security team for all production configuration modifications.

### Customer Support Agent Denying CRM Data Access

- **Description:** A customer support agent accesses or exports sensitive customer personally identifiable information through the CRM platform — including passport numbers, booking histories, and contact details — and later denies having done so. Given that support agents have the broadest legitimate read access to customer data of any internal role, unlogged access is a significant insider repudiation risk.

- **Mitigation:** All CRM data access and export events should be logged with the agent's identity, timestamp, and the specific records accessed. Bulk data exports should require an explicit justification field and trigger a real-time alert to a supervisor or security team. Read-access audit trails should be maintained at the database layer for any queries returning sensitive fields such as passport numbers or payment history.

### Partner Provider Denying a Booking Confirmation

- **Description:** When MegaTravel confirms a hotel, transport, or tour booking via a partner API, the partner may later deny having issued the confirmation, leaving the customer without their booked service and MegaTravel unable to prove the exchange occurred. This risk is compounded by tour guide and smaller transport partners, which are explicitly noted as having weaker security postures and may lack reliable audit infrastructure on their end.

- **Mitigation:** All booking confirmation exchanges with partner APIs should be logged with a cryptographic signature covering the confirmation payload, timestamp, and partner identifier, stored in a tamper-evident, append-only log store. Partners should be required to return signed confirmation receipts as part of the API contract, and these receipts should be retained immutably. Where a partner cannot provide signed receipts, alternative confirmation channels such as email should be retained as fallback evidence.

## Information Disclosure

Information disclosure involves the exposure of sensitive data to unauthorised parties.

### Exposure of Credentials from the Credentials DB

- **Description:** An attacker targets the Credentials DB via SQL injection or by compromising the Auth Processor’s service account to bypass at-rest encryption. The goal is to extract salted hashes or intercept decrypted data through authorized application channels. Even with encryption active, the threat persists through potential key mismanagement or offline brute-force attacks on the extracted hashes.

- **Mitigation:** The system utilizes memory-hard hashing (Argon2 or bcrypt) and restricts DB access exclusively to the Auth Processor via strict IAM roles and network whitelisting. Security is maintained through KMS-integrated key rotation and CI/CD secret scanning. Additionally, real-time anomaly detection monitors query volumes to immediately flag and alert on any suspicious bulk data extraction attempts.

### Sensitive Payment Data Exposure via Payment DB

- **Description:** An attacker or malicious insider attempts to exfiltrate payment card data or transaction history from the Payment DB. Although the database is encrypted, the threat involves bypassing access controls or compromising the Payment Processor service account to access decrypted records. The risk centers on the potential exposure of transaction details or improperly stored card identifiers through authorized database channels.

- **Mitigation:** The system maintains strict PCI-DSS compliance by utilizing tokenization instead of storing full PAN or CVV data, ensuring that the most sensitive details are never present in the store. Access is restricted to the Payment Processor via granular IAM roles, supplemented by database activity monitoring that alerts on bulk data access. Furthermore, security is validated through annual penetration tests and audits, ensuring that encryption keys and access policies remain resilient against evolving exfiltration techniques.

### Compromise of Transit via Protocol Vulnerabilities

- **Description:** An attacker positioned on the network attempts to intercept client-facing traffic by exploiting weaknesses in the TLS implementation rather than cleartext streams. This involves forcing "downgrade" attacks to older, insecure protocols (like SSLv3) or intercepting traffic via mismanaged or expired certificates. If successful, the attacker can decrypt session tokens and personal itinerary data, rendering the existing encryption ineffective.

- **Mitigation:** The system enforces HSTS (HTTP Strict Transport Security) to prevent downgrade attacks and mandates the use of TLS 1.3 with strong cipher suites, disabling all legacy protocols. Certificate integrity is maintained through automated lifecycle management (e.g., Let's Encrypt or AWS ACM) and robust Certificate Authority (CA) validation. To further protect session integrity, all cookies are flagged with Secure and HttpOnly attributes, ensuring they are never transmitted over unencrypted channels or exposed to client-side scripts.

### Information Leakage via External Notification Channels

Information disclosure involves the exposure of sensitive data to unauthorised parties.

- **Description:** Sensitive booking details, or partial transaction data may be exposed when transmitted to external Email/SMS providers. While the communication flow to the provider is encrypted, the primary risk involves the exposure of sensitive data once it leaves the corporate trust boundary, potentially being retained in provider logs or intercepted at the final delivery stage to the user. The threat centers on the unintended disclosure of travel itineraries or financial identifiers through these less secure third-party communication channels.

- **Mitigation:** The system minimizes the inclusion of personal data in notification payloads by replacing full details with secure, authenticated links that direct users back to the MegaTravel portal. Communication with providers is strictly enforced over TLS, and all outgoing content is stripped of sensitive financial data, such as partial card numbers. Furthermore, data security is governed by rigorous Data Processing Agreements (DPA) to ensure GDPR compliance, while automated redaction logic is applied to ensure that only the essential information required for the notification is ever processed by external services.

