#!/bin/bash

echo "--- SERVICES REVIEW ---"

if [ -f /.dockerenv ]; then
    echo -e "\033[0;33m[INFO]\033[0m Running inside Docker container."
    echo "Service analysis may differ from a standard Linux installation."
fi


# Running processes

echo -e "\n[*] Auditing running processes:"
ps -edf


# TCP listening services

echo -e "\n[*] Checking TCP listening services:"
if command -v lsof &>/dev/null; then
    lsof -i TCP -n -P | grep LISTEN
elif command -v ss &>/dev/null; then
    ss -tlnp
elif command -v netstat &>/dev/null; then
    netstat -tlnp
else
    echo -e "Status: \033[0;33m[INFO]\033[0m No suitable tool found (lsof, ss, netstat)."
fi


# UDP listening services

echo -e "\n[*] Checking UDP listening services:"
if command -v lsof &>/dev/null; then
    lsof -i UDP -n -P
elif command -v ss &>/dev/null; then
    ss -ulnp
elif command -v netstat &>/dev/null; then
    netstat -ulnp
else
    echo -e "Status: \033[0;33m[INFO]\033[0m No suitable tool found (lsof, ss, netstat)."
fi


# Services exposed on all interfaces

echo -e "\n[*] Checking for services listening on all interfaces:"
EXPOSED_SERVICES=$(lsof -i TCP -n -P 2>/dev/null | grep LISTEN | grep -E "\*:|0\.0\.0\.0:|:::")
if [ -z "$EXPOSED_SERVICES" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No services detected listening on all interfaces."
else
    echo -e "Status: \033[0;33m[WARNING]\033[0m Services exposed on all interfaces (verify each is intentional and firewalled):"
    echo "$EXPOSED_SERVICES"
fi


# SSH configuration

echo -e "\n[*] Auditing SSH daemon configuration:"

SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_D="/etc/ssh/sshd_config.d"

if [ -f "$SSH_CONFIG" ] || [ -d "$SSH_CONFIG_D" ]; then

    PERMIT_ROOT=$(grep -r -E "^PermitRootLogin" "$SSH_CONFIG" "$SSH_CONFIG_D"/ 2>/dev/null | awk '{print $2}' | head -1)
    if [ -z "$PERMIT_ROOT" ]; then
        echo -e "  \033[0;33m[INFO]\033[0m PermitRootLogin not explicitly set. Default behavior varies by OpenSSH version."
    elif echo "$PERMIT_ROOT" | grep -qi "^yes$"; then
        echo -e "  \033[0;31m[WARNING]\033[0m PermitRootLogin is '$PERMIT_ROOT'. Direct root SSH login is enabled."
    else
        echo -e "  \033[0;32m[OK]\033[0m PermitRootLogin is '$PERMIT_ROOT'."
    fi

    TCP_FWD=$(grep -r -E "^AllowTcpForwarding" "$SSH_CONFIG" "$SSH_CONFIG_D"/ 2>/dev/null | awk '{print $2}' | head -1)
    if [ -z "$TCP_FWD" ] || echo "$TCP_FWD" | grep -qi "^yes$"; then
        echo -e "  \033[0;33m[WARNING]\033[0m AllowTcpForwarding is '${TCP_FWD:-yes (default)}'. Can be abused to bypass network controls."
    else
        echo -e "  \033[0;32m[OK]\033[0m AllowTcpForwarding is '$TCP_FWD'."
    fi

    SSH_PROTO=$(grep -r -E "^Protocol" "$SSH_CONFIG" "$SSH_CONFIG_D"/ 2>/dev/null | awk '{print $2}' | head -1)
    if [ -n "$SSH_PROTO" ] && [ "$SSH_PROTO" != "2" ]; then
        echo -e "  \033[0;31m[WARNING]\033[0m SSH Protocol is set to '$SSH_PROTO'. Only Protocol 2 should be used."
    else
        echo -e "  \033[0;32m[OK]\033[0m SSH Protocol 2 enforced (or implicit in modern OpenSSH)."
    fi

    MAX_AUTH=$(grep -r -E "^MaxAuthTries" "$SSH_CONFIG" "$SSH_CONFIG_D"/ 2>/dev/null | awk '{print $2}' | head -1)
    if [ -z "$MAX_AUTH" ]; then
        echo -e "  \033[0;33m[INFO]\033[0m MaxAuthTries not set (default is 6). Consider reducing to 3."
    elif [ "$MAX_AUTH" -gt 3 ]; then
        echo -e "  \033[0;33m[WARNING]\033[0m MaxAuthTries is $MAX_AUTH. Consider reducing to 3 or fewer to limit brute-force attempts."
    else
        echo -e "  \033[0;32m[OK]\033[0m MaxAuthTries is $MAX_AUTH."
    fi

    PASSWD_AUTH=$(grep -r -E "^PasswordAuthentication" "$SSH_CONFIG" "$SSH_CONFIG_D"/ 2>/dev/null | awk '{print $2}' | head -1)
    if [ -z "$PASSWD_AUTH" ] || echo "$PASSWD_AUTH" | grep -qi "^yes$"; then
        echo -e "  \033[0;33m[INFO]\033[0m PasswordAuthentication is '${PASSWD_AUTH:-yes (default)}'. Key-based auth only is more secure."
    else
        echo -e "  \033[0;32m[OK]\033[0m PasswordAuthentication is '$PASSWD_AUTH'."
    fi

else
    echo -e "Status: \033[0;33m[INFO]\033[0m SSH configuration not found."
fi


# MySQL configuration
# On Debian, mysql-server is not available; mariadb-server is installed instead.
# MariaDB runs as 'mysqld' and uses /etc/mysql/my.cnf, so checks remain compatible.

echo -e "\n[*] Auditing MySQL/MariaDB configuration:"

MYSQL_RUNNING=false
if pgrep -x "mysqld" > /dev/null || pgrep -x "mariadbd" > /dev/null; then
    MYSQL_RUNNING=true
fi

MYSQL_CONF="/etc/mysql/my.cnf"
MYSQL_DEBIAN_CONF="/etc/mysql/debian.cnf"

if [ "$MYSQL_RUNNING" = true ]; then
    echo "MySQL/MariaDB process detected."

    if [ -f "$MYSQL_CONF" ]; then
        BIND_ADDR=$(grep -E "^bind-address" "$MYSQL_CONF" | awk -F'[[:space:]]*=[[:space:]]*' '{print $2}' | tr -d ' ')
        if [ -z "$BIND_ADDR" ]; then
            echo -e "  \033[0;33m[WARNING]\033[0m bind-address not configured in $MYSQL_CONF. MySQL/MariaDB may be listening on all interfaces."
        elif [ "$BIND_ADDR" = "127.0.0.1" ] || [ "$BIND_ADDR" = "localhost" ]; then
            echo -e "  \033[0;32m[OK]\033[0m MySQL/MariaDB bind-address is '$BIND_ADDR' (localhost only)."
        else
            echo -e "  \033[0;31m[WARNING]\033[0m MySQL/MariaDB bind-address is '$BIND_ADDR'. Verify this is intentional."
        fi
    else
        echo -e "  \033[0;33m[INFO]\033[0m $MYSQL_CONF not found. Cannot verify bind-address."
    fi

    MYSQL_EXTERNAL=$(ss -tlnp 2>/dev/null | grep ":3306" | grep -v "127\.0\.0\.1\|::1")
    if [ -n "$MYSQL_EXTERNAL" ]; then
        echo -e "  \033[0;31m[WARNING]\033[0m MySQL/MariaDB port 3306 is exposed on a non-loopback interface:"
        echo "  $MYSQL_EXTERNAL"
    else
        echo -e "  \033[0;32m[OK]\033[0m MySQL/MariaDB port 3306 not detected on external interfaces."
    fi

    if [ -f "$MYSQL_DEBIAN_CONF" ]; then
        DEBIAN_CNF_PERMS=$(stat -c "%a" "$MYSQL_DEBIAN_CONF")
        echo -e "\n[*] Checking $MYSQL_DEBIAN_CONF permissions:"
        echo "$MYSQL_DEBIAN_CONF -> permissions: $DEBIAN_CNF_PERMS"
        if [ "$DEBIAN_CNF_PERMS" -gt 640 ]; then
            echo -e "   \033[0;31m[WARNING]\033[0m Permissions too permissive. File contains plaintext maintenance credentials."
        else
            echo -e "   \033[0;32m[OK]\033[0m Permissions are acceptable."
        fi
    fi
else
    echo -e "Status: \033[0;33m[INFO]\033[0m MySQL/MariaDB is not running."
fi


# Apache configuration

echo -e "\n[*] Auditing Apache web server configuration:"

APACHE_RUNNING=false
if pgrep -x "apache2" > /dev/null || pgrep -x "httpd" > /dev/null; then
    APACHE_RUNNING=true
fi

if [ "$APACHE_RUNNING" = true ]; then
    echo "Apache process detected."

    APACHE_WORKER_USER=$(ps -edf | grep -E "(apache2|httpd)" | grep -v "root\|grep" | awk '{print $1}' | sort -u | head -1)
    if [ -z "$APACHE_WORKER_USER" ]; then
        echo -e "  \033[0;33m[INFO]\033[0m Could not determine Apache worker process user."
    elif [ "$APACHE_WORKER_USER" = "root" ]; then
        echo -e "  \033[0;31m[WARNING]\033[0m Apache worker processes are running as root. Vulnerability impact is severely elevated."
    else
        echo -e "  \033[0;32m[OK]\033[0m Apache worker processes running as '$APACHE_WORKER_USER'."
    fi

    APACHE_SECURITY_CONF=""
    for CONF_PATH in /etc/apache2/conf.d/security /etc/apache2/conf-enabled/security.conf /etc/httpd/conf.d/security.conf; do
        if [ -f "$CONF_PATH" ]; then
            APACHE_SECURITY_CONF="$CONF_PATH"
            break
        fi
    done

    if [ -n "$APACHE_SECURITY_CONF" ]; then
        SERVER_TOKENS=$(grep -E "^ServerTokens" "$APACHE_SECURITY_CONF" 2>/dev/null | awk '{print $2}')
        SERVER_SIG=$(grep -E "^ServerSignature" "$APACHE_SECURITY_CONF" 2>/dev/null | awk '{print $2}')

        if [ -z "$SERVER_TOKENS" ] || [ "$SERVER_TOKENS" != "Prod" ]; then
            echo -e "  \033[0;33m[WARNING]\033[0m ServerTokens is '${SERVER_TOKENS:-not set}'. Recommended value is 'Prod'."
        else
            echo -e "  \033[0;32m[OK]\033[0m ServerTokens is 'Prod'."
        fi

        if [ -z "$SERVER_SIG" ] || echo "$SERVER_SIG" | grep -qi "^on$"; then
            echo -e "  \033[0;33m[WARNING]\033[0m ServerSignature is '${SERVER_SIG:-not set}'. Recommended value is 'Off'."
        else
            echo -e "  \033[0;32m[OK]\033[0m ServerSignature is Off."
        fi
    else
        echo -e "  \033[0;33m[INFO]\033[0m Apache security config not found. Cannot audit ServerTokens/ServerSignature."
    fi

    echo -e "\n[*] Checking for directory listing (Indexes) in Apache site configs:"
    SITES_DIR=""
    for SITES_PATH in /etc/apache2/sites-enabled /etc/httpd/conf.d; do
        if [ -d "$SITES_PATH" ]; then
            SITES_DIR="$SITES_PATH"
            break
        fi
    done

    if [ -n "$SITES_DIR" ]; then
        INDEXES_ENABLED=$(grep -r "Options.*Indexes" "$SITES_DIR" 2>/dev/null | grep -v "\-Indexes\|#")
        if [ -n "$INDEXES_ENABLED" ]; then
            echo -e "Status: \033[0;31m[WARNING]\033[0m Directory listing (Indexes) is enabled:"
            echo "$INDEXES_ENABLED"
        else
            echo -e "Status: \033[0;32m[OK]\033[0m Directory listing (Indexes) not found in enabled site configs."
        fi
    else
        echo -e "Status: \033[0;33m[INFO]\033[0m Apache sites-enabled directory not found."
    fi
else
    echo -e "Status: \033[0;33m[INFO]\033[0m Apache is not running."
fi


# PHP configuration

echo -e "\n[*] Auditing PHP configuration:"

PHP_INI=""
for PHP_INI_PATH in \
    /etc/php5/apache2/php.ini \
    /etc/php7.0/apache2/php.ini \
    /etc/php7.4/apache2/php.ini \
    /etc/php8.0/apache2/php.ini \
    /etc/php8.1/apache2/php.ini \
    /etc/php8.2/apache2/php.ini \
    /etc/php8.3/apache2/php.ini \
    /etc/php/*/apache2/php.ini \
    /etc/php/*/cli/php.ini; do
    # expand globs
    for EXPANDED in $PHP_INI_PATH; do
        if [ -f "$EXPANDED" ]; then
            PHP_INI="$EXPANDED"
            break 2
        fi
    done
done

if [ -z "$PHP_INI" ] && command -v php &>/dev/null; then
    PHP_INI=$(php -r "echo php_ini_loaded_file();" 2>/dev/null)
fi

if [ -z "$PHP_INI" ]; then
    echo -e "Status: \033[0;33m[INFO]\033[0m No PHP ini file found. PHP may not be installed."
else
    echo "PHP configuration file: $PHP_INI"

    check_php_directive() {
        local DIRECTIVE=$1
        local EXPECTED=$2
        local SEVERITY=$3
        local MESSAGE=$4
        local VALUE
        VALUE=$(grep -E "^\s*${DIRECTIVE}\s*=" "$PHP_INI" 2>/dev/null | tail -1 | awk -F= '{print $2}' | tr -d ' ')
        if [ -z "$VALUE" ]; then
            echo -e "  \033[0;33m[INFO]\033[0m ${DIRECTIVE} not explicitly set in $PHP_INI."
        elif echo "$VALUE" | grep -qi "^${EXPECTED}$"; then
            echo -e "  \033[0;32m[OK]\033[0m ${DIRECTIVE} = ${VALUE}."
        else
            echo -e "  \033[0;${SEVERITY}m[WARNING]\033[0m ${DIRECTIVE} = ${VALUE}. ${MESSAGE}"
        fi
    }

    check_php_directive "expose_php"       "Off"   "33" "PHP version is disclosed in HTTP response headers."
    check_php_directive "display_errors"   "Off"   "31" "Error details are exposed to end users in production."
    check_php_directive "log_errors"       "On"    "31" "PHP errors are not being logged."
    check_php_directive "safe_mode"        "On"    "33" "safe_mode is off. It can be bypassed but still slows down an attacker."
    check_php_directive "allow_url_include" "Off"  "31" "Remote file inclusion via URL is permitted. High risk for RFI attacks."

    ERROR_REPORTING=$(grep -E "^\s*error_reporting\s*=" "$PHP_INI" 2>/dev/null | tail -1 | awk -F= '{print $2}' | tr -d ' ')
    if [ -z "$ERROR_REPORTING" ]; then
        echo -e "  \033[0;33m[INFO]\033[0m error_reporting not explicitly set."
    else
        echo -e "  \033[0;32m[OK]\033[0m error_reporting = ${ERROR_REPORTING}."
    fi

    echo -e "\n[*] Checking PHP disabled_functions:"
    DISABLED_FUNCS=$(grep -E "^\s*disable_functions\s*=" "$PHP_INI" 2>/dev/null | tail -1 | awk -F= '{print $2}' | tr -d ' ')
    if [ -z "$DISABLED_FUNCS" ]; then
        echo -e "Status: \033[0;31m[WARNING]\033[0m disable_functions is not set. Dangerous functions (exec, system, shell_exec, passthru, proc_open, popen) are available."
    else
        echo "  Disabled functions: $DISABLED_FUNCS"
        MISSING_FUNCS=""
        for FUNC in eval exec system shell_exec passthru proc_open popen; do
            if ! echo "$DISABLED_FUNCS" | grep -qi "$FUNC"; then
                MISSING_FUNCS="$MISSING_FUNCS $FUNC"
            fi
        done
        if [ -n "$MISSING_FUNCS" ]; then
            echo -e "  \033[0;33m[WARNING]\033[0m The following dangerous functions are not disabled:$MISSING_FUNCS"
        else
            echo -e "  \033[0;32m[OK]\033[0m All commonly abused execution functions are disabled."
        fi
    fi
    echo -e "\n[*] Checking Suhosin PHP extension:"

    SUHOSIN_INI=""
    for SUHOSIN_PATH in \
        /etc/php5/apache2/conf.d/suhosin.ini \
        /etc/php/*/apache2/conf.d/*suhosin* \
        /etc/php/*/mods-available/suhosin.ini; do
        for EXPANDED in $SUHOSIN_PATH; do
            if [ -f "$EXPANDED" ]; then
                SUHOSIN_INI="$EXPANDED"
                break 2
            fi
        done
    done

    if [ -z "$SUHOSIN_INI" ]; then
        echo -e "Status: \033[0;33m[INFO]\033[0m Suhosin not detected. Consider installing it for an additional PHP security layer."
    else
        echo "Suhosin config: $SUHOSIN_INI"
        echo "Active configuration (non-commented):"
        grep -v -E "^;|^\s*$" "$SUHOSIN_INI"

        SUHOSIN_LOG=$(grep -E "^\s*suhosin\.log\.syslog\s*=" "$SUHOSIN_INI" | grep -v "^;" | awk -F= '{print $2}' | tr -d ' ')
        SUHOSIN_TRAVERSAL=$(grep -E "^\s*suhosin\.executor\.include\.max_traversal\s*=" "$SUHOSIN_INI" | grep -v "^;" | awk -F= '{print $2}' | tr -d ' ')
        SUHOSIN_DISABLE_EVAL=$(grep -E "^\s*suhosin\.executor\.disable_eval\s*=" "$SUHOSIN_INI" | grep -v "^;" | awk -F= '{print $2}' | tr -d ' ')
        SUHOSIN_EMODIFIER=$(grep -E "^\s*suhosin\.executor\.disable_emodifier\s*=" "$SUHOSIN_INI" | grep -v "^;" | awk -F= '{print $2}' | tr -d ' ')

        if [ -z "$SUHOSIN_LOG" ]; then
            echo -e "  \033[0;33m[WARNING]\033[0m suhosin.log.syslog not set. Suhosin events are not being logged to syslog."
        else
            echo -e "  \033[0;32m[OK]\033[0m suhosin.log.syslog = $SUHOSIN_LOG"
        fi

        if [ -z "$SUHOSIN_TRAVERSAL" ]; then
            echo -e "  \033[0;33m[WARNING]\033[0m suhosin.executor.include.max_traversal not set. Directory traversal via include is unrestricted."
        else
            echo -e "  \033[0;32m[OK]\033[0m suhosin.executor.include.max_traversal = $SUHOSIN_TRAVERSAL"
        fi

        if [ -z "$SUHOSIN_DISABLE_EVAL" ] || echo "$SUHOSIN_DISABLE_EVAL" | grep -qi "^0$"; then
            echo -e "  \033[0;33m[WARNING]\033[0m suhosin.executor.disable_eval not enabled. eval() can still be used for code execution."
        else
            echo -e "  \033[0;32m[OK]\033[0m suhosin.executor.disable_eval = $SUHOSIN_DISABLE_EVAL"
        fi

        if [ -z "$SUHOSIN_EMODIFIER" ] || echo "$SUHOSIN_EMODIFIER" | grep -qi "^0$"; then
            echo -e "  \033[0;33m[WARNING]\033[0m suhosin.executor.disable_emodifier not enabled. preg_replace /e modifier can be used for code execution."
        else
            echo -e "  \033[0;32m[OK]\033[0m suhosin.executor.disable_emodifier = $SUHOSIN_EMODIFIER"
        fi
    fi

fi

# Nginx configuration

echo -e "\n[*] Auditing Nginx web server configuration:"

if pgrep -x "nginx" > /dev/null; then
    echo "Nginx process detected."

    NGINX_WORKER_USER=$(ps -edf | grep nginx | grep -v "root\|grep\|master" | awk '{print $1}' | sort -u | head -1)
    if [ -z "$NGINX_WORKER_USER" ]; then
        echo -e "  \033[0;33m[INFO]\033[0m Could not determine Nginx worker process user."
    elif [ "$NGINX_WORKER_USER" = "root" ]; then
        echo -e "  \033[0;31m[WARNING]\033[0m Nginx worker processes are running as root."
    else
        echo -e "  \033[0;32m[OK]\033[0m Nginx worker processes running as '$NGINX_WORKER_USER'."
    fi

    NGINX_TOKENS_ON=$(grep -r "server_tokens" /etc/nginx/ 2>/dev/null | grep -v "#" | grep "\bon\b")
    if [ -n "$NGINX_TOKENS_ON" ]; then
        echo -e "  \033[0;33m[WARNING]\033[0m server_tokens is 'on' in Nginx config. Set it to 'off' to suppress version disclosure."
    else
        echo -e "  \033[0;32m[OK]\033[0m server_tokens is not explicitly set to 'on'."
    fi
else
    echo -e "Status: \033[0;33m[INFO]\033[0m Nginx is not running."
fi


# Crontab review

echo -e "\n[*] Auditing crontab entries:"

echo "System crontab (/etc/crontab):"
if [ -f /etc/crontab ]; then
    grep -v "^#" /etc/crontab | grep -v "^\s*$"
else
    echo -e "  \033[0;33m[INFO]\033[0m /etc/crontab not found."
fi

echo -e "\n[*] Cron job directories:"
for CRON_DIR in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
    if [ -d "$CRON_DIR" ]; then
        CRON_FILES=$(ls "$CRON_DIR" 2>/dev/null)
        if [ -n "$CRON_FILES" ]; then
            echo "  $CRON_DIR:"
            echo "$CRON_FILES" | sed 's/^/    /'
        fi
    fi
done


echo -e "\n[*] Checking user crontabs:"
CRON_SPOOL="/var/spool/cron/crontabs"
if [ -d "$CRON_SPOOL" ] && [ -n "$(ls "$CRON_SPOOL" 2>/dev/null)" ]; then
    for CRON_FILE in "$CRON_SPOOL"/*; do
        [ -f "$CRON_FILE" ] || continue
        CRON_USER=$(basename "$CRON_FILE")
        echo "  Crontab for '$CRON_USER':"
        grep -v "^#" "$CRON_FILE" | grep -v "^\s*$" | sed 's/^/    /'
    done
else
    echo -e "  \033[0;33m[INFO]\033[0m No user crontabs found in $CRON_SPOOL."
fi


# Permissions of scripts invoked by cron

echo -e "\n[*] Checking write permissions on scripts referenced in cron jobs:"

CRON_SCRIPT_PATHS=$(grep -r -h -E "^[^#]" \
    /etc/crontab /etc/cron.d/ /var/spool/cron/crontabs/ 2>/dev/null \
    | grep -oE '(/[^ *?]+\.(sh|py|pl|rb))' \
    | sort -u)

if [ -z "$CRON_SCRIPT_PATHS" ]; then
    echo -e "Status: \033[0;33m[INFO]\033[0m No script paths with common extensions detected in cron entries."
else
    WRITABLE_CRON_COUNT=0
    for CRON_SCRIPT in $CRON_SCRIPT_PATHS; do
        if [ -f "$CRON_SCRIPT" ]; then
            CRON_SCRIPT_PERMS=$(stat -c "%a" "$CRON_SCRIPT")
            CRON_SCRIPT_OWNER=$(stat -c "%U" "$CRON_SCRIPT")
            echo "  $CRON_SCRIPT -> owner: $CRON_SCRIPT_OWNER, permissions: $CRON_SCRIPT_PERMS"
            if find "$CRON_SCRIPT" -perm -002 2>/dev/null | grep -q .; then
                echo -e "    \033[0;31m[WARNING]\033[0m Script is world-writable. Any local user can modify it to escalate privileges."
                WRITABLE_CRON_COUNT=$((WRITABLE_CRON_COUNT + 1))
            elif find "$CRON_SCRIPT" -perm -020 2>/dev/null | grep -q .; then
                echo -e "    \033[0;33m[WARNING]\033[0m Script is group-writable. Verify group membership is appropriately restricted."
            else
                echo -e "    \033[0;32m[OK]\033[0m Script permissions are acceptable."
            fi
        fi
    done
    if [ "$WRITABLE_CRON_COUNT" -eq 0 ]; then
        echo -e "Status: \033[0;32m[OK]\033[0m No world-writable cron scripts found."
    fi
fi

echo -e "\n--- END OF SERVICES REVIEW ---"