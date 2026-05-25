FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
    net-tools \
    iproute2 \
    iptables \
    iputils-ping \
    dnsutils \
    lsof \
    openssh-server \
    apache2 \
    php \
    libapache2-mod-php \
    mariadb-server \
    && rm -rf /var/lib/apt/lists/*

# --- SSH: weak configuration ---
RUN echo "PermitRootLogin yes" >> /etc/ssh/sshd_config \
    && echo "MaxAuthTries 6" >> /etc/ssh/sshd_config \
    && echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config \
    && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config

# --- Apache: weak configuration ---
RUN echo "ServerTokens Full" > /etc/apache2/conf-enabled/security.conf \
    && echo "ServerSignature On" >> /etc/apache2/conf-enabled/security.conf
RUN sed -i 's/Options Indexes FollowSymLinks/Options Indexes FollowSymLinks/' \
    /etc/apache2/sites-enabled/000-default.conf 2>/dev/null || true

# --- PHP: weak configuration ---
RUN PHP_INI=$(php -r "echo php_ini_loaded_file();" 2>/dev/null || find /etc/php -name "php.ini" | head -1) \
    && echo "expose_php = On" >> "$PHP_INI" \
    && echo "display_errors = On" >> "$PHP_INI" \
    && echo "log_errors = Off" >> "$PHP_INI" \
    && echo "allow_url_include = On" >> "$PHP_INI" \
    && echo "safe_mode = Off" >> "$PHP_INI" \
    && echo "disable_functions =" >> "$PHP_INI"

# --- MariaDB: weak configuration (listen on all interfaces) ---
RUN sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf

# --- Crontab: weak configuration ---
RUN echo "#!/bin/bash" > /opt/backup.sh \
    && echo "tar -czf /tmp/backup.tar.gz /etc" >> /opt/backup.sh \
    && chmod 777 /opt/backup.sh \
    && echo "0 2 * * * root /opt/backup.sh" > /etc/cron.d/backup

WORKDIR /app

COPY main_audit.sh .
COPY system_review.sh .
COPY network_review.sh .
COPY filesystem_review.sh .
COPY users_review.sh .
COPY services_review.sh .

RUN sed -i 's/\r$//' *.sh && chmod +x *.sh

ENTRYPOINT ["./main_audit.sh"]