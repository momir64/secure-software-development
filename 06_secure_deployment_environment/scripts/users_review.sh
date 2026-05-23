#!/bin/bash

echo "--- USERS & AUTHENTICATION REVIEW ---"

# --- Root Enforcement Guard ---
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR]\033[0m This script must be run as root to accurately audit system secrets and shadow configurations."
    exit 1
fi

# Detect container environment
if [ -f /.dockerenv ]; then
    echo -e "\033[0;33m[INFO]\033[0m Running inside Docker container."
    echo "User and authentication analysis may differ from a standard Linux installation."
fi


# UID 0 review

echo -e "\n[*] Checking for users with UID 0:"

UID0_USERS=$(awk -F: '($3 == 0) {print $1}' /etc/passwd)
echo "$UID0_USERS"

# --- Safe newline/line counting via grep ---
COUNT=$(awk -F: '($3==0){count++} END{print count}' /etc/passwd)

if [ "$COUNT" -gt 1 ]; then
    echo -e "Status: \033[0;31m[WARNING]\033[0m Multiple users have UID 0."
else
    echo -e "Status: \033[0;32m[OK]\033[0m Only root-equivalent account detected."
fi


# Interactive shell review

echo -e "\n[*] Checking users with interactive shells:"

SHELL_USERS=$(awk -F: '$7 !~ /(nologin|false)$/ {print}' /etc/passwd)

if [ -z "$SHELL_USERS" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No interactive users found."
else
    echo "$SHELL_USERS"
    echo -e "Status: \033[0;33m[INFO]\033[0m Review service accounts for unnecessary shell access."
fi


# Duplicate UIDs

echo -e "\n[*] Checking for duplicate UIDs:"

DUP_UID=$(cut -d: -f3 /etc/passwd | sort | uniq -d)

if [ -z "$DUP_UID" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No duplicate UIDs found."
else
    echo -e "Status: \033[0;31m[WARNING]\033[0m Duplicate UIDs detected:"
    echo "$DUP_UID"
fi


# Duplicate usernames

echo -e "\n[*] Checking for duplicate usernames:"

DUP_USERS=$(cut -d: -f1 /etc/passwd | sort | uniq -d)

if [ -z "$DUP_USERS" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No duplicate usernames found."
else
    echo -e "Status: \033[0;31m[WARNING]\033[0m Duplicate usernames detected:"
    echo "$DUP_USERS"
fi


# Empty password review

echo -e "\n[*] Checking for empty passwords:"

EMPTY_PASS=$(awk -F: '($2==""){print $1}' /etc/shadow 2>/dev/null)

if [ -z "$EMPTY_PASS" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No accounts with empty passwords."
else
    echo -e "Status: \033[0;31m[WARNING]\033[0m Accounts with empty passwords:"
    echo "$EMPTY_PASS"
fi


# Password hash algorithm review

echo -e "\n[*] Reviewing password hash algorithms:"

awk -F: '
{
    user=$1
    hash=$2

    if(hash ~ /^\$/){

        split(hash,a,"$")

        if(a[2]=="1")
            print user": MD5"
        else if(a[2]=="2" || a[2]=="2a")
            print user": Blowfish/Bcrypt"
        else if(a[2]=="y")
            print user": Yescrypt"
        else if(a[2]=="5")
            print user": SHA256"
        else if(a[2]=="6")
            print user": SHA512"
    }
    else if(hash!="*" && hash!="!" && hash!="")
        print user": DES/Legacy crypt"
}
' /etc/shadow 2>/dev/null


# PAM hashing algorithm

echo -e "\n[*] Reviewing PAM password hashing configuration:"

if [ -f /etc/pam.d/common-password ]; then

    PAM_HASH=$(grep "pam_unix.so" /etc/pam.d/common-password)
    echo "$PAM_HASH"

    # --- Modified to accept modern algorithms like yescrypt or bcrypt alongside sha512 ---
    if echo "$PAM_HASH" | grep -qi -E "sha512|yescrypt|bcrypt"; then
        echo -e "Status: \033[0;32m[OK]\033[0m Secure hashing algorithm detected."
    else
        echo -e "Status: \033[0;33m[WARNING]\033[0m Preferred strong hashing algorithms not explicitly configured."
    fi
fi


# Password complexity

echo -e "\n[*] Reviewing password complexity rules:"

CRACKLIB=$(grep "pam_cracklib\|pam_pwquality" \
/etc/pam.d/common-password 2>/dev/null)

if [ -z "$CRACKLIB" ]; then
    echo -e "Status: \033[0;31m[WARNING]\033[0m No password complexity enforcement detected."
else
    echo "$CRACKLIB"
    echo -e "Status: \033[0;32m[OK]\033[0m Password complexity enabled."
fi


# Password expiration

echo -e "\n[*] Checking password expiration policies:"

# --- Performance Improvement (Only query accounts configured with interactive logins) ---
for user in $(grep -E "/(bash|sh|zsh|dash|tcsh)$" /etc/passwd | cut -d: -f1)
do
    EXP=$(chage -l "$user" 2>/dev/null | grep "Maximum")

    if [ -n "$EXP" ]; then
        echo "$user -> $EXP"
    fi
done


# System / non-login accounts

echo -e "\n[*] Checking System / non-login accounts:"

awk -F: '
{
    if($2 ~ /^!/ || $2 ~ /^\*/)
        print $1
}
' /etc/shadow 2>/dev/null


# Sudo NOPASSWD rules

echo -e "\n[*] Checking sudo NOPASSWD rules:"

NOPASS=$(grep -r "NOPASSWD" \
/etc/sudoers /etc/sudoers.d/ \
2>/dev/null | grep -v "^#")

if [ -z "$NOPASS" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No NOPASSWD rules found."
else
    echo -e "Status: \033[0;31m[WARNING]\033[0m NOPASSWD rules detected:"
    echo "$NOPASS"
fi


# Dangerous sudo commands

echo -e "\n[*] Looking for dangerous sudo permissions:"

# ---Word Boundaries (-w) applied to eliminate overlapping string false-positives ---
DANGER=$(grep -r -E \
"(^|[[:space:]])(chown|chmod|vi|less|find|awk|python|perl)([[:space:]]|$)" \
/etc/sudoers /etc/sudoers.d/ \
2>/dev/null | grep -v "^#")

if [ -z "$DANGER" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No dangerous sudo commands detected."
else
    echo -e "Status: \033[0;31m[WARNING]\033[0m Dangerous sudo rules found:"
    echo "$DANGER"
fi


# Privileged group review

echo -e "\n[*] Checking privileged group membership:"

getent group sudo 2>/dev/null
getent group wheel 2>/dev/null


# SSH review

echo -e "\n[*] Reviewing SSH access configuration:"

# ---  Added target lookup to parse modern Include directory parameters (.d/) ---
if [ -d /etc/ssh/sshd_config.d ] || [ -f /etc/ssh/sshd_config ]; then

    grep -r -E \
    "AllowUsers|DenyUsers|PermitRootLogin" \
    /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null | grep -v "^#"

else
    echo -e "Status: \033[0;33m[INFO]\033[0m SSH configuration files not found."
fi


# Home directory permissions

echo -e "\n[*] Checking home directory permissions:"

WORLD_HOME=$(find /home \
-maxdepth 1 \
-type d \
-perm -002 \
2>/dev/null)

if [ -z "$WORLD_HOME" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No world-writable home directories."
else
    echo -e "Status: \033[0;31m[WARNING]\033[0m World-writable home directories:"
    echo "$WORLD_HOME"
fi


# Dormant accounts

echo -e "\n[*] Reviewing account login activity:"

if command -v lastlog &>/dev/null; then
    lastlog
else
    echo -e "Status: \033[0;33m[INFO]\033[0m lastlog unavailable."
fi


echo -e "\n--- END OF USERS & AUTHENTICATION REVIEW ---"