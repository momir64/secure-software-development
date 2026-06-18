#!/bin/bash

set -e

# ── Output helpers ────────────────────────────────────────────────────────────
step() { echo -e "\n▶  $1"; }
ok()   { echo -e "   \e[32m✓\e[0m  $1"; }
fail() { echo -e "   \e[31m✗\e[0m  $1"; exit 1; }
info() { echo "   $1"; }

# ── Resolve oblak path ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBLAK_PATH="$(dirname "$SCRIPT_DIR")"

if [ ! -d "$OBLAK_PATH/firecracker" ]; then
    fail "Could not find oblak/firecracker. Run this script from the oblak/ directory."
fi
if [ ! -f "$OBLAK_PATH/resources/vmlinux" ]; then
    fail "resources/vmlinux not found — run setup.sh first"
fi

echo "Oblak: $OBLAK_PATH"

if [ "$EUID" -ne 0 ]; then
    fail "Please run as root: sudo bash firecracker/snapshot.sh"
fi

# ── Read config/vm.toml ───────────────────────────────────────────────────────
get_vm_config() {
    local key="$1"
    local default="$2"
    local toml="$OBLAK_PATH/config/vm.toml"
    if [ -f "$toml" ]; then
        local val
        val=$(grep -E "^\s*${key}\s*=" "$toml" | head -1 | cut -d= -f2 | tr -d ' ')
        echo "${val:-$default}"
    else
        echo "$default"
    fi
}

VCPU=$(get_vm_config "vcpu_count" "1")
MEM=$(get_vm_config "memory_mib" "128")
DISK_SIZE=$(get_vm_config "disk_size_mib" "512")

# ── Rebuild rootfs ────────────────────────────────────────────────────────────
step "Rebuilding base rootfs"

if ! command -v docker &>/dev/null; then
    fail "Docker not found. Install it: https://docs.docker.com/engine/install/"
fi
if ! command -v mkfs.ext4 &>/dev/null; then
    apt-get install -y e2fsprogs 2>/dev/null | tail -1
fi

cd "$OBLAK_PATH"
docker build -t oblak-base firecracker/rootfs/
docker rm -f oblak-base-tmp 2>/dev/null || true
docker create --name oblak-base-tmp oblak-base
mkdir -p /tmp/oblak-rootfs
docker export oblak-base-tmp | tar -x -C /tmp/oblak-rootfs/
docker rm oblak-base-tmp
echo "nameserver 8.8.8.8" > /tmp/oblak-rootfs/etc/resolv.conf
truncate -s "${DISK_SIZE}M" resources/rootfs.ext4
mkfs.ext4 -d /tmp/oblak-rootfs -F resources/rootfs.ext4
rm -rf /tmp/oblak-rootfs

ok "resources/rootfs.ext4 rebuilt"

# ── Take snapshot ─────────────────────────────────────────────────────────────
step "Taking base snapshot ($VCPU vCPU, ${MEM}MiB RAM)"
info "Boots a Firecracker VM and waits for the runner on vsock port 8080."

ABS_OBLAK="$OBLAK_PATH"
SNAP_OUT="$ABS_OBLAK/resources/snapshot"
SNAP_WORK=$(mktemp -d)

SNAP_TAP="tap0"
STUB="/resources/stub.ext4"
VSOCK_SOCK="/tmp/v.sock"

FC_PID=""
cleanup() {
    [ -n "$FC_PID" ] && kill "$FC_PID" 2>/dev/null || true
    ip link del "$SNAP_TAP" 2>/dev/null || true
    rm -f "$VSOCK_SOCK"
    rm -f /resources
    rm -rf "$SNAP_WORK"
}
trap cleanup EXIT

FC_SOCK="$SNAP_WORK/fc.sock"
FC_LOG="$SNAP_WORK/fc.log"

VMLINUX="/resources/vmlinux"
ROOTFS="/resources/rootfs.ext4"

mkdir -p "$SNAP_OUT"

if [ ! -f "$ABS_OBLAK/resources/stub.ext4" ]; then
    truncate -s 1M "$ABS_OBLAK/resources/stub.ext4"
    mkfs.ext4 -F "$ABS_OBLAK/resources/stub.ext4"
fi

ln -sfn "$ABS_OBLAK/resources" /resources

# ── TAP device ────────────────────────────────────────────────────────────────
info "Setting up TAP device..."
ip tuntap add dev "$SNAP_TAP" mode tap
ip link set "$SNAP_TAP" up

# ── Start Firecracker ─────────────────────────────────────────────────────────
info "Starting Firecracker..."
firecracker --api-sock "$FC_SOCK" > "$FC_LOG" 2>&1 &
FC_PID=$!

# Wait up to 15 s for the API socket to appear
for i in $(seq 30); do
    [ -S "$FC_SOCK" ] && break
    sleep 0.5
done
[ -S "$FC_SOCK" ] || { echo "Firecracker API socket did not appear — see $FC_LOG"; cat "$FC_LOG"; exit 1; }

# ── Firecracker REST helper ───────────────────────────────────────────────────
api() {
    local method="$1" path="$2" body="${3:-}"
    local code resp
    if [ -n "$body" ]; then
        resp=$(curl -s -w "\n%{http_code}" -X "$method" --unix-socket "$FC_SOCK" \
            -H "Accept: application/json" -H "Content-Type: application/json" \
            "http://localhost$path" -d "$body")
    else
        resp=$(curl -s -w "\n%{http_code}" -X "$method" --unix-socket "$FC_SOCK" \
            -H "Accept: application/json" -H "Content-Type: application/json" \
            "http://localhost$path")
    fi
    code=$(echo "$resp" | tail -1)
    if [ "$code" -ge 300 ]; then
        echo "Firecracker API error: $method $path -> HTTP $code: $(echo "$resp" | head -n -1)" >&2
        exit 1
    fi
}

# ── Configure VM ──────────────────────────────────────────────────────────────
api PUT /machine-config \
    "{\"vcpu_count\": $VCPU, \"mem_size_mib\": $MEM}"

api PUT /boot-source \
    "{\"kernel_image_path\": \"$VMLINUX\", \"boot_args\": \"console=ttyS0 reboot=k panic=1 pci=off init=/var/runtime/runner.py\"}"

api PUT /drives/rootfs \
    "{\"drive_id\": \"rootfs\", \"path_on_host\": \"$ROOTFS\", \"is_root_device\": true, \"is_read_only\": true}"

api PUT /drives/env \
    "{\"drive_id\": \"env\", \"path_on_host\": \"$STUB\", \"is_root_device\": false, \"is_read_only\": true}"

api PUT /drives/task \
    "{\"drive_id\": \"task\", \"path_on_host\": \"$STUB\", \"is_root_device\": false, \"is_read_only\": true}"

api PUT /vsock \
    "{\"vsock_id\": \"vsock0\", \"guest_cid\": 3, \"uds_path\": \"$VSOCK_SOCK\"}"

api PUT /network-interfaces/eth0 \
    "{\"iface_id\": \"eth0\", \"host_dev_name\": \"$SNAP_TAP\", \"guest_mac\": \"AA:FC:00:00:00:01\"}"

# ── Boot ──────────────────────────────────────────────────────────────────────
api PUT /actions '{"action_type": "InstanceStart"}'
info "VM booting — polling vsock port 8080 for runner readiness..."

READY=0
for i in $(seq 40); do
    if ERR=$(python3 -c "
import socket, sys
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(2)
    s.connect('$VSOCK_SOCK')
    s.sendall(b'CONNECT 8080\n')
    line = b''
    while not line.endswith(b'\n'):
        chunk = s.recv(1)
        if not chunk:
            print('connection closed')
            sys.exit(1)
        line += chunk
    sys.exit(0 if line.startswith(b'OK') else 1)
except Exception as e:
    print(type(e).__name__ + ': ' + str(e))
    sys.exit(1)
" 2>/dev/null); then
        READY=1
        break
    fi
    info "attempt $i: $ERR"
    sleep 0.5
done

[ "$READY" -eq 1 ] || {
    echo "Runner did not become ready within 20 s"
    echo "Firecracker log:"
    cat "$FC_LOG"
    exit 1
}

# Probe consumed one accept(). Give runner time to return to accept().
info "Runner ready. Waiting 5 s for it to return to accept()..."
sleep 5

# ── Snapshot ──────────────────────────────────────────────────────────────────
info "Pausing VM..."
api PATCH /vm '{"state": "Paused"}'

info "Creating full snapshot..."
api PUT /snapshot/create \
    "{\"snapshot_type\":\"Full\",\"snapshot_path\":\"${SNAP_OUT}/vmstate\",\"mem_file_path\":\"${SNAP_OUT}/mem.snap\"}"

# Give Firecracker a moment to flush snapshot data to disk
sleep 1

[ -f "$SNAP_OUT/vmstate" ] || { echo "vmstate not found after snapshot"; exit 1; }
[ -f "$SNAP_OUT/mem.snap" ] || { echo "mem.snap not found after snapshot"; exit 1; }

# ── Done ──────────────────────────────────────────────────────────────────────
ok "resources/snapshot/vmstate"
ok "resources/snapshot/mem.snap"
echo -e "\n\e[32m✓  Base snapshot complete.\e[0m"