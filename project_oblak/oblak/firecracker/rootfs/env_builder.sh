#!/bin/sh
export PATH=/usr/local/bin:/usr/bin:/bin:/sbin
mount -t tmpfs tmpfs /tmp
mount -t ext4 -o ro /dev/vdb /var/task
mount -t ext4 /dev/vdc /env
mount -t tmpfs tmpfs /etc
echo "nameserver 8.8.8.8" > /etc/resolv.conf
for arg in $(cat /proc/cmdline); do
    case "$arg" in
        env_ip=*) ENV_IP="${arg#env_ip=}" ;;
        env_gw=*) ENV_GW="${arg#env_gw=}" ;;
    esac
done
ip addr add "$ENV_IP" dev eth0
ip link set eth0 up
ip route add default via "$ENV_GW"
UV_CACHE_DIR=/env/.cache uv pip install --no-cache --system --target /env -r /var/task/requirements.txt && touch /env/.__build_ok__
rm -rf /env/.cache
umount /env
reboot -f