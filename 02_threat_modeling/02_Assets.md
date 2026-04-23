# Assets

## Introduction

Identifying and prioritizing sensitive assets is the foundation of a robust risk assessment. As highlighted by the OWASP Risk Rating Methodology, risk cannot be accurately measured without first understanding the specific impact a compromise would have on the organization. For a global entity like MegaTravel, which manages data for over 100 million customers and coordinates with hundreds of third-party suppliers, the asset landscape is both vast and high-stakes. The following section evaluates the critical assets that sustain MegaTravel’s operations and the potential consequences of their failure.

Each asset below is examined through three lenses:

- **Exposure:** who has inherent access to the asset, both internally and externally, and through which systems or interfaces;
- **Security Goals (CIA):** the confidentiality, integrity, and availability requirements of the asset, each rated across four levels of criticality — **Low**, **Medium**, **High**, and **Critical**;
- **Impact:** the business, operational, and regulatory consequences of a security failure.

Relevant regulatory frameworks considered include the **EU General Data Protection Regulation (GDPR)** (applicable to the London HQ and all EU customer data), the **California Consumer Privacy Act (CCPA)** (applicable to the Boston operations serving US customers), the **Hong Kong Personal Data (Privacy) Ordinance (PDPO)**, and the **Payment Card Industry Data Security Standard (PCI DSS)** (applicable wherever payment card data is processed).

---

### 1. Customer Personal Data (PII)

MegaTravel collects and processes a wide range of personally identifiable information (PII) including full names, passport numbers, dates of birth, home addresses, phone numbers, email addresses, and nationality. All of these are required for international travel bookings.

**Exposure:** Accessible by customer-facing web and mobile application servers, internal customer service agents across all branches, booking management systems, and third-party accommodation and transport partners via API integrations.

**Security Goals (CIA):**

- *Confidentiality:* Critical. PII must not be disclosed to unauthorized parties.
- *Integrity:* High. Incorrect personal data can make a booking invalid and strand a customer.
- *Availability:* Medium. Service disruption is harmful but typically recoverable without permanent data loss.

**Impact:** A breach of customer PII exposes MegaTravel to enforcement actions under GDPR (fines up to €20 million or 4% of global annual turnover), CCPA, and PDPO. Beyond regulatory penalties, the reputational damage from exposing passport data or travel histories of 100+ million customers would be severe and potentially existential for customer trust.

---

### 2. Payment Card and Financial Data

MegaTravel processes payments for accommodations, transport, and vacation packages globally. This includes credit/debit card numbers, CVVs, expiry dates, billing addresses, and bank transfer details.

**Exposure:** Payment processing systems, third-party payment gateways, internal finance teams, and potentially back-office staff across all HQ locations. PCI DSS mandates strict segmentation of cardholder data environments (CDE), but with dozens of global branches, the enforcement perimeter is difficult to maintain uniformly.

**Security Goals (CIA):**

- *Confidentiality:* Critical. Cardholder data is a primary target for cyber-criminals.
- *Integrity:* Critical. Unauthorized modification of payment records constitutes fraud.
- *Availability:* High. Payment system downtime directly blocks revenue generation.

**Impact:** A breach of payment data triggers mandatory PCI DSS incident reporting, potential card scheme fines, and liability for fraudulent charges. Nation-state actors or organized criminal groups could use this data for large-scale financial fraud. Combined with the volume of transactions, even a short-duration breach could expose millions of records.

---

### 3. Authentication Credentials and Identity Data

This includes employee login credentials, customer account passwords, API keys issued to business partners, OAuth tokens, and administrative credentials for internal systems.

**Exposure:** Stored in identity providers and directory services (e.g., Active Directory) accessible to IT administrators. Customer credentials located in the web platform's authentication layer. API keys are distributed to dozens of third-party partners. With 10,000 employees across global offices, credential compromise is a significant concern.

**Security Goals (CIA):**

- *Confidentiality:* Critical. Compromised credentials are the most common initial access vector for both external attackers and malicious insiders.
- *Integrity:* High. Credential manipulation (e.g., privilege escalation) can silently expand an attacker's foothold.
- *Availability:* Medium. Lockouts affect productivity but are generally recoverable.

*Impact:* The compromise of administrative credentials allows attackers to navigate freely through MegaTravel’s internal network. This level of access enables the exfiltration of sensitive user data and the disruption of core business processes. Additionally, a leak of partner API keys extends the damage beyond the corporation's immediate perimeter, potentially compromising the security of the entire global integration layer and associated travel partners.

---

### 4. Operational Booking Data

This asset includes the complete records of customer travels, such as stays, transport, and scheduled activities. It represents the primary functional data MegaTravel uses to deliver its services.

**Exposure:** This data is widely shared across the internal booking engine, regional offices in London, Boston, and Hong Kong, and through external API integrations with third-party service providers (hotels and airlines).

**Security Goals (CIA):**

- *Confidentiality:* High. Information regarding travel schedules and locations is sensitive. Unauthorized access could lead to the tracking of individuals or the exposure of corporate travel habits.
- *Integrity:* Critical. The accuracy of these records is vital. Any unauthorized change to a reservation (e.g., date shifts or cancellations) results in immediate service failure and loss of customer trust.
- *Availability:* Critical. Constant access to these records is required for the business to function. Any downtime directly prevents customers from accessing their travel plans and halts new sales.

