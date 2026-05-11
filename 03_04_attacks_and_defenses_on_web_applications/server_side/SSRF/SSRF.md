# Server-Side Request Forgery (SSRF)

## 1. Attack Class Description

Server-Side Request Forgery (SSRF) is a web security vulnerability that allows an attacker to induce the server-side application to make HTTP requests to an unintended location. Instead of the server fetching resources it is supposed to, the attacker manipulates it into contacting internal services, cloud metadata endpoints, or arbitrary external systems, all from the server's own network identity.

In a typical SSRF scenario, the attacker supplies or modifies a URL parameter that the server uses to fetch a resource. Because the request originates from the server itself, it often bypasses firewall rules, network segmentation, and access controls that would otherwise block an external attacker.

There are two primary variants:

- **Regular SSRF:** The attacker receives the response from the forged request (e.g., the server returns the body of the internal page).
- **Blind SSRF:** The server makes the forged request but does not return the response to the attacker. This is harder to exploit but can still be used for port scanning, service enumeration, or triggering side effects.

---

## 2. Impact of Exploiting SSRF Vulnerabilities

A successful SSRF exploit can have severe consequences for an organization:

- **Unauthorized access to internal services:** The attacker can reach internal APIs, admin panels, and databases that are not exposed to the public internet (e.g., `http://localhost/admin` or `http://192.168.0.68/admin`).
- **Authentication bypass:** Internal services often trust requests coming from the server itself or from within the local network, effectively granting attackers full access without credentials.
- **Cloud metadata exfiltration:** In cloud environments (AWS, GCP, Azure), SSRF is frequently used to query the instance metadata service and steal IAM credentials, API keys, and configuration data.
- **Arbitrary command execution:** In some configurations, SSRF can be chained with other vulnerabilities (e.g., internal services with RCE flaws) to achieve full remote code execution on the server or back-end components.
- **Lateral movement:** Once inside the internal network perimeter, the attacker can probe and attack other systems that are not directly reachable from the outside.
- **Data leakage:** Sensitive data such as authorization credentials, internal API responses, or configuration files may be returned directly to the attacker.
- **Reputational and legal damage:** Attacks on third-party systems appear to originate from the organization's own infrastructure, which can cause legal liability and reputational harm.

---

## 3. Software Vulnerabilities That Allow SSRF to Succeed

SSRF succeeds because of a combination of design flaws and missing validation in the application:

### 3.1 Unvalidated User-Supplied URLs

The most fundamental issue is that the application accepts a URL from the user and passes it directly to a server-side HTTP client without sanitization or validation. For example:

```text
POST /product/stock HTTP/1.0
Content-Type: application/x-www-form-urlencoded

stockApi=http://localhost/admin
```

The `stockApi` parameter is controlled by the attacker and the server fetches it without checking whether the destination is permitted.

### 3.2 Implicit Trust of Loopback and Internal Addresses

Applications and internal services often grant elevated trust to requests originating from `127.0.0.1` or `localhost`. Administrative interfaces may be accessible without authentication when accessed via the loopback interface, under the assumption that only a trusted process would make such a request. This assumption is broken by SSRF.

### 3.3 Weak or Bypassable Input Filters

Some applications attempt to block SSRF using blacklists (e.g., blocking `127.0.0.1` or `localhost`) or whitelists. These filters are often incomplete and can be bypassed using:

- **Alternative IP representations:**`2130706433` (decimal), `017700000001` (octal), `127.1`
- **URL encoding / double encoding** of blocked characters
- **Case variation** (`LocalHost`, `LOCALHOST`)
- **Custom domains** that resolve to `127.0.0.1`
- **Credential injection via `@`:**`https://expected-host:fakepassword@evil-host`
- **Fragment injection via `#`:**`https://evil-host#expected-host`
- **Subdomain injection:**`https://expected-host.evil-host`

### 3.4 Open Redirection in Allowed Domains

If the application uses a whitelist allowing specific domains, but one of those domains contains an open redirect vulnerability, the attacker can chain the two flaws:

```text
stockApi=http://trusted-site.com/redirect?path=http://192.168.0.68/admin
```

The server validates the trusted domain, follows the redirect, and ends up at the internal target.

### 3.5 SSRF via Data Formats (XXE)

Applications that parse XML or other data formats may issue network requests as a side effect of parsing. An XML parser that processes external entity declarations (`DOCTYPE` with a system identifier pointing to an internal URL) can be used as an SSRF vector via XXE injection.

### 3.6 SSRF via HTTP Headers

The `Referer` header is commonly logged and sometimes fetched by analytics software running server-side. An attacker can set the `Referer` header to an internal address, causing the analytics component to issue a request to that internal resource. This is a blind SSRF through a trusted subsystem.

### 3.7 Partial URL Construction

Applications that only accept a hostname or path segment and construct the full URL server-side may still be vulnerable if the partial input is not properly validated, allowing attackers to influence which host or path is contacted.

