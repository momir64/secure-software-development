# Attacker Motivation

## Attackers

### 1. Cyber-Criminals

**Motivation**: Financial. MegaTravel's transaction volume, stored PII, payment data, and loyalty systems create multiple monetization paths. This can be exploited for data sales on dark web markets, ransomware, and fraudulent bookings for money laundering. Organized criminal groups select targets based on expected return versus effort, and travel platforms rank highly due to the density of valuable data per user record.

*Typical Attacks:* SQL Injection, credential stuffing using breach databases like Collection #1, phishing, ransomware deployment, carding attacks against stored payment methods, and account takeover to redeem loyalty points.

### 2. Malicious Insiders

**Motivation**: Financial gain, coercion, or revenge. Insiders bypass perimeter defenses entirely and already know where sensitive data lives. At 10,000 employees across global branches, monitoring is difficult and the attack surface is massive. The Verizon DBIR consistently identifies insiders as responsible for a disproportionate share of data breaches relative to their numbers, and dwell times before detection are typically measured in months. 

*Typical Attacks:* Bulk database exfiltration before resignation, planting backdoors in production code, privilege escalation, selling API credentials or internal access to criminal groups, and deliberate sabotage of critical systems.

### 3. Hacktivists

**Motivation**: Ideological. MegaTravel may be targeted over mass tourism's environmental impact, carbon emissions from air travel, or the displacement of local communities through over-tourism. Groups like Anonymous have historically targeted travel and hospitality companies over perceived ethical violations. Goal is public embarrassment rather than financial gain, with attacks timed for maximum media coverage.

*Typical Attacks*: DDoS during peak booking periods such as summer or holiday seasons, website defacement with political messaging, doxxing of executives, and leaking internal communications to journalists or activist networks.

### 4. Competitors

**Motivation**: Strategic. In a market dominated by Expedia, Booking.com, and Airbnb, access to MegaTravel's pricing algorithms, supplier contracts, customer data and marketing plans have direct commercial value. Corporate espionage in travel and hospitality is well-documented, and the line between aggressive competitive intelligence and illegal espionage is frequently crossed.

*Typical Attacks*: Spear-phishing of executives, API scraping to harvest pricing and availability data, social engineering of engineers and sales staff, recruiting disgruntled insiders, and planting moles in key departments.

### 5. Malicious Business Partners

**Motivation**: Financial or strategic gain by abuse of trusted access. MegaTravel's business model requires deep API integrations with airlines, hotel chains, car rental services, and payment processors. Partners with legitimate access have a privileged position inside the trust boundary that is difficult to monitor without degrading the partnership relationship itself. Disabling the use of the partners products while under investigation also contributes to a decline in service quality and customer satisfaction. 

*Typical Attacks:* Unauthorized API calls to harvest customer data beyond contractual scope, manipulation of pricing or availability feeds, injecting malicious code through shared SDKs or libraries, using partner credentials to pivot into systems outside their intended access scope, and exfiltrating data incrementally to avoid detection thresholds.

### 6. Script Kiddies

**Motivation**: Recognition, curiosity, and thrill-seeking with little technical sophistication. Opportunistic rather than targeted, they're drawn by MegaTravel's brand visibility and the social capital of claiming a recognizable victim. While individually low-impact, their automated scanning activity can expose unpatched vulnerabilities that more capable actors subsequently exploit, and their DDoS attacks can cause real revenue loss during peak periods. Additionally it places distrust in the public perception of the MegaTravel agency. 

*Typical Attacks:* Off-the-shelf DDoS tools such as LOIC, automated CVE scanners like Shodan and Metasploit modules, brute-force login attempts using public wordlists, and defacement via known CMS vulnerabilities.

### 7. Nation-State Actors

**Motivation**: Geopolitical intelligence. Travel booking records are among the richest open-source intelligence datasets available, revealing movement patterns of diplomats, military personnel, journalists, and corporate executives. MegaTravel's presence in Hong Kong adds particular sensitivity given ongoing geopolitical tensions. State actors are patient, well-resourced, and operate under legal immunity, making them the most dangerous attacker class. Secondary motivations may include mapping travel infrastructure for future sabotage operations.

*Typical Attacks:* Advanced Persistent Threats involving long-term low-and-slow network infiltration, supply chain attacks through compromised third-party software vendors, zero-day exploits against border-facing infrastructure, watering hole attacks targeting MegaTravel employees, and targeted surveillance of specific high-value individuals through their booking histories.

### Prominent Location-Based Attackers

#### 1. London

- **Scattered Spider** - While they have members globally, court proceedings in 2025/2026 have linked several key players to the UK, particularly the London area. They are famous for exploiting UK helpdesks by using high level "vishing" (voice phishing) to trick employees into resetting passwords. They were behind the MGM/Caesars attacks, which shows their targeting of travel and hospitality establishments.

#### 2. Hong Kong

- **APT41 (Double Dragon)** - They present a unique threat because they operate on a "dual-track" model: they perform state-sponsored espionage by day and financially motivated cybercrime (for personal profit) by night. They would be particularly dangerous for our agency because they have an interest in *PNR* (Passenger Name Record) data. They want to know the flight numbers, seat assignments and hotel stays of specific people. 


#### 3. Boston

Unlike London or Hong Kong, there are no well-documented, active hacker groups specifically tied to Boston. Cyber incidents in this region are more commonly associated with individual actors or loosely organized attackers rather than structured groups. The presence of major institutions such as MIT and Harvard University has also made the area a target for ideologically motivated attacks and protest-driven cyber activity in the past, rather than a source of organized cybercrime groups.
