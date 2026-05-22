# Authentication

## What is Authentication?

If you've ever used a website you've likely created an identity associated with it - an account. The process of the server verifing your identity and giving you access to the account is authentication. This immediatelly presents two potential targets:

- The information you store in the account (private information used to log in like password, email, phone number etc)
- Information and services you access based on your identity/account type

The three main types of authentication are:
1. Knowledge factor - something you know, like a password or an answer to a security question
2. Possession factor - a physical object like phone or YubiKey
3. Inherence factors - something you are, your biometrics 

Authorization and authentication are of course different, authorization verifies if you're allowed to do something, and authentification verifies if you are who you say you are. 

## What is the impact of exploiting these vurnabilities?

The impact can be severe. Giving the attacker the ability to misrepresent themselves as an existing account, especially one that is a highly priviliged opens the door to full control of the users data and all the services they're priviliged for.
Needless to say, the threat of having your account compromised would make users not want to use your website and services. And if the issue is caused by the vurnabilities in the companies software, you may be on the hook for legaly paying the damages.

In 2021 Coinbase - a website for buying and selling bitcoin had 6000 accounts compromised. The hackers already had the emails, passwords and phone numbers, but there was SMS MFA authentification. They couldnt login....BUT they didnt implement the SMS MFA in the account recovery page! So they gained access to the accounts and took the money. Coinbase announced that they will reinburse the money stolen for all the accounts to avoid legal trouble. 

## What the software vulnerabilies?

1. Vulnerabilities in password based login

- Brute forcing usernames - usernames are often emails, and for companies usually in a format like name.surname@company.com. Admin accounts are sometimes left with usernames admin or administrator.

- Brute forcing passwords - can be done the same way as usernames, but can also be infered from commonly used passwords, or if we require the user to change it on a regular basis they will likely make very minimal changes.

- Username enumeration - observing server responses to see if username exists. Make sure the status codes are all the same, dont make error messages different depending on if just the password or both the password and username are wrong. The response time can also be a tell, if we check the password only if the username passes it will result in slightly higher response times.

2. Vulnerabilities in MFA

Biometric factors are often impractical. It is important to remember that MFA uses 2 different factors, so you cant call MFA to use email verification and account password since they are both knowledge factors.

- SIM MFA is vurnable to sim swapping.
- Check if you made the second (MFA) step mandatory. If you ask for the password, and then send the user to a seperate different page for MFA you should check if they are in a logged in state. If they can reroute themselves to lets say homepage and be considered logged in.
  
- Flawed MFA verification logic – The application verifies the first login step (username/password) but fails to ensure that the same user completes the second authentication step. For example, if the account identity is stored in a client-controlled cookie, an attacker can modify it and attempt to complete MFA for another account.

- Brute forcing MFA codes – Verification codes are often only 4–6 digits long, making them vulnerable if proper protections are missing. Logging out a user after several failed attempts is often insufficient because attackers can automate the entire login process. Rate limits, account lockouts, CAPTCHAs, and attempt throttling should be implemented.

1. Vulnerabilities in other auth mechanisms

- "Remember me" – Websites use cookies to keep users logged in after closing the browser. When they generate cookies using predictable information like usernames, timestamps or passwords, instead of random values they get easier to guess. Thenan attacker may be able to create or brute force valid cookies

- Weak cookie protection – simply encoding or hashing cookies does not make them safe. Basic encoding like Base64 provides no real protection because it can easily be decoded. Even hashes can be brute forced if the algorithm is known and no salt is used.

- Passwords via email – email inboxes are not designed for secure storage and messages can be intercepted or accessed from multiple devices

- Predictable password reset links – Password reset links should contain long random tokens. If they use something predictable like reset-passowrd?username=john attackers can just change params

- Weak password change - password reset page should be as safe as te login page

## What are the ways to prevent these attacks?

1. User data needs to travel safe - Only send login data through secure encrypted connections. Any attempt of HTTP request should be redirected to HTTPS. Look into the data you send as a response from backend, never send back usernames or email addresses.

2. Don't trust no man - as with every security issue we need to be wary of the human error. People will want to bypass steps if possible, given the possibility for a lazy solution - users will take you up on it. Example is a password policy, dont rely on them to want a safe password, make sure there is a password checker that enforces rules. 

3. "If the account exists an email has been sent to it" - if you wondered why websites won't explicitly confirm to you that the email already exists as an account when trying to reset a password or won't tell you whether the email or the password is incorrect when logging in - it's because you shouldn't reveal sensitive data when not neccessary. The right person won't need that confirmation, but it could be valueable info to a hacker.

4. Force stop - brute force - different ways to do this is to add IP based user rate limit (but then make sure they cant manipulate their ip addresses), lock the account after many failed attempts or better yet use a CAPCHA test after login attempts. None of this is an absolute certain way to stop brute force attacks, but it makes it more likely to wear them down to giving up and moving to another target.

5. Check the logic in your code - if the logic of your check can be bipassed, that rule is only giving you a false sense of security.
   
6. You dont get authenticated at only login - dont forget about the forgot password pages etc.

7. MFA - multi factor authentification. It combines multiple factors we listed above: SMS - you need to know something (your number) and you need to have something (phone). However your SIM can be swapped. Dream scenario is to use an authentificator app that generated verification codes.  
