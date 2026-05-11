# Clickjacking

## 1. Attack Class Description

Clickjacking, also known as **UI redressing**, is an interface-based attack in which a victim is tricked into clicking on actionable content belonging to a hidden, legitimate website while believing they are interacting with a visible decoy page. The attacker constructs a malicious webpage that embeds the target website inside a transparent `<iframe>` and overlays it precisely on top of innocent-looking content (e.g., a "Click here to win a prize" button). When the user clicks what they see, they are actually clicking on a hidden element from the target site, triggering an unintended action on their behalf.

The core mechanism relies on two CSS/HTML primitives:

- **`<iframe>`:** used to embed the target (victim) website as an invisible layer within the attacker's page.
- **CSS `opacity` and `z-index`:** the iframe is made fully transparent (`opacity: 0.00001`) and placed on top (`z-index: 2`) of the decoy content, so the user sees only the decoy but clicks on the hidden iframe.

### Attack Variants

- **Basic clickjacking:** A single hidden button or link on the target site is aligned with a visible decoy element. One user action (one click) triggers one unintended operation.
- **Clickjacking with prefilled form input:** The attacker uses GET parameters in the target URL to pre-populate form fields (e.g., an email address or transfer amount), so the user only needs to click "Submit" to complete an attacker-crafted action.
- **Multistep clickjacking:** Multiple sequential clicks are required (e.g., "Add to cart" then "Confirm purchase"). The attacker uses multiple overlapping iframes or decoy steps to capture each click in the correct order.
- **Clickjacking combined with DOM XSS:** Clickjacking is used as a delivery mechanism to trigger an existing Cross-Site Scripting vulnerability. The iframe URL includes an XSS payload, and the user's click executes the script in the context of the target origin.

### Difference from CSRF

Unlike Cross-Site Request Forgery (CSRF), clickjacking requires the user to perform a real action (e.g., a click). CSRF forges an entire HTTP request without any user interaction. Because clickjacking occurs within a legitimate browser session on the target domain, CSRF tokens do **not** mitigate it. The CSRF token is present and valid, but it is the user themselves (unwittingly) who submits it.

---

## 2. Impact of Exploiting Clickjacking Vulnerabilities

A successful clickjacking attack can have wide-ranging consequences depending on the functionality exposed on the target website:

- **Unauthorized financial transactions:** Tricking users into confirming payments, wire transfers, or purchases by clicking a hidden "Confirm" button.
- **Account takeover actions:** Causing users to change their email address, password, or linked phone number without their knowledge, enabling a follow-up account takeover.
- **Privilege escalation and administrative actions:** If the victim is an administrator, they may unknowingly promote other accounts, delete data, or change system settings.
- **Social media manipulation:** Historically used to inflate "likes," follows, or shares by making users interact with social media widgets embedded invisibly (so-called "likejacking").
- **Data exfiltration via DOM XSS chaining:** When combined with a DOM XSS vulnerability, clickjacking can result in script execution in the victim's browser, enabling session hijacking, credential theft, or arbitrary actions on behalf of the user.
- **Malware distribution:** Tricking users into clicking invisible "Download" or "Allow" buttons, initiating unwanted software installations or browser permission grants (e.g., microphone/camera access).
- **Bypassing user confirmations:** Any security-critical action that is protected only by a user confirmation dialog (rather than re-authentication) is potentially vulnerable.

---

## 3. Software Vulnerabilities That Allow Clickjacking to Succeed

### 3.1 Missing or Misconfigured Framing Controls

The fundamental vulnerability is that the target website does not restrict which origins are allowed to embed it inside an `<iframe>`. By default, browsers allow any page to frame any other page. If the server does not send `X-Frame-Options` or a `Content-Security-Policy: frame-ancestors` header, any attacker can embed the site.

### 3.2 Absence of the `X-Frame-Options` Header

Without this HTTP response header, the browser has no server-side instruction to prevent framing. The site can be embedded by any third-party page.

### 3.3 Absence or Incorrect Configuration of Content Security Policy (CSP)

A missing `frame-ancestors` directive in the CSP leaves the application unprotected. Misconfigured CSPs, such as using an overly broad `frame-ancestors *`, are equally ineffective.

### 3.4 Reliance on Weak Client-Side Frame Busting Scripts

Some applications attempt to prevent framing using JavaScript (e.g., checking `window.top !== window.self` and redirecting). These frame busting scripts can be neutralized by the attacker using the HTML5 `sandbox` attribute on the iframe:

```html
<iframe src="https://victim-website.com" sandbox="allow-forms"></iframe>
```

With `allow-forms` (or `allow-scripts`) set but `allow-top-navigation` omitted, the frame busting script cannot redirect the top-level window, rendering it useless while preserving form submission functionality within the frame.

### 3.5 Sensitive Actions Protected Only by a Single Click

Functionality that triggers significant effects (payments, account changes, data deletion) with a single click and no re-authentication challenge is inherently higher risk. Such actions rely entirely on the assumption that the user clicked intentionally, an assumption that clickjacking violates.

### 3.6 URL-Based Form Prepopulation (GET Parameters)

Web forms that accept data via GET parameters to pre-populate fields expose an additional attack surface. The attacker can craft a target URL that pre-fills fields with malicious values, reducing the attack to a single "Submit" click from the victim.

### 3.7 Existing DOM XSS Vulnerabilities

When a DOM-based XSS vulnerability exists on the target site, clickjacking can be used to trigger the XSS payload without requiring the victim to navigate to any crafted URL directly. The attacker embeds the XSS-bearing URL inside the iframe, and the user's click executes the payload.

---

## 4. Countermeasures

