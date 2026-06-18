# firecracker/snapshot.ps1
# Rebuilds rootfs.ext4, boots a Firecracker VM, waits for the runner to signal
# readiness on vsock port 8080, takes a full memory snapshot, and stores it
# in resources/snapshot/.
#
# Run from the oblak/ directory:
#   .\firecracker\snapshot.ps1

param([string]$OblakPath = "")

$ErrorActionPreference = "Stop"

# ── Output helpers ────────────────────────────────────────────────────────────
function Write-Step { param($msg) Write-Host "`n▶  $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "   " -NoNewline; Write-Host "✓" -ForegroundColor Green  -NoNewline; Write-Host "  $msg" }
function Write-Fail { param($msg) Write-Host "   " -NoNewline; Write-Host "✗" -ForegroundColor Red    -NoNewline; Write-Host "  $msg"; exit 1 }
function Write-Info { param($msg) Write-Host "   $msg" }

# ── Resolve oblak path ────────────────────────────────────────────────────────
if ($OblakPath -eq "") { $OblakPath = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path "$OblakPath\firecracker")) {
    Write-Fail "Could not find oblak/firecracker. Pass path explicitly: .\firecracker\snapshot.ps1 -OblakPath C:\path\to\oblak"
}
if (-not (Test-Path "$OblakPath\resources\vmlinux")) { Write-Fail "resources/vmlinux not found  -  run setup.ps1 first" }

$WslOblakPath = (wsl wslpath -u ($OblakPath -replace '\\', '/')).Trim()
Write-Host "Oblak: $OblakPath" -ForegroundColor DarkGray

# ── Helpers ───────────────────────────────────────────────────────────────────
function Invoke-WslScript {
    param([string]$Script, [string]$WorkDir = "", [switch]$AsRoot)
    $header  = "#!/bin/bash`n"
    $cd      = if ($WorkDir -ne "") { "cd '$WorkDir'`n" } else { "" }
    $content = ($header + $cd + $Script) -replace "`r`n", "`n" -replace "`r", "`n"
    $tmp     = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + ".sh")
    [System.IO.File]::WriteAllText($tmp, $content, (New-Object System.Text.UTF8Encoding $false))
    $wslTmp  = (wsl wslpath -u ($tmp -replace '\\', '/')).Trim()
    if ($AsRoot) { wsl -u root bash "$wslTmp" } else { wsl bash "$wslTmp" }
    $code = $LASTEXITCODE
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ($code -ne 0) { Write-Fail "Snapshot script failed (exit $code)" }
}

function Get-VmConfig {
    param([string]$Key, [string]$Default)
    $toml = "$OblakPath\config\vm.toml"
    if (Test-Path $toml) {
        $line = Get-Content $toml | Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1
        if ($line) { return (($line -split '=')[1]).Trim() }
    }
    return $Default
}

# ── Read config ───────────────────────────────────────────────────────────────
$vcpu     = Get-VmConfig "vcpu_count" "1"
$mem      = Get-VmConfig "memory_mib" "128"
$diskSize = Get-VmConfig "disk_size_mib" "512"

# ── Rebuild rootfs ────────────────────────────────────────────────────────────
Write-Step "Rebuilding base rootfs"
$null = wsl -u root bash -c "docker version" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "docker not found in WSL2. Enable WSL integration in Docker Desktop: Settings -> Resources -> WSL Integration -> Ubuntu -> Apply"
}
Invoke-WslScript ("DISK_SIZE=$diskSize`n" + @'
set -e
docker build -t oblak-base firecracker/rootfs/
docker rm -f oblak-base-tmp 2>/dev/null || true
docker create --name oblak-base-tmp oblak-base
mkdir -p /tmp/oblak-rootfs
docker export oblak-base-tmp | tar -x -C /tmp/oblak-rootfs/
docker rm oblak-base-tmp
echo "nameserver 8.8.8.8" > /tmp/oblak-rootfs/etc/resolv.conf
truncate -s ${DISK_SIZE}M resources/rootfs.ext4
mkfs.ext4 -d /tmp/oblak-rootfs -F resources/rootfs.ext4
rm -rf /tmp/oblak-rootfs
'@) -WorkDir $WslOblakPath -AsRoot
Write-Ok "resources/rootfs.ext4 rebuilt"

# ── Take snapshot ─────────────────────────────────────────────────────────────
Write-Step "Taking base snapshot ($vcpu vCPU, ${mem}MiB RAM)"
Write-Info "Boots a Firecracker VM and waits for the runner on vsock port 8080."

# The bash body is a literal single-quoted here-string so PowerShell does not
# expand shell variables like $FC_PID.  The VCPU / MEM lines are prepended
# as a double-quoted string so their values come from vm.toml.
Invoke-WslScript ("VCPU=$vcpu`nMEM=$mem`n" + @'
set -e

ABS_OBLAK=$(pwd)
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
echo "   Setting up TAP device..."
ip tuntap add dev "$SNAP_TAP" mode tap
ip link set "$SNAP_TAP" up

# ── Start Firecracker ─────────────────────────────────────────────────────────
echo "   Starting Firecracker..."
firecracker --api-sock "$FC_SOCK" > "$FC_LOG" 2>&1 &
FC_PID=$!

# Wait up to 15 s for the API socket to appear
for i in $(seq 30); do
    [ -S "$FC_SOCK" ] && break
    sleep 0.5
done
[ -S "$FC_SOCK" ] || { echo "Firecracker API socket did not appear  -  see $FC_LOG"; exit 1; }

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
    '{"vcpu_count": '"$VCPU"', "mem_size_mib": '"$MEM"'}'

api PUT /boot-source \
    '{"kernel_image_path": "'"$VMLINUX"'", "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/var/runtime/runner.py"}'

api PUT /drives/rootfs \
    '{"drive_id": "rootfs", "path_on_host": "'"$ROOTFS"'", "is_root_device": true, "is_read_only": true}'

api PUT /drives/env \
    '{"drive_id": "env", "path_on_host": "'"$STUB"'", "is_root_device": false, "is_read_only": true}'

api PUT /drives/task \
    '{"drive_id": "task", "path_on_host": "'"$STUB"'", "is_root_device": false, "is_read_only": true}'

api PUT /vsock \
    '{"vsock_id": "vsock0", "guest_cid": 3, "uds_path": "'"$VSOCK_SOCK"'"}'

api PUT /network-interfaces/eth0 \
    '{"iface_id": "eth0", "host_dev_name": "'"$SNAP_TAP"'", "guest_mac": "AA:FC:00:00:00:01"}'

# ── Boot ──────────────────────────────────────────────────────────────────────
api PUT /actions '{"action_type": "InstanceStart"}'
echo "   VM booting  -  polling vsock port 8080 for runner readiness..."

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
    echo "   attempt $i: $ERR"
    sleep 0.5
done

[ "$READY" -eq 1 ] || {
    echo "Runner did not become ready within 20 s"
    echo "Firecracker log:"
    cat "$FC_LOG"
    exit 1
}

# Probe consumed one accept(). Give runner time to return to accept().
echo "   Runner ready. Waiting 5 s for it to return to accept()..."
sleep 5

# ── Snapshot ──────────────────────────────────────────────────────────────────
echo "   Pausing VM..."
api PATCH /vm '{"state": "Paused"}'

echo "   Creating full snapshot..."
api PUT /snapshot/create \
    '{"snapshot_type":"Full","snapshot_path":"'"$SNAP_OUT/vmstate"'","mem_file_path":"'"$SNAP_OUT/mem.snap"'"}'

# Give Firecracker a moment to flush snapshot data to disk
sleep 1

[ -f "$SNAP_OUT/vmstate" ] || { echo "vmstate not found after snapshot"; exit 1; }
[ -f "$SNAP_OUT/mem.snap" ] || { echo "mem.snap not found after snapshot"; exit 1; }

echo "   Snapshot files written to resources/snapshot/"
'@) -WorkDir $WslOblakPath -AsRoot

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Ok "resources/snapshot/vmstate"
Write-Ok "resources/snapshot/mem.snap"
Write-Host "`n✓  Base snapshot complete." -ForegroundColor Green