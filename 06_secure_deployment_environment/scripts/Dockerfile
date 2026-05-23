FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
    net-tools \
    iproute2 \
    iptables \
    iputils-ping \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY main_audit.sh .
COPY system_review.sh .
COPY network_review.sh .
COPY filesystem_review.sh .
COPY users_review.sh .

RUN sed -i 's/\r$//' *.sh && chmod +x *.sh

ENTRYPOINT ["./main_audit.sh"]