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