---

## 4. Countermeasures

### 4.1 Validate and Sanitize All User-Supplied URLs

Never pass user input directly to a server-side HTTP client. Apply strict validation:

- **Parse the URL:** using a trusted URL parsing library (not manual string checks).
- **Extract and verify the scheme:** only allow `http` and `https`; reject `file://`, `gopher://`, `ftp://`, `dict://`, etc.
- **Extract and verify the hostname:** resolve the hostname to an IP address *after* parsing and check the resolved IP against a deny-list of forbidden ranges.

### 4.2 Enforce a Strict Allowlist of Permitted Destinations

Rather than trying to block bad inputs (blacklisting), define an explicit allowlist of hosts, IP ranges, and ports that the server is permitted to contact. Reject all requests that do not match the allowlist. This is the most robust approach:

- Maintain a list of permitted external URLs or domains.
- Reject any URL not present in the allowlist.
- Do not allow user input to construct URLs dynamically from partial fragments.

### 4.3 Block Requests to Private, Loopback, and Link-Local Addresses

After resolving the hostname to an IP, verify that the resolved IP is not in a private or reserved range before making the request. Ranges to block include:

| Range | Description |
| --- | --- |
| `127.0.0.0/8` | Loopback |
| `10.0.0.0/8` | Private (RFC 1918) |
| `172.16.0.0/12` | Private (RFC 1918) |
| `192.168.0.0/16` | Private (RFC 1918) |
| `169.254.0.0/16` | Link-local / Cloud metadata |
| `::1/128` | IPv6 loopback |
| `fc00::/7` | IPv6 unique local |

**Important:**Perform the IP check *after* DNS resolution, and ensure the HTTP client does not follow redirects to a different (potentially internal) IP without re-checking. DNS rebinding attacks can be mitigated by resolving the hostname once and reusing the resolved IP for the actual connection.

### 4.4 Disable Unnecessary URL Schemes

Configure the HTTP client to only support `http` and `https`. Explicitly disable schemes such as `file://`, `gopher://`, `dict://`, `ftp://`, and `ldap://`, which can be used to access local files or interact with non-HTTP services.

### 4.5 Do Not Follow Redirects Blindly

If the server-side HTTP client is configured to follow redirects (e.g., HTTP 301/302), each redirect target must be re-validated against the allowlist and IP deny-list before the follow is executed. Alternatively, disable redirect following entirely and treat redirects as errors.

### 4.6 Segregate and Harden Internal Services

Apply the principle of least privilege to internal services:

- Internal services should require authentication even when accessed from the internal network. They should never implicitly trust the source IP.
- Place administrative interfaces on separate ports or networks that are unreachable from the application server.
- Use network-level controls (firewall rules, security groups) to restrict which services the application server can reach, even if SSRF is present.

### 4.7 Disable or Restrict Cloud Metadata Endpoints

For cloud-hosted applications, block access to metadata endpoints at the network level where possible. On AWS, use IMDSv2 (Instance Metadata Service v2), which requires a session token obtained via a `PUT` request. This prevents simple SSRF from fetching metadata using a `GET` request.

### 4.8 Use a Web Application Firewall (WAF)

A WAF can provide an additional layer of defense by detecting and blocking common SSRF payloads (e.g., requests containing `127.0.0.1`, `localhost`, `169.254.169.254`, encoded variants, etc.). However, a WAF alone is insufficient, it should complement, not replace, server-side validation.

### 4.9 Sanitize and Restrict XML Parsing

If the application processes XML, disable external entity processing in the XML parser to prevent XXE-based SSRF.

### 4.10 Log, Monitor, and Alert on Outbound Requests

Implement logging for all outbound HTTP requests made by the server. Monitor for:

- Requests to RFC 1918 / loopback / link-local addresses.
- Unusual or unexpected destination hosts.
- High volumes of outbound requests to uncommon ports.

Set up alerts so that anomalous outbound traffic is detected quickly, even if SSRF is not yet exploited successfully.

### 4.11 Conduct Regular Security Testing

Include SSRF in penetration testing and security assessments:

- Review all request parameters that accept URLs, hostnames, or IP addresses.
- Test partial URL parameters (only hostname or path) for SSRF exploitability.
- Check HTTP headers such as `Referer`, `X-Forwarded-For`, and custom headers used by back-end routing.
- Use tools like Burp Suite with Burp Collaborator to detect blind SSRF.

---

## Summary

SSRF is a critical vulnerability class that allows attackers to pivot from the public internet into an organization's internal infrastructure by abusing the server's ability to make outbound HTTP requests. The most effective defense is a combination of strict allowlist-based URL validation, IP deny-listing after DNS resolution, network segmentation with authenticated internal services, and continuous monitoring of outbound traffic. Defense-in-depth multiple overlapping controls is essential because no single countermeasure is sufficient on its own.