**Impact:** A breach of booking data allows threat actors to monitor or disrupt the movements of clients. Mass alteration or deletion of records by malicious actors would cause large-scale operational paralysis and significant financial penalties. Furthermore, competitors could analyze these data sets to gain insights into MegaTravel’s market share and pricing models.

---

### 5. Proprietary Business Data and Trade Secrets

This asset category includes proprietary business information such as supplier contracts, negotiated pricing structures, internal market algorithms, and long-term strategic plans. These elements represent the core competitive advantage of the corporation.

**Exposure:** Access is restricted to executive leadership, financial departments, and procurement teams within the primary headquarters. Information is typically stored in internal document management systems and secure collaboration platforms, with partial exposure to third-party partners during contract negotiations.

**Security Goals (CIA):**

- *Confidentiality:* Critical. Unauthorized disclosure of pricing models or supplier rates would directly compromise the corporation's market position, allowing competitors to exploit sensitive cost structures.
- *Integrity:* Medium. Modification of internal strategy documents is less immediately harmful but could cause misdirected decision-making.
- *Availability:* Low. These assets are not operationally time-critical in the same way as booking systems.

**Impact:** Competitors or malicious business partners with access to negotiated supplier rates could undercut MegaTravel's pricing. Leakage of customer segmentation models could enable targeted competitive campaigns. Insider threats represent the highest risk vector.

---

### 6. Internal IT Infrastructure and Configuration Data

This includes server configurations, network topology documentation, firewall rules, VPN credentials, cloud environment settings (IAM roles, storage bucket policies), and CI/CD pipeline access.

**Exposure:** Accessible to IT and DevOps teams. Given MegaTravel's global scale, infrastructure management may be delegated across regional teams, increasing the number of individuals with privileged access. Third-party managed service providers may also have partial access.

**Security Goals (CIA):**

- *Confidentiality:* High. Knowledge of network topology and firewall rules dramatically lowers the effort required to execute a targeted attack.
- *Integrity:* Critical. Unauthorized changes to firewall rules, IAM policies, or server configurations can silently open attack vectors.
- *Availability:* Critical. Infrastructure failure cascades into total service unavailability.

**Impact:** A malicious insider or external attacker with access to infrastructure configuration could disable security controls, exfiltrate data undetected, or cause a total platform outage. As seen in recent industry trends, misconfigured cloud assets are a primary vector for large-scale data breaches, making the integrity of these configurations a high-priority risk.

---

### 7. Employee Data

Personnel records including employment contracts, salary information, performance reviews, disciplinary records, and HR communications for 10,000 employees across multiple jurisdictions.

**Exposure:** HR systems accessible to HR personnel, department managers, and payroll providers. Subject to labor law and privacy protections in the UK (UK GDPR post-Brexit), the USA (CCPA for California employees), and Hong Kong (PDPO).

**Security Goals (CIA):**

- *Confidentiality:* High. Exposure of salary data or disciplinary records violates employee privacy and constitutes a regulatory breach.
- *Integrity:* Medium. Payroll record manipulation constitutes financial fraud.
- *Availability:* Low. HR system downtime is operationally disruptive but not immediately critical.

**Impact:** A breach of personnel records triggers mandatory notification requirements and significant regulatory fines. Furthermore, exposed HR data can be weaponized by external actors for social engineering or coercion. This is a critical concern, as it directly increases the "Malicious Insider" risk profile.

---

### 8. Third-Party Partner Integration Data

MegaTravel integrates with hundreds of external partners such as airlines, hotel chains, car rental services, and local tour operators, via APIs. These integrations carry shared credentials, data exchange agreements, and mutual system access.

**Exposure:** API gateways, integration middleware, and partner-facing portals. Each connected partner represents an additional attack surface, as the security of the integration is only as strong as the weakest partner's security posture.

**Security Goals (CIA):**

- *Confidentiality:* High. Partner API keys and shared data must not be exposed to unauthorized parties.
- *Integrity:* High. Malicious partners or compromised partner systems could inject false availability or pricing data, leading to fraudulent bookings.
- *Availability:* High. Partner API downtime degrades MegaTravel's ability to confirm bookings in real time, directly impacting customer experience.

**Impact:** Supply chain attacks via third-party integrations are an established and growing threat vector. A compromised partner could serve as a pivot point into MegaTravel's internal network, bypassing perimeter defenses entirely, a risk compounded by the number and geographic diversity of MegaTravel's supplier relationships.

## References

- OWASP Risk Rating Methodology — <https://owasp.org/www-community/OWASP_Risk_Rating_Methodology>
- EU General Data Protection Regulation (GDPR), Art. 83 — <https://gdpr-info.eu/art-83-gdpr/>
- California Consumer Privacy Act (CCPA) — <https://oag.ca.gov/privacy/ccpa>
- Hong Kong Personal Data (Privacy) Ordinance (PDPO) — <https://www.pcpd.org.hk/english/data_privacy_law/ordinance_at_a_Glance/ordinance.html>
