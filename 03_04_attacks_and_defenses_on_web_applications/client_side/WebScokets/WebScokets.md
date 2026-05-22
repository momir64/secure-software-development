# WebSockets vulnerabilities

## 1. Attack Class Description

WebSockets provide persistent, two-sided communication channels initiated via an HTTP handshake. Because they can carry user input in both directions, virtually any HTTP-based vulnerability can appear in WebSocket messages as well — XSS, SQL injection, XXE, etc. Additionally, WebSockets introduce a unique attack: cross-site WebSocket hijacking (CSWSH), where an attacker's page establishes a WebSocket connection to a target server using the victim's cookies (since WebSockets send cookies automatically), then interacts with the connection on their behalf.

Common attack vectors:
- Unsanitized user input in WebSocket messages leading to XSS or injection vulnerabilities
- Cross-site WebSocket hijacking — exploiting lack of CSRF protection on the handshake to hijack the victim's WebSocket session from an attacker-controlled page

## 2. Impact of Exploiting WebSockets Vulnerabilities

- Performing privileged actions on behalf of the victim (CSWSH)
- Stealing sensitive data transmitted over the WebSocket connection (chat history, credentials, tokens)
- XSS via malicious message content rendered in another user's browser
- Server-side injection (SQLi, XXE) via WebSocket message payloads

## 3. Software Vulnerabilities That Allow WebSockets Vulnerabilities to Succeed

- No CSRF protection on the WebSocket handshake, allowing cross-origin connections using victim's cookies
- Unsanitized message content rendered in the browser or processed by the server
- Using plain `ws://` instead of `wss://`, exposing messages to interception
- Flawed session handling tied to the handshake context
- Trusting HTTP headers like `X-Forwarded-For` for security decisions during the handshake

## 4. Countermeasures

- Use `wss://` (WebSockets over TLS)
- Validate and sanitize all data received via WebSocket messages on both client and server
- Protect the handshake with CSRF tokens to prevent cross-site hijacking
- Do not make security decisions based on headers like `X-Forwarded-For`

## Summary

WebSockets inherit all the vulnerabilities of HTTP while adding their own, most notably cross-site WebSocket hijacking. CSWSH can happen because browsers automatically attach cookies to WebSocket handshakes without the same-origin restrictions. The attack surface covers both the message content (injection, XSS) and the connection handshake (CSRF, session flaws). Defenses require secure transport and server-side validation of all incoming WebSocket data, the same as any other user input.