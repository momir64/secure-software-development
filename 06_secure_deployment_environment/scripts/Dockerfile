FROM debian/eol:squeeze-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN echo "deb http://archive.debian.org/debian/ squeeze main contrib non-free" > /etc/apt/sources.list && \
    echo "deb-src http://archive.debian.org/debian/ squeeze main contrib non-free" >> /etc/apt/sources.list && \
    echo "Acquire::Check-Valid-Until false;" > /etc/apt/apt.conf.d/99no-check-valid-until

RUN apt-get update && apt-get install -y --force-yes \
    procps \
    net-tools \
    iproute \
    iptables \
    iputils-ping \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY main_audit.sh .
COPY system_review.sh .
COPY network_review.sh .

RUN chmod +x *.sh

ENTRYPOINT ["./main_audit.sh"]