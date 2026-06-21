# Reconnaissance

## Challenge Description

**Answers needed:** 
* attacker's email 
* attacker's full real name 
**Provided:** `SakuraSnowAngelAiko` username from previous step  
**Hint:** It appears that our attacker made a fatal mistake in their operational security. They seem to have reused their username across other social media platforms as well. This
should make it far easier for us to gather additional information on them by locating their other social media accounts.

---

## Solution

### 1. Google Search the username

![img.png](img/img1.png)

---

### 2. Finding email on the Contact Us page on attackers website

![img.png](img/img2.png)

It turns out this isn't the email that passes CTF check.

---

### 3. Finding PGP keys on the attackers GitHub

![img.png](img/img3.png)

![img.png](img/img4.png)

---

### 3. Analyzing PGP key to get the email

https://kriztalz.sh/pgp-key-analyser/

![img.png](img/img5.png)

---

### 4. Finding full name on the attackers Twitter page

![img.png](img/img6.png)

---

## Flag

**email:** `SakuraSnowAngel83@protonmail.com`  
**full name:** `Aiko Abe`

---

## Tools Used

- Google Search
- GitHub
- Twitter
- kriztalz's Security Tools (Analyze PGP/OpenPGP Public Keys)