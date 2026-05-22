# DOM

## What is DOM?

DOM (Document Object Model) is a browsers representation of web page elements. We use JavaScript or similar to manipulate the nodes and objects of the DOM, as well as their properties. For example handling that when an action happens, a button changes color. 
The issue happens when websites have js that takes a value that the attacker can change and control (known as source) and passes it to a dangerous function (known as sink). So when values that can be changed by anyone, can affect the behavior of an impactful function.

## What is the impact of exploiting these vulnerabilies?

It depends on what the attacker can control and which sink is used, but it can be very severe. In the worst cases, an attacker can fully take over user interactions within the page without the server even being involved. This includes redirecting users to phishing sites, executing arbitrary JavaScript code in the context of the victim, or modifying what the user sees on the page to trick them into giving away sensitive information.

Because this all happens on the client side, traditional backend often doesn’t help - making DOM vulnerabilies especially dangerous.

The real-world impact includes:

- Account takeover via session theft (cookies)
- Phishing attacks that look identical to the real site
- Malware delivery via injected scripts or redirects
- Compromise of user trust in the application

Even when no data is directly stolen, the ability to control the page behavior and redirect users can still cause significant reputational and financial damage to the company.

## What the software vurnabilities?

First lets introduce some terms. 

Sources - a source is a js property that accepts data and can be attacker controlled. E.g. location.search property because it reads input from the query string - which the attacker can simply set. Anything that is mutable by a user can be dangerous, such as cookie (exposed by document.cookie string), reffering URL (exposed by document.referrer string) etc.

Sinks - a js function or DOM object that can be affected by this mutable input. Thats why we were told not to use eval() function because it will process the arg passed as javascript. document.body.innerHTML also can have an attacker insert html that will execute some js.

Most common source is the location object (the URL). For example if we're just checking that the location starts with https, the attacker can do https/legitling#https://evil-link. The script will slice this to use the last url and redirect to a malicious site.

Common cources are:
    document.URL
    location
    document.cookie
    document.referrer
    window.name
    localStorage
    ...

Common sinks:
    document.write()
    document.cookie
    window.location
    eval()
    element.src
    JSON.parse()
    ...


## What are the ways to prevent these attacks?

The main way to prevent DOM-based vulnerabilities is to strictly separate trusted and untrusted data, and ensure that user-controlled input never directly reaches dangerous sinks.

1. Avoid dangerous sinks - Functions like eval(), innerHTML, and direct assignment to location.href should be avoided where possible. If they must be used, input must be heavily sanitized and validated.
2. Use safe DOM APIs - Instead of innerHTML, use safer alternatives like textContent or createElement() and appendChild(), which do not interpret input as HTML or JavaScript.
3. Validate and whitelist inputs - Never trust values from sources like location, document.referrer, or window.name. If a URL is expected, enforce strict validation (for example only allowing same-origin URLs).
4. Avoid client-side trust assumptions - Do not assume anything coming from the browser is safe, even if it originates from your own site. Attackers can fully control the DOM environment.
5. Minimize DOM complexity for sensitive logic - Authentication, redirects, and security decisions should not rely on client-side JavaScript alone. These should always be enforced server-side where possible.

