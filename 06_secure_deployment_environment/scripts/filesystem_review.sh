#!/bin/bash

echo "--- FILESYSTEM REVIEW ---"

# Detect container environment
if [ -f /.dockerenv ]; then
    echo -e "\033[0;33m[INFO]\033[0m Running inside Docker container."
    echo "Filesystem and mount analysis may not reflect a normal Linux installation."
fi


# Mounted Partitions Review

echo -e "\n[*] Auditing mounted partitions (/etc/fstab):"

if [ -f /etc/fstab ]; then
    grep -v "^#" /etc/fstab

    echo -e "\n[*] Checking mount options..."

    TMP_ENTRY=$(grep -v "^#" /etc/fstab | grep -w "/tmp")
    HOME_ENTRY=$(grep -v "^#" /etc/fstab | grep -w "/home")

    # noatime check
    if grep -q "noatime" /etc/fstab; then
        echo -e "Status: \033[0;33m[WARNING]\033[0m 'noatime' detected."
        echo "  Access timestamps are disabled. This can reduce forensic visibility."
    else
        echo -e "Status: \033[0;32m[OK]\033[0m noatime not detected."
    fi

    # /tmp checks
    if [ -n "$TMP_ENTRY" ]; then

        if echo "$TMP_ENTRY" | grep -q "noexec"; then
            echo -e "Status: \033[0;32m[OK]\033[0m /tmp uses noexec."
        else
            echo -e "Status: \033[0;31m[WARNING]\033[0m /tmp missing noexec."
        fi

        if echo "$TMP_ENTRY" | grep -q "nosuid"; then
            echo -e "Status: \033[0;32m[OK]\033[0m /tmp uses nosuid."
        else
            echo -e "Status: \033[0;31m[WARNING]\033[0m /tmp missing nosuid."
        fi
    else
        echo -e "Status: \033[0;33m[INFO]\033[0m No separate /tmp mount found."
    fi


    # /home checks
    if [ -n "$HOME_ENTRY" ]; then

        if echo "$HOME_ENTRY" | grep -q "noexec"; then
            echo -e "Status: \033[0;32m[OK]\033[0m /home uses noexec."
        else
            echo -e "Status: \033[0;33m[INFO]\033[0m /home missing noexec."
        fi

        if echo "$HOME_ENTRY" | grep -q "nosuid"; then
            echo -e "Status: \033[0;32m[OK]\033[0m /home uses nosuid."
        else
            echo -e "Status: \033[0;33m[INFO]\033[0m /home missing nosuid."
        fi
    else
        echo -e "Status: \033[0;33m[INFO]\033[0m No separate /home mount found."
    fi



else
    echo -e "\033[0;31m[WARNING]\033[0m /etc/fstab not found."
fi



# Sensitive files review

echo -e "\n[*] Auditing sensitive file permissions:"

FILES=(
"/etc/shadow:640"
"/etc/mysql/my.cnf:640"
)

for item in "${FILES[@]}"
do

    FILE=$(echo "$item" | cut -d: -f1)
    MAXPERM=$(echo "$item" | cut -d: -f2)

    if [ -f "$FILE" ]; then

        PERMS=$(stat -c "%a" "$FILE")

        echo "$FILE -> permissions: $PERMS"

        if [ "$PERMS" -gt "$MAXPERM" ]; then
            echo -e "   \033[0;31m[WARNING]\033[0m Permissions too permissive."
        else
            echo -e "   \033[0;32m[OK]\033[0m Permissions acceptable."
        fi
    fi
done


# /etc/passwd handled separately

if [ -f /etc/passwd ]; then

    PERMS=$(stat -c "%a" /etc/passwd)

    echo "/etc/passwd -> permissions: $PERMS"

    if [ "$PERMS" = "644" ]; then
        echo -e "   \033[0;32m[OK]\033[0m Standard Linux permissions."
    else
        echo -e "   \033[0;33m[WARNING]\033[0m Non-standard passwd permissions."
    fi
fi



# Shadow backups

echo -e "\n[*] Looking for backup files (*.backup, *.old, *.bak):"

BACKUP_FILES=$(find / \
    \( -name "*.backup" -o -name "*.old" -o -name "*.bak" \) \
    2>/dev/null | grep -v "/proc")

if [ -z "$BACKUP_FILES" ]
then
    echo -e "Status: \033[0;32m[OK]\033[0m No backup files found."
else
    echo -e "Status: \033[0;33m[WARNING]\033[0m Backup files detected:"
    echo "$BACKUP_FILES"
fi


# SETUID review

echo -e "\n[*] Searching for SETUID files:"

SETUID_FILES=$(find / -perm -4000 2>/dev/null)

COUNT=$(echo "$SETUID_FILES" | wc -l)

echo "Found $COUNT SETUID files"

echo "$SETUID_FILES"

ROOT_SETUID=$(find / -user root -perm -4000 2>/dev/null | wc -l)

if [ "$ROOT_SETUID" -gt 30 ]
then
    echo -e "Status: \033[0;33m[WARNING]\033[0m Unusually high number of root-owned SETUID binaries."
else
    echo -e "Status: \033[0;32m[OK]\033[0m SETUID count within expected range."
fi

echo "Review SETUID entries manually for unexpected binaries."



# World readable + writable files

echo -e "\n[*] Looking for world-readable and writable files:"

RW_FILES=$(find / -type f -perm -006 2>/dev/null | grep -v "/proc")

if [ -z "$RW_FILES" ]
then
    echo -e "Status: \033[0;32m[OK]\033[0m No globally readable+writable files."
else
    echo -e "Status: \033[0;31m[WARNING]\033[0m Files readable and writable by everyone:"
    echo "$RW_FILES"
fi



echo -e "\n[*] Looking for world-writable files:"

WW_FILES=$(find / -type f -perm -002 2>/dev/null | grep -v "/proc")

if [ -z "$WW_FILES" ]
then
    echo -e "Status: \033[0;32m[OK]\033[0m No world-writable files."
else
    echo -e "Status: \033[0;31m[WARNING]\033[0m World writable files detected:"
    echo "$WW_FILES"
fi



# Backup audit

echo -e "\n[*] Auditing backup directories:"

for dir in /backup /var/backups
do

if [ -d "$dir" ]
then

    echo "Found: $dir"

    INSECURE=$(find "$dir" -type f \( -perm -004 -o -perm -002 \) 2>/dev/null)

    if [ -z "$INSECURE" ]
    then
        echo -e "Status: \033[0;32m[OK]\033[0m Backup permissions appear safe."
    else
        echo -e "Status: \033[0;31m[WARNING]\033[0m Insecure backup files:"
        echo "$INSECURE"
    fi

fi

done


echo -e "\n--- END OF FILESYSTEM REVIEW ---"