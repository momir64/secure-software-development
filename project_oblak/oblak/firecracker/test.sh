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
    fail "Could not find oblak/firecracker. Run from the oblak/ directory."
fi
if [ ! -f "$OBLAK_PATH/resources/vmlinux" ]; then
    fail "resources/vmlinux not found — run setup.sh first"
fi
if [ ! -f "$OBLAK_PATH/resources/rootfs.ext4" ]; then
    fail "resources/rootfs.ext4 not found — run setup.sh first"
fi

echo "Oblak: $OBLAK_PATH"

if [ "$EUID" -ne 0 ]; then
    fail "Please run as root: sudo bash firecracker/test.sh"
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
VM_ID="test-vm"
CHROOT="/srv/jailer/firecracker/$VM_ID/root"

# ── Prepare chroot ────────────────────────────────────────────────────────────
step "Preparing test VM ($VCPU vCPU, ${MEM}MiB RAM)"

rm -rf "/srv/jailer/firecracker/$VM_ID"
mkdir -p "$CHROOT/resources"
cp "$OBLAK_PATH/resources/vmlinux"    "$CHROOT/resources/vmlinux"
cp "$OBLAK_PATH/resources/rootfs.ext4" "$CHROOT/resources/rootfs.ext4"
chown -R firecracker-jailer:firecracker-jailer "$CHROOT"
ok "Resources copied to chroot"

cat > "$CHROOT/vm-config.json" <<EOF
{
    "boot-source": {
        "kernel_image_path": "resources/vmlinux",
        "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/bin/sh"
    },
    "drives": [
        {
            "drive_id": "rootfs",
            "path_on_host": "resources/rootfs.ext4",
            "is_root_device": true,
            "is_read_only": false
        }
    ],
    "machine-config": {
        "vcpu_count": $VCPU,
        "mem_size_mib": $MEM
    }
}
EOF
ok "Config written"

# ── Boot ──────────────────────────────────────────────────────────────────────
step "Booting MicroVM"
echo -e "   \e[33mType 'reboot' or 'exit' inside the VM to shut it down (press Enter to boot)\e[0m"
read -r

FC_UID=$(id -u firecracker-jailer)
FC_GID=$(id -g firecracker-jailer)

jailer \
    --id "$VM_ID" \
    --exec-file /usr/local/bin/firecracker \
    --uid "$FC_UID" \
    --gid "$FC_GID" \
    --chroot-base-dir /srv/jailer \
    -- --config-file vm-config.json

# ── Cleanup ───────────────────────────────────────────────────────────────────
rm -rf "/srv/jailer/firecracker/$VM_ID"

echo -e "\n\e[32m✓  MicroVM shut down cleanly.\e[0m"