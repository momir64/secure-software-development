#!/bin/bash
echo "--- SYSTEM REVIEW ---"

# Operating System
echo "[*] Checking operating system..."
if [ -f /etc/debian_version ]; then
    OS_VER=$(cat /etc/debian_version)
    echo "OS: Debian $OS_VER"
else
    OS_VER=$(cat /etc/issue | head -n 1)
    echo "OS: $OS_VER"
fi

# Kernel and Uptime
echo -e "\n[*] Kernel version and uptime:"
uname -a
uptime

echo -e "\n[*] Kernel uptime analysis:"
UPTIME_DAYS=$(awk '{print int($1/86400)}' /proc/uptime)
if [ "$UPTIME_DAYS" -gt 30 ]; then
    echo -e "Status: \033[0;33m[INFO]\033[0m System has been up for $UPTIME_DAYS days. Kernel may not have been patched recently."
else
    echo -e "Status: \033[0;32m[OK]\033[0m System uptime is $UPTIME_DAYS days."
fi

# Time Management
echo -e "\n[*] Auditing Time Management..."
date
# Check for timezone
TZ=$(cat /etc/timezone 2>/dev/null || echo "Not set")
echo "Timezone: $TZ"

# Check for NTP/Chrony
if pgrep -x "ntpd" > /dev/null || pgrep -x "chronyd" > /dev/null; then
    echo -e "Status: \033[0;32m[OK]\033[0m NTP/Chrony service is running."
else
    echo -e "Status: \033[0;31m[WARNING]\033[0m No time sync daemon found. Timestamps might be inaccurate."
fi

# Check NTP peer connectivity
echo -e "\n[*] NTP peer connectivity:"
if command -v ntpq &>/dev/null; then
    NTP_PEERS=$(ntpq -p -n 2>/dev/null)
    if [ -z "$NTP_PEERS" ]; then
        echo -e "Status: \033[0;31m[WARNING]\033[0m ntpq returned no peers. NTP may not be reachable."
    else
        echo "$NTP_PEERS"
        if echo "$NTP_PEERS" | grep -q '^\*'; then
            echo -e "Status: \033[0;32m[OK]\033[0m At least one NTP peer is synchronized (marked with *)."
        else
            echo -e "Status: \033[0;33m[WARNING]\033[0m No synchronized NTP peer found (no * marker). Time may be drifting."
        fi
    fi
elif command -v chronyc &>/dev/null; then
    chronyc tracking 2>/dev/null || echo "chronyc tracking failed."
else
    echo -e "Status: \033[0;33m[INFO]\033[0m Neither ntpq nor chronyc available for peer check."
fi

# Installed Packages
echo -e "\n[*] Installed packages:"
dpkg -l

# Check for broken packages
echo -n "\n[*] Checking for broken or partially installed packages: "
BROKEN=$(dpkg -l | grep -v "^ii" | grep -v "^rc" | tail -n +6 | wc -l)

if [ "$BROKEN" -gt 0 ]; then
    echo -e "\033[0;31m[WARNING]\033[0m Found $BROKEN packages in inconsistent state."
    dpkg -l | grep -v "^ii" | grep -v "^rc" | tail -n +6
else
    echo -e "\033[0;32m[OK]\033[0m All installed packages are in 'ii' state."
fi

# Check for available security updates
echo -e "\n[*] Checking for available security updates:"
if command -v apt-get &>/dev/null; then
    # Samo simulacija (dry-run), ne instalira nista
    UPGRADABLE=$(apt-get --just-print upgrade 2>/dev/null | grep "^Inst" | wc -l)
    SECURITY_UPGRADABLE=$(apt-get --just-print upgrade 2>/dev/null | grep "^Inst" | grep -i security | wc -l)
    echo "Total upgradable packages: $UPGRADABLE"
    if [ "$SECURITY_UPGRADABLE" -gt 0 ]; then
        echo -e "Status: \033[0;31m[WARNING]\033[0m $SECURITY_UPGRADABLE security update(s) available:"
        apt-get --just-print upgrade 2>/dev/null | grep "^Inst" | grep -i security
    else
        echo -e "Status: \033[0;32m[OK]\033[0m No pending security updates detected."
    fi
else
    echo -e "Status: \033[0;33m[INFO]\033[0m apt-get not available."
fi

# Check rc (removed-config) packages
echo -e "\n[*] Checking for packages with residual config files (rc state):"
RC_PKGS=$(dpkg -l | grep "^rc" | awk '{print $2}')
if [ -z "$RC_PKGS" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No packages in 'rc' (removed with config) state."
else
    echo -e "Status: \033[0;33m[WARNING]\033[0m The following packages were removed but left config files:"
    echo "$RC_PKGS"
    echo "  Consider running: dpkg --purge \$(dpkg -l | grep '^rc' | awk '{print \$2}')"
fi

# Logging status
echo -e "\n[*] Auditing System Logging (rsyslog):"
RSYSLOG_PROC=$(ps -edf | grep rsyslog | grep -v grep)
if [ -z "$RSYSLOG_PROC" ]; then
    echo -e "Status: \033[0;31m[WARNING]\033[0m rsyslog is NOT running. Events are not being logged."
else
    echo "$RSYSLOG_PROC"
    echo -e "Status: \033[0;32m[OK]\033[0m rsyslog is active."
fi

# Remote logging check
if [ -f /etc/rsyslog.conf ]; then
    REMOTE_LOG=$(grep -E "^[^#].*@.*" /etc/rsyslog.conf)
    if [ -z "$REMOTE_LOG" ]; then
        echo -e "Remote Logging: \033[0;33m[INFO]\033[0m No remote logging configured in /etc/rsyslog.conf."
    else
        echo "Remote Logging Config: $REMOTE_LOG"
    fi
fi

# Check permissions on log files
echo -e "\n[*] Checking permissions on log files in /var/log:"
WORLD_READABLE_LOGS=$(find /var/log -maxdepth 2 -type f -perm -o+r 2>/dev/null)
if [ -z "$WORLD_READABLE_LOGS" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No world-readable log files found in /var/log."
else
    echo -e "Status: \033[0;33m[WARNING]\033[0m The following log files are world-readable:"
    echo "$WORLD_READABLE_LOGS"
fi

# Check for world-writable log files
WORLD_WRITABLE_LOGS=$(find /var/log -maxdepth 2 -type f -perm -o+w 2>/dev/null)
if [ -n "$WORLD_WRITABLE_LOGS" ]; then
    echo -e "Status: \033[0;31m[WARNING]\033[0m World-writable log files found (attacker could tamper):"
    echo "$WORLD_WRITABLE_LOGS"
fi

# Check log rotation configuration
echo -e "\n[*] Checking log rotation configuration:"
if [ -f /etc/logrotate.conf ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m /etc/logrotate.conf exists."
    # Proveri da li je compress ukljucen
    if grep -q "compress" /etc/logrotate.conf; then
        echo "  Log compression is enabled."
    else
        echo -e "  \033[0;33m[INFO]\033[0m Log compression not set globally in logrotate.conf."
    fi
else
    echo -e "Status: \033[0;31m[WARNING]\033[0m /etc/logrotate.conf not found. Log rotation may not be configured."
fi

echo -e "\n--- END OF SYSTEM REVIEW ---"