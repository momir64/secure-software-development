# COMMITMENT

## Challenge Description

**Flag format:** csictf{}

The goal of this challenge was to track down the user `hoshimaseok` and find the hidden flag.

The hint was:

> hoshimaseok is up to no good. Track him down.

---

## Solution

### 1. Finding the GitHub account

The first step was searching for the username `hoshimaseok`.

A GitHub profile and related repositories were discovered through the search results.

![GitHub search](img/01.png)

---

### 2. Finding the target repository

After inspecting the GitHub results, I found the repository named `SomethingFishy`.

![GitHub repository](img/02.png)

---

### 3. Inspecting the repository

The repository was cloned locally and the available branches were checked.

The `dev` branch contained additional content, so it was pulled and searched.

I searched through the repository files for possible flag references.

![Repository search](img/03.png)

---

### 4. Checking commit history

Since no obvious flag was found in the files, I inspected the commit history.

A suspicious commit named:

> feat: Looking for flag?

was discovered.

Opening that commit revealed a file named `csicrf.txt`.

![Commit history](img/04.png)

---

### 5. Extracting the flag

Inside the `csicrf.txt` file there was a hidden message.

The important part was found in the comments:

```text
flag{d0_osint_c4n_b3_d1ff1cult}
```

![Flag comment](img/05.png)

---

## Flag

```text
csictf{d0_osint_c4n_b3_d1ff1cult}
```

---

## Tools Used

- Google Search
- GitHub
- Git
- Git log / commit history
- Repository file search
