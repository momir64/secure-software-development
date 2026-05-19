# Cross-origin resource sharing (CORS) vulnerabilities

## 1. Attack Class Description

CORS is a browser mechanism that relaxes the same-origin policy by letting servers declare which external origins may read their responses via HTTP headers (`Access-Control-Allow-Origin`, `Access-Control-Allow-Credentials`). CORS vulnerabilities arise when these headers are misconfigured, allowing attacker-controlled origins to read sensitive cross-origin responses in the victim's browser.

Common misconfigurations:
- Server reflects any `Origin` header value back in `Access-Control-Allow-Origin`
- Whitelist matching is too loose (prefix/suffix/regex errors), e.g. trusting `hackersnormal-website.com` when intending only `normal-website.com`
- `null` origin is whitelisted, exploitable via sandboxed iframes
- Trusted subdomain is vulnerable to XSS, which can be used to make credentialed CORS requests to the main domain
- HTTPS site whitelists an HTTP subdomain, allowing a MitM attacker to intercept HTTP traffic and inject a CORS request to the HTTPS site

## 2. Impact of Exploiting CORS Vulnerabilities

An attacker can read authenticated responses from a victim's session on the vulnerable site — anything the victim's browser can access. This includes API keys, personal data, and session-bound information. The victim just needs to visit the attacker's page while logged in.

## 3. Software Vulnerabilities That Allow CORS Vulnerabilities to Succeed

- Dynamic origin reflection without validation
- Flawed whitelist logic (regex/prefix/suffix matching mistakes)
- Whitelisted `null` origin
- Trusting subdomains that have XSS vulnerabilities
- Whitelisting HTTP origins on an HTTPS application
- Internal services using wildcard `Access-Control-Allow-Origin: *` assuming network-level protection is sufficient

## 4. Countermeasures

- Only allow explicitly trusted origins in `Access-Control-Allow-Origin`; never dynamically reflect the request's `Origin` without strict validation against a whitelist
- Never whitelist `null`
- Do not use wildcards on endpoints that serve sensitive data or accept credentials
- Ensure all trusted origins are HTTPS and free of XSS

## Summary

CORS vulnerabilities are misconfigurations, CORS itself is not flawed, the browser enforces it as designed. The vulnerability lies in the server being misconfigured to trust origins it shouldn't. The core risk is that a victim's authenticated session can be abused to leak sensitive data to an attacker's origin, purely by getting the victim to load a malicious page. Proper defenses require a strict, explicitly maintained origin whitelist and awareness that any trusted subdomain with XSS extends the attack surface.