### 4.1 Set the `X-Frame-Options` HTTP Response Header

This header instructs the browser whether the page is permitted to be rendered inside a frame. It should be set on all pages that contain sensitive or actionable content.

| Directive | Effect |
| --- | --- |
| `X-Frame-Options: DENY` | Prevents framing by any origin, including the same site. |
| `X-Frame-Options: SAMEORIGIN` | Allows framing only by pages on the same origin. |
| `X-Frame-Options: ALLOW-FROM https://trusted.com` | Allows framing only from a specific origin (not supported in Chrome or Safari). |

**Recommended configuration for most applications:**

```text
X-Frame-Options: DENY
```

Apply this header consistently across the entire application, not just on login pages. Note that `ALLOW-FROM` has inconsistent browser support; prefer CSP `frame-ancestors` for fine-grained allowlisting.

### 4.2 Implement `Content-Security-Policy: frame-ancestors` (Preferred)

The `frame-ancestors` CSP directive is the modern, standards-based replacement for `X-Frame-Options`. It offers more granular control and is well-supported across all modern browsers.

| Directive | Effect |
| --- | --- |
| `frame-ancestors 'none'` | Equivalent to `X-Frame-Options: DENY` — no origin may frame the page. |
| `frame-ancestors 'self'` | Equivalent to `SAMEORIGIN` — only the same origin may frame the page. |
| `frame-ancestors https://trusted.com` | Only the specified origin may frame the page. |

**Recommended configuration for most applications:**

```text
Content-Security-Policy: frame-ancestors 'none';
```

For applications that need to embed their own pages in iframes (e.g., widget integration):

```text
Content-Security-Policy: frame-ancestors 'self';
```

CSP `frame-ancestors` takes precedence over `X-Frame-Options` in browsers that support both. For maximum compatibility, deploy **both** headers simultaneously.

### 4.3 Use Both Headers as a Defense-in-Depth Strategy

Some older browsers support `X-Frame-Options` but not CSP, and vice versa. To cover all browser versions, send both headers together:

```text
X-Frame-Options: DENY
Content-Security-Policy: frame-ancestors 'none';
```

This layered approach ensures protection regardless of the browser's level of standards support.

### 4.4 Require Re-Authentication for Sensitive Actions

High-impact operations (account deletion, email/password change, payment confirmation) should require the user to re-enter their password or complete a second-factor challenge before execution. This ensures that even if a user is tricked into clicking a hidden button, the action cannot complete without explicit credential confirmation, which the clickjacking attack cannot provide.

### 4.5 Use SameSite Cookie Attribute

Setting the `SameSite` attribute on session cookies to `Strict` or `Lax` limits cross-site cookie transmission. While primarily a CSRF defense, it reduces the effectiveness of clickjacking against cross-origin iframe scenarios where authentication cookies must be sent:

```text
Set-Cookie: session=abc123; SameSite=Strict; Secure; HttpOnly
```

Note that `SameSite` alone is not sufficient to prevent clickjacking when the attacker frames a page that the user is already authenticated to on the same browser.

### 4.6 Avoid Relying Solely on Frame Busting Scripts

Client-side JavaScript frame busting is inherently unreliable. The `sandbox` attribute on iframes can disable JavaScript navigation, neutralizing any frame buster. JavaScript may also be disabled in the browser. Frame busting scripts should **never** be the primary or sole defense. They may be used as a supplementary, best-effort layer only if server-side headers are also in place.

### 4.7 Validate and Sanitize GET-Based Form Prepopulation

If a web form uses GET parameters to prepopulate fields, validate all values server-side before rendering them into the form. Do not allow GET parameters to set fields that control the destination or amount of sensitive operations. Consider requiring POST-only form submissions for sensitive actions, and validate the `Origin` and `Referer` headers on the server side.

### 4.8 Apply a Strong Content Security Policy (Broad)

Beyond `frame-ancestors`, a well-crafted CSP restricts the sources from which scripts, styles, and other resources can be loaded. This limits the damage if a DOM XSS vulnerability exists that could be chained with clickjacking:

```text
Content-Security-Policy: default-src 'self'; script-src 'self'; frame-ancestors 'none';
```

### 4.9 Regular Security Testing

Include clickjacking in web application penetration tests and vulnerability assessments:

- Check all HTTP responses for the presence of `X-Frame-Options` and `Content-Security-Policy: frame-ancestors`.
- Attempt to manually embed the target site in an iframe from an external origin and confirm the browser blocks it.
- Use Burp Suite's Clickbandit tool to rapidly generate clickjacking proof-of-concept overlays and verify exploitability.
- Audit all high-sensitivity endpoints (account management, payments, admin actions) specifically for single-click exploitability.

### 4.10 Educate Users (Limited but Supplementary)

While user education cannot reliably prevent clickjacking (the attack is invisible by design), security-aware users may be more cautious about clicking elements on unfamiliar pages. More practically, organizations should ensure internal users (e.g., administrators) are briefed on the risks of clicking links from untrusted sources while authenticated to sensitive systems.

---

## Summary

Clickjacking is a UI deception attack that exploits the browser's ability to embed third-party pages in transparent iframes, tricking users into performing unintended actions on legitimate websites. The root cause is the absence of server-side controls that restrict page framing. The most effective and reliable countermeasures are the `X-Frame-Options: DENY` HTTP header and the `Content-Security-Policy: frame-ancestors 'none'` directive, deployed together for maximum browser coverage. These should be complemented by requiring re-authentication for sensitive operations, using `SameSite` cookies, and conducting regular security testing to verify that framing controls are correctly applied across all application endpoints.
