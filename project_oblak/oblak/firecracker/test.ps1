# firecracker/test.ps1
# Run from the oblak/ directory: .\firecracker\test.ps1

param([string]$OblakPath = "")

$ErrorActionPreference = "Stop"

# ── Output helpers ────────────────────────────────────────────────────────────
function Write-Step { param($msg) Write-Host "`n▶  $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "   " -NoNewline; Write-Host "✓" -ForegroundColor Green -NoNewline; Write-Host "  $msg" }
function Write-Fail { param($msg) Write-Host "   " -NoNewline; Write-Host "✗" -ForegroundColor Red   -NoNewline; Write-Host "  $msg"; exit 1 }
function Write-Info { param($msg) Write-Host "   $msg" }

# ── Resolve oblak path ────────────────────────────────────────────────────────
if ($OblakPath -eq "") { $OblakPath = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path "$OblakPath\firecracker"))            { Write-Fail "Could not find oblak/firecracker. Pass path explicitly: .\firecracker\test.ps1 -OblakPath C:\path\to\oblak" }
if (-not (Test-Path "$OblakPath\resources\vmlinux"))     { Write-Fail "resources/vmlinux not found — run setup.ps1 first" }
if (-not (Test-Path "$OblakPath\resources\rootfs.ext4")) { Write-Fail "resources/rootfs.ext4 not found — run setup.ps1 first" }

$WslOblakPath = (wsl wslpath -u ($OblakPath -replace '\\', '/')).Trim()
Write-Host "Oblak: $OblakPath" -ForegroundColor DarkGray

# ── Helpers ───────────────────────────────────────────────────────────────────
function Write-WslFile {
    param([string]$Content, [string]$Dest, [switch]$Sudo)
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Content))
    if ($Sudo) {
        wsl -u root bash -c "echo '$b64' | base64 -d | tee '$Dest' > /dev/null"
    } else {
        wsl bash -c "echo '$b64' | base64 -d | tee '$Dest' > /dev/null"
    }
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
$vcpu      = Get-VmConfig "vcpu_count" "1"
$mem       = Get-VmConfig "memory_mib" "128"
$VM_ID     = "test-vm"
$WslChroot = "/srv/jailer/firecracker/$VM_ID/root"

# ── Prepare chroot ────────────────────────────────────────────────────────────
Write-Step "Preparing test VM ($vcpu vCPU, ${mem}MiB RAM)"

$null = wsl -u root bash -c "rm -rf '/srv/jailer/firecracker/$VM_ID'" 2>&1
wsl -u root bash -c "mkdir -p '$WslChroot/resources' && cp '$WslOblakPath/resources/vmlinux' '$WslChroot/resources/vmlinux' && cp '$WslOblakPath/resources/rootfs.ext4' '$WslChroot/resources/rootfs.ext4' && chown -R firecracker-jailer:firecracker-jailer '$WslChroot'"
if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to set up chroot" }
Write-Ok "Resources copied to chroot"

$vmConfig = @"
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
        "vcpu_count": $vcpu,
        "mem_size_mib": $mem
    }
}
"@
Write-WslFile -Content $vmConfig -Dest "$WslChroot/vm-config.json" -Sudo
Write-Ok "Config written"

# ── Boot ──────────────────────────────────────────────────────────────────────
Write-Step "Booting MicroVM"
Write-Host "   " -NoNewline
Write-Host "Type 'exit' inside the VM to shut it down (press Enter to boot)" -ForegroundColor Yellow
$null = Read-Host
Write-Host ""

wsl -u root bash -c "jailer --id '$VM_ID' --exec-file /usr/local/bin/firecracker --uid `$(id -u firecracker-jailer) --gid `$(id -g firecracker-jailer) --chroot-base-dir /srv/jailer -- --config-file vm-config.json"

# ── Cleanup ───────────────────────────────────────────────────────────────────
$null = wsl -u root bash -c "rm -rf '/srv/jailer/firecracker/$VM_ID'" 2>&1

Write-Host "`n✓  MicroVM shut down cleanly." -ForegroundColor Green