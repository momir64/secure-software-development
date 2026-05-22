# Network Review Script

## Description

This script audits the network stack and firewall configurations.

---

### Interface & Routing Surface Analysis

- **Functionality**: Maps all active network interfaces and the full routing table using `ip addr show` and `ip route show`.
- **Security Problem**: Unexpected or undocumented interfaces can indicate a rogue network attachment. An unrecognized route entry (e.g., a route through an unexpected gateway) may mean the host is dual-homed or that traffic is being silently redirected, allowing an attacker to bypass perimeter defenses or bridge isolated network segments.

### Promiscuous Mode Detection

- **Functionality**: Iterates over all interfaces and checks for the `PROMISC` flag via `ip link show`.
- **Security Problem**: An interface in promiscuous mode captures all packets on the segment, not just those addressed to the host. This is a strong indicator of active packet sniffing — either by a legitimate monitoring tool that was forgotten, or by malware performing passive credential harvesting.

### IP Forwarding Status Check

- **Functionality**: Reads `net.ipv4.ip_forward` and `net.ipv6.conf.all.forwarding` via `sysctl`.
- **Security Problem**: Enabled IP forwarding turns the host into a router capable of relaying traffic between network segments it should not bridge. On a standard server this setting should always be off. If enabled unexpectedly, it may indicate a misconfiguration or that the host has been repurposed as a pivot point inside the network.

---

### DNS Resolution Audit

- **Functionality**: Reads and displays the contents of `/etc/resolv.conf`, verifying that at least one nameserver is configured.
- **Security Problem**: Use of untrusted or unauthorized DNS servers can lead to DNS Spoofing or Hijacking, where traffic is redirected to malicious clones of legitimate services (e.g., fake update servers or phishing pages). A missing nameserver entry can also cause silent resolution failures that are difficult to diagnose.

### `/etc/hosts` Audit

- **Functionality**: Filters `/etc/hosts` for non-standard entries, excluding well-known localhost and IPv6 link-local lines.
- **Security Problem**: Unauthorized entries in `/etc/hosts` override DNS resolution entirely and take precedence over any nameserver. An attacker or malicious package that writes a single line here can silently redirect the host to attacker-controlled infrastructure for any domain — including package repositories and internal services — without any network-level change being visible.

---

### Firewall Policy Evaluation (IPv4 & IPv6)

- **Functionality**: Runs a full `iptables -L -v -n` and `ip6tables -L -v -n` dump and checks the default policy for each built-in chain.
- **Security Problem**: A default "ACCEPT" policy means that all traffic is permitted unless explicitly blocked. This is the opposite of the "Default Deny" principle — any service accidentally started by a developer, or any port opened by a package post-install script, is immediately exposed to the network with no manual firewall change required.

### Empty Chain Detection

- **Functionality**: Counts the number of rules in the INPUT, OUTPUT, and FORWARD chains and reports any that are empty.
- **Security Problem**: An empty chain with a default ACCEPT policy provides zero filtering. Even if rules are intended to be present, an empty chain may indicate that a rule-loading script failed silently on boot, leaving the host completely unprotected without any visible error.

### Egress (Outbound) Filtering Check

- **Functionality**: Checks the OUTPUT chain rule count and default policy to determine whether any outbound filtering is in place.
- **Security Problem**: Most firewalls focus exclusively on inbound traffic. Without egress filtering, a compromised host can freely communicate outward — exfiltrating data, downloading additional malware, or beaconing to a command-and-control server — with nothing to block or log it.

### SSH Port Configuration Check

- **Functionality**: Reads the `Port` directive from `/etc/ssh/sshd_config` to determine the configured SSH listening port.
- **Security Problem**: SSH running on the default port 22 is a constant target of automated scanning tools and brute-force bots. While changing the port is not a security control in isolation, it significantly reduces noise from opportunistic attacks and makes low-effort credential stuffing campaigns ineffective against the host.

---

### Firewall Persistence Verification

- **Functionality**: Scans for standard persistence files such as `/etc/iptables/rules.v4` and `/etc/network/if-pre-up.d/iptables` to confirm that rules will survive a reboot.
- **Security Problem**: Many administrators configure rules manually at runtime but never persist them. A system reboot — whether planned or caused by a crash — would completely erase the active ruleset and revert to an open or default state, silently removing the entire security perimeter.

### Saved vs. Active Rules Comparison

- **Functionality**: Compares the output of `iptables-save` against the contents of the saved rules file, if one exists.
- **Security Problem**: A mismatch between active and saved rules means that manual changes were made after the last save. A reboot would silently revert to the saved (different) ruleset without any warning, potentially re-opening ports that were deliberately closed or removing rules that were added in response to an incident.

---

### IPv6 Status Audit

- **Functionality**: Reads `net.ipv6.conf.all.disable_ipv6` via `sysctl` to determine whether IPv6 is active on the system.
- **Security Problem**: IPv6 is enabled by default on most modern Linux distributions, even when the network infrastructure does not use it. An active but unmonitored IPv6 stack is an invisible attack surface — tools and services may bind to IPv6 addresses without the administrator realizing it, and those endpoints will not appear in any IPv4-based scan or monitoring.

### IPv6 Firewall Coverage Check

- **Functionality**: If IPv6 is enabled, inspects the `ip6tables` INPUT chain policy and rule count to verify that filtering is in place.
- **Security Problem**: "IPv6 Leakage" occurs when security hardening is applied only to IPv4. An attacker who can communicate over IPv6 bypasses the entire IPv4 firewall ruleset. An INPUT chain with a default ACCEPT policy and no rules means all inbound IPv6 traffic is completely unrestricted, regardless of how strict the IPv4 configuration is.