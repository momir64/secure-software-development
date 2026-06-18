#!/bin/bash

set -e

# ── Output helpers ────────────────────────────────────────────────────────────
step() { echo -e "\n▶  $1"; }
ok()   { echo -e "   \e[32m✓\e[0m  $1"; }
warn() { echo -e "   \e[33m⚠\e[0m  $1"; }
fail() { echo -e "   \e[31m✗\e[0m  $1"; exit 1; }
info() { echo "   $1"; }

# ── Resolve oblak path ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBLAK_PATH="$(dirname "$SCRIPT_DIR")"

if [ ! -d "$OBLAK_PATH/firecracker" ]; then
    fail "Could not find oblak/firecracker. Run this script from the oblak/ directory."
fi

echo "Oblak: $OBLAK_PATH"

# Must run as root
if [ "$EUID" -ne 0 ]; then
    fail "Please run as root: sudo bash firecracker/setup.sh"
fi

# Current (non-root) user who invoked sudo
REAL_USER="${SUDO_USER:-$USER}"

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

# ── Step 0: Virtualization / KVM ──────────────────────────────────────────────
step "Step 0: Virtualization"

if [ ! -e /dev/kvm ]; then
    # Try to load the right module
    if grep -q GenuineIntel /proc/cpuinfo 2>/dev/null; then
        modprobe kvm_intel || true
    else
        modprobe kvm_amd || true
    fi
fi

if [ ! -e /dev/kvm ]; then
    fail "/dev/kvm not found. Check that your CPU supports virtualization and it is enabled in BIOS/UEFI."
fi
ok "/dev/kvm present"

# ── Step 1: KVM access and vhost-vsock ───────────────────────────────────────
step "Step 1: KVM access and vhost-vsock"

modprobe vhost_vsock 2>/dev/null || warn "Could not load vhost_vsock module (may already be built-in)"

chown root:kvm /dev/kvm && chmod 660 /dev/kvm
ok "/dev/kvm permissions set"

if id "$REAL_USER" &>/dev/null && ! groups "$REAL_USER" | grep -q kvm; then
    info "Adding $REAL_USER to kvm group..."
    groupadd -f kvm
    usermod -aG kvm "$REAL_USER"
    ok "$REAL_USER added to kvm group (re-login required for group to take effect)"
else
    ok "$REAL_USER is in kvm group"
fi

if [ -e /dev/vhost-vsock ]; then
    chown root:kvm /dev/vhost-vsock && chmod 660 /dev/vhost-vsock
    ok "/dev/vhost-vsock present and permissions set"
else
    warn "/dev/vhost-vsock not found (vsock not available — may not be needed)"
fi

# ── Step 2: Firecracker and Jailer ───────────────────────────────────────────
step "Step 2: Firecracker and Jailer"

if command -v firecracker &>/dev/null && command -v jailer &>/dev/null; then
    fc_ver=$(firecracker --version 2>/dev/null | head -1)
    ok "Already installed: $fc_ver"
else
    info "Downloading latest Firecracker release..."
    ARCH="$(uname -m)"
    RELEASES_URL="https://github.com/firecracker-microvm/firecracker/releases"
    LATEST=$(basename "$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${RELEASES_URL}/latest")")
    BASE_URL="${RELEASES_URL}/download/${LATEST}/firecracker-${LATEST}-${ARCH}"
    FILENAME="firecracker-${LATEST}-${ARCH}.tgz"

    curl -fsSL -o "/tmp/${FILENAME}" "${BASE_URL}.tgz"
    curl -fsSL -o "/tmp/${FILENAME}.sha256.txt" "${BASE_URL}.tgz.sha256.txt"
    (cd /tmp && sha256sum -c "${FILENAME}.sha256.txt")
    tar -xzf "/tmp/${FILENAME}" -C /tmp/

    for binary in firecracker jailer; do
        mv "/tmp/release-${LATEST}-${ARCH}/${binary}-${LATEST}-${ARCH}" /usr/local/bin/"${binary}"
        chmod +x /usr/local/bin/"${binary}"
    done

    rm -rf "/tmp/${FILENAME}" "/tmp/${FILENAME}.sha256.txt" "/tmp/release-${LATEST}-${ARCH}"

    fc_ver=$(firecracker --version 2>/dev/null | head -1)
    jailer_ver=$(jailer --version 2>/dev/null | head -1)
    ok "Installed: $fc_ver"
    ok "Installed: $jailer_ver"
fi

# ── Step 3: Guest kernel ──────────────────────────────────────────────────────
step "Step 3: Guest kernel"

if [ -f "$OBLAK_PATH/resources/vmlinux" ]; then
    ok "Already present: resources/vmlinux"
else
    info "Downloading latest Firecracker CI kernel..."
    ARCH="$(uname -m)"
    S3_CI_BASE="http://spec.ccfc.min.s3.amazonaws.com/?prefix=firecracker-ci/"
    S3_BASE="https://s3.amazonaws.com/spec.ccfc.min"
    CI_VERSION=$(curl -s "${S3_CI_BASE}&list-type=2&delimiter=/" \
        | grep -oP "(?<=firecracker-ci/)v[0-9]+\.[0-9]+(?=/)" \
        | sort -V | tail -1)
    KERNEL_KEY=$(curl -s "${S3_CI_BASE}${CI_VERSION}/${ARCH}/vmlinux-&list-type=2" \
        | grep -oP "(?<=<Key>)(firecracker-ci/${CI_VERSION}/${ARCH}/vmlinux-[0-9]+\.[0-9]+\.[0-9]{1,3})(?=</Key>)" \
        | sort -V | tail -1)
    mkdir -p "$OBLAK_PATH/resources"
    curl -fsSL -o "$OBLAK_PATH/resources/vmlinux" "${S3_BASE}/${KERNEL_KEY}"
    ok "Kernel downloaded"
fi

# ── Step 4: Root filesystem ───────────────────────────────────────────────────
step "Step 4: Root filesystem"

if [ -f "$OBLAK_PATH/resources/rootfs.ext4" ]; then
    ok "Already present: resources/rootfs.ext4"
else
    if ! command -v docker &>/dev/null; then
        fail "Docker not found. Install it: https://docs.docker.com/engine/install/"
    fi
    if ! command -v mkfs.ext4 &>/dev/null; then
        info "Installing e2fsprogs..."
        apt-get install -y e2fsprogs 2>/dev/null | tail -1
    fi

    DISK_SIZE=$(get_vm_config "disk_size_mib" "512")
    info "Building rootfs (${DISK_SIZE}MiB)..."

    cd "$OBLAK_PATH"
    docker build -t oblak-base firecracker/rootfs/
    docker rm -f oblak-base-tmp 2>/dev/null || true
    docker create --name oblak-base-tmp oblak-base
    mkdir -p /tmp/oblak-rootfs
    docker export oblak-base-tmp | tar -x -C /tmp/oblak-rootfs/
    docker rm oblak-base-tmp
    truncate -s "${DISK_SIZE}M" resources/rootfs.ext4
    mkfs.ext4 -d /tmp/oblak-rootfs -F resources/rootfs.ext4
    rm -rf /tmp/oblak-rootfs
    ok "Root filesystem created: resources/rootfs.ext4 (${DISK_SIZE}MiB)"
fi

# ── Step 5: Jailer user and directory ─────────────────────────────────────────
step "Step 5: Jailer"

if id firecracker-jailer &>/dev/null; then
    ok "User firecracker-jailer already exists"
else
    groupadd -f firecracker-jailer
    useradd -r -s /sbin/nologin -g firecracker-jailer firecracker-jailer
    ok "Created user firecracker-jailer"
fi

if [ -d /srv/jailer ]; then
    ok "/srv/jailer already exists"
else
    mkdir -p /srv/jailer
    chown firecracker-jailer:firecracker-jailer /srv/jailer
    ok "Created /srv/jailer"
fi

# ── Step 6: TAP networking ────────────────────────────────────────────────────
step "Step 6: TAP networking"

if ip tuntap add dev tap-test mode tap 2>/dev/null && ip tuntap del dev tap-test mode tap 2>/dev/null; then
    ok "TAP device creation works"
else
    fail "TAP device creation failed"
fi

if iptables -t nat -L &>/dev/null; then
    ok "iptables NAT available"
else
    fail "iptables NAT not available"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo -e "\n\e[32m✓  Setup complete.\e[0m"
info "Run: sudo bash firecracker/snapshot.sh   — to build the base snapshot"
info "Run: sudo bash firecracker/test.sh       — to verify the MicroVM boots"
info ""
warn "Log out and back in (or run 'newgrp kvm') for the kvm group to take effect."