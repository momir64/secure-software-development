# File Upload Vulnerabilities

## 1. Attack Class Description

File upload vulnerabilities occur when a web server allows users to upload files without sufficiently validating their name, type, contents, or size. This can turn a basic image upload function into a vector for uploading arbitrary and potentially dangerous files, including server-side scripts that enable remote code execution (RCE).

The attack typically follows one of two patterns:

- The upload itself causes damage (overwriting a critical file).
- A follow-up HTTP request triggers the uploaded file's execution on the server.

Web Shell Deployment is the most severe form. If the server accepts and executes server-side scripts (PHP, Java, Python, etc.), an attacker can upload a web shell — a malicious script that executes arbitrary commands via HTTP requests. A minimal example:

```php
<?php system($_GET['cmd']); ?>
```

Accessed via: `GET /files/image.php?cmd=cat secret`

Exploitation techniques when defenses are in place:

- **Flawed MIME type validation** — The `Content-Type` header in `multipart/form-data` requests can be freely manipulated by the attacker. If the server trusts it without inspecting the actual file contents, simply setting `Content-Type: image/jpeg` on a PHP file bypasses the check.

- **Directory targeting** — Upload directories often have script execution disabled, but other directories may not. Using directory traversal in the `filename` field of the request can place the file in a more permissive location.

- **Blacklist bypass via obscure extensions** — Blacklists rarely cover every executable extension. Alternatives like `.php5`, `.phtml`, or `.phar` may still be executed by the server.

- **Overriding server configuration** — On Apache servers, uploading a malicious `.htaccess` file can instruct the server to treat a custom extension (like `.myext`) as executable PHP. IIS servers have an equivalent mechanism via `web.config`.

- **Extension obfuscation** — Multiple techniques can confuse validation logic:
  - Case variation: `exploit.pHp`
  - Multiple extensions: `exploit.php.jpg`
  - Trailing characters: `exploit.php.`
  - URL encoding: `exploit%2Ephp`
  - Null byte injection: `exploit.php%00.jpg`
  - Stripping bypass: `exploit.p.phphp` (removing `.php` leaves `.php`)

- **Polyglot files** — Tools like hex editors can embed malicious PHP code in a valid image file like JPEG or PNG (which starts with specific header and ends with a specific footer), bypassing content-based validation while still being a structurally valid image.

- **Race conditions** — Some servers upload the file to the filesystem first, validate it, then delete it if invalid. There is a window — even if brief — during which the file exists and can be executed.

**Exploitation without RCE:**

- **Stored XSS** — Uploading HTML or SVG files containing `<script>` tags creates stored XSS payloads that execute in other users browsers when they visit the page.
- **XXE injection** — If the server parses XML-based files (like `.docx`, `.xls`), they can be crafted to exploit XXE vulnerabilities in the parser.
- **PUT method abuse** — If the server supports HTTP `PUT` and lacks proper controls, files can be uploaded directly to arbitrary paths without using any upload UI at all.

## 2. Impact of Exploiting File Upload Vulnerabilities

Impact severity scales with what the server fails to validate and what it permits after upload:

- **Full server compromise** — A successfully deployed web shell grants read/write access to the filesystem, exfiltration of sensitive data, and the ability to pivot to internal infrastructure or external targets.
- **Arbitrary file overwrite** — If filenames are not validated, an attacker can overwrite critical server files by uploading a file with the same name. Combined with directory traversal, files outside the upload directory can be targeted.
- **Denial of Service (DoS)** — No file size limit allows an attacker to exhaust available disk space.
- **Client-side attacks** — Stored XSS via uploaded HTML/SVG can compromise other users sessions or credentials.
- **Data leakage** — A misconfigured server that serves executable files as plain text instead of running them exposes source code.

## 3. Software Vulnerabilities That Allow File Upload Vulnerabilities to Succeed

- **Trusting client-supplied MIME type** — Relying on the `Content-Type` header from the request rather than inspecting actual file contents.
- **Blacklist-based extension filtering** — Easier to bypass than whitelists; obscure or platform-specific extensions are routinely missed.
- **Inconsistent validation across the stack** — Validation applied at one layer (like the application) may not match behavior at another (like the web server or a reverse proxy behind a load balancer).
- **Permissive upload directories** — Allowing script execution in directories where user-uploaded files are stored.
- **Writable server configuration files** — Failure to prevent upload of `.htaccess` or `web.config` files that can redefine how the server handles file types.
- **Case-sensitive or narrow validation logic** — Validation that doesn't account for mixed case, multiple extensions, URL encoding, null bytes, or Unicode normalization tricks.
- **No content inspection** — Checking only the extension or MIME type without verifying magic bytes or actual file structure.
- **Race conditions in custom upload handling** — Writing the file to disk before completing validation, or using predictable temp directory names in URL-based upload flows.
- **HTTP PUT enabled without access controls** — Exposes an alternative file upload path outside the normal application UI.
- **Custom upload validation** — Custom implementations frequently miss edge cases that established frameworks handle correctly.

## 4. Countermeasures

- **Use established frameworks** — Prefer well-tested upload libraries over custom implementations.
- **Whitelist permitted file extensions** — Explicitly allow only the extensions the application needs (like `jpg`, `png`, `pdf`) rather than trying to block bad ones.
- **Validate file contents, not just metadata** — Check magic bytes and, where applicable, structural properties (like image dimensions) to confirm the file matches its claimed type.
- **Sanitize filenames** — Strip or reject any directory traversal sequences (`../`), null bytes, and other special characters. Rename files server-side to remove attacker control over the final filename.
- **Disable script execution in upload directories** — Configure the web server to never execute files in directories where user content is stored, regardless of extension.
- **Prevent upload of server configuration files** — Explicitly block `.htaccess`, `web.config`, and similar files.
- **Use a sandboxed staging area** — Do not write files to their final destination until all validation passes. Use randomized names for temporary files.
- **Enforce file size limits** — Reject uploads exceeding a defined threshold to prevent DoS via disk exhaustion.
- **Restrict or disable HTTP PUT** — Audit all endpoints for PUT support and disable it unless explicitly required, with proper access controls applied where it is needed.

## Summary

File upload vulnerabilities arise when applications fail to properly validate uploaded files — their name, type, size, or contents — allowing attackers to introduce malicious files onto the server. In the worst case, this leads to remote code execution via a deployed web shell, giving an attacker full server control. Lesser but still serious outcomes include stored XSS, arbitrary file overwrite, DoS, and source code disclosure. The root cause is almost always insufficient or bypassable validation: trusting client-supplied headers, using extension blacklists, applying checks inconsistently across the stack, or writing files to disk before validation completes. Effective defense requires whitelisting extensions, inspecting actual file contents, sanitizing filenames, disabling execution in upload directories, and relying on vetted frameworks rather than custom validation logic.
