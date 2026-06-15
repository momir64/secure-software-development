# firecracker/setup.ps1
# Run from the oblak/ directory in an elevated PowerShell: .\firecracker\setup.ps1

param([string]$OblakPath = "")

$ErrorActionPreference = "Stop"

# ── Output helpers ────────────────────────────────────────────────────────────
function Write-Step { param($msg) Write-Host "`n▶  $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "   " -NoNewline; Write-Host "✓" -ForegroundColor Green  -NoNewline; Write-Host "  $msg" }
function Write-Warn { param($msg) Write-Host "   " -NoNewline; Write-Host "⚠" -ForegroundColor Yellow -NoNewline; Write-Host "  $msg" }
function Write-Fail { param($msg) Write-Host "   " -NoNewline; Write-Host "✗" -ForegroundColor Red    -NoNewline; Write-Host "  $msg"; exit 1 }
function Write-Info { param($msg) Write-Host "   $msg" }

# ── Resolve oblak path ────────────────────────────────────────────────────────
if ($OblakPath -eq "") { $OblakPath = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path "$OblakPath\firecracker")) {
    Write-Fail "Could not find oblak/firecracker. Pass path explicitly: .\firecracker\setup.ps1 -OblakPath C:\path\to\oblak"
}
$WslOblakPath = (wsl wslpath -u ($OblakPath -replace '\\', '/')).Trim()
Write-Host "Oblak: $OblakPath" -ForegroundColor DarkGray

# ── Helpers ───────────────────────────────────────────────────────────────────

# Run a bash script in WSL2 via temp file. Normalizes CRLF to avoid bash errors
# when setup.ps1 is saved with Windows line endings.
function Invoke-WslScript {
    param([string]$Script, [string]$WorkDir = "", [switch]$AsRoot)
    $header = "#!/bin/bash`nset -e`n"
    $cd     = if ($WorkDir -ne "") { "cd '$WorkDir'`n" } else { "" }
    $content = ($header + $cd + $Script) -replace "`r`n", "`n" -replace "`r", "`n"
    $tmp = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + ".sh")
    [System.IO.File]::WriteAllText($tmp, $content, (New-Object System.Text.UTF8Encoding $false))
    $wslTmp = (wsl wslpath -u ($tmp -replace '\\', '/')).Trim()
    if ($AsRoot) { wsl -u root bash "$wslTmp" } else { wsl bash "$wslTmp" }
    $code = $LASTEXITCODE
    Remove-Item $tmp -ErrorAction SilentlyContinue
    if ($code -ne 0) { Write-Fail "Script failed (exit $code)" }
}

# Returns $true if the bash command exits 0
function Test-Wsl {
    param([string]$Command)
    $null = wsl bash -c $Command 2>&1
    return $LASTEXITCODE -eq 0
}

# Write text content to a WSL2 path using base64 to avoid quoting issues
function Write-WslFile {
    param([string]$Content, [string]$Dest, [switch]$Sudo)
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Content))
    if ($Sudo) {
        wsl -u root bash -c "echo '$b64' | base64 -d | tee '$Dest' > /dev/null"
    } else {
        wsl bash -c "echo '$b64' | base64 -d | tee '$Dest' > /dev/null"
    }
}

# Read a value from config/vm.toml
function Get-VmConfig {
    param([string]$Key, [string]$Default)
    $toml = "$OblakPath\config\vm.toml"
    if (Test-Path $toml) {
        $line = Get-Content $toml | Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1
        if ($line) { return (($line -split '=')[1]).Trim() }
    }
    return $Default
}

# ── Step 0: Hyper-V ───────────────────────────────────────────────────────────
Write-Step "Step 0: Virtualization"

if (-not (Get-ComputerInfo).HyperVisorPresent) {
    Write-Warn "Hyper-V not active. Enabling..."
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart | Out-Null
    Write-Fail "Restart your machine and re-run this script."
}
Write-Ok "Hyper-V is active"

# ── Step 1: KVM and vsock ─────────────────────────────────────────────────────
Write-Step "Step 1: KVM access and vsock"

$kvmModule = if ((Test-Wsl "grep -q GenuineIntel /proc/cpuinfo")) { "kvm_intel" } else { "kvm_amd" }
Write-Info "Detected CPU module: $kvmModule"
$wslConfCmd = "/sbin/modprobe $kvmModule; /sbin/modprobe vhost_vsock; chown root:kvm /dev/kvm && chmod 660 /dev/kvm; chown root:kvm /dev/vhost-vsock && chmod 660 /dev/vhost-vsock"

if (-not (Test-Wsl "grep -q 'vhost_vsock' /etc/wsl.conf 2>/dev/null")) {
    Write-Info "Writing /etc/wsl.conf..."
    Write-WslFile -Content "[boot]`ncommand = $wslConfCmd`n" -Dest "/etc/wsl.conf" -Sudo
    Write-Info "Restarting WSL2..."
    wsl --shutdown
    $elapsed = 0
    while ($elapsed -lt 30 -and -not (Test-Wsl "test -e /dev/kvm")) {
        Start-Sleep -Seconds 2; $elapsed += 2
    }
    Write-Ok "WSL2 restarted"
} else {
    Write-Ok "/etc/wsl.conf already configured"
}

if (-not (Test-Wsl "test -e /dev/kvm")) {
    Write-Fail "/dev/kvm not found. Check that KVM modules loaded correctly."
}
Write-Ok "/dev/kvm present"

$wslUser = (wsl bash -c "echo `$USER").Trim()
if (-not (Test-Wsl "groups | grep -q kvm")) {
    Write-Info "Adding user to kvm group..."
    Invoke-WslScript "groupadd -f kvm && usermod -aG kvm $wslUser" -AsRoot
    Write-Info "Restarting WSL2 for group membership..."
    wsl --shutdown
    $elapsed = 0
    while ($elapsed -lt 20 -and -not (Test-Wsl "true")) {
        Start-Sleep -Seconds 2; $elapsed += 2
    }
}
if (-not (Test-Wsl "groups | grep -q kvm")) {
    Write-Fail "User still not in kvm group after restart."
}
Write-Ok "User is in kvm group"

if (-not (Test-Wsl "test -e /dev/vhost-vsock")) {
    Write-Fail "/dev/vhost-vsock not found. Check that vhost_vsock module loaded correctly."
}
Write-Ok "/dev/vhost-vsock present"

# ── Step 2: Firecracker ───────────────────────────────────────────────────────
Write-Step "Step 2: Firecracker and Jailer"

if ((Test-Wsl "command -v firecracker") -and (Test-Wsl "command -v jailer")) {
    $fcVer = (wsl bash -c "firecracker --version 2>/dev/null | head -1").Trim()
    Write-Ok "Already installed: $fcVer"
} else {
    Write-Info "Downloading latest Firecracker release..."
    Invoke-WslScript @'
ARCH="$(uname -m)"
RELEASES_URL="https://github.com/firecracker-microvm/firecracker/releases"
LATEST=$(basename $(curl -fsSLI -o /dev/null -w %{url_effective} "${RELEASES_URL}/latest"))
BASE_URL="${RELEASES_URL}/download/${LATEST}/firecracker-${LATEST}-${ARCH}"
FILENAME="firecracker-${LATEST}-${ARCH}.tgz"
curl -fsSL -o "${FILENAME}" "${BASE_URL}.tgz"
curl -fsSL -o "${FILENAME}.sha256.txt" "${BASE_URL}.tgz.sha256.txt"
sha256sum -c "${FILENAME}.sha256.txt"
tar -xzf "${FILENAME}"
for binary in firecracker jailer; do
    mv "release-${LATEST}-${ARCH}/${binary}-${LATEST}-${ARCH}" /usr/local/bin/"${binary}"
    chmod +x /usr/local/bin/"${binary}"
done
rm -rf "${FILENAME}" "${FILENAME}.sha256.txt" "release-${LATEST}-${ARCH}"
'@ -AsRoot
    $fcVer   = (wsl bash -c "firecracker --version 2>/dev/null | head -1").Trim()
    $jailVer = (wsl bash -c "jailer --version 2>/dev/null | head -1").Trim()
    Write-Ok "Installed: $fcVer"
    Write-Ok "Installed: $jailVer"
}

# ── Step 3: Kernel ────────────────────────────────────────────────────────────
Write-Step "Step 3: Guest kernel"

if (Test-Path "$OblakPath\resources\vmlinux") {
    Write-Ok "Already present: resources/vmlinux"
} else {
    Write-Info "Downloading latest Firecracker CI kernel..."
    Invoke-WslScript @'
ARCH="$(uname -m)"
S3_CI_BASE="http://spec.ccfc.min.s3.amazonaws.com/?prefix=firecracker-ci/"
S3_BASE="https://s3.amazonaws.com/spec.ccfc.min"
CI_VERSION=$(curl -s "${S3_CI_BASE}&list-type=2&delimiter=/" \
    | grep -oP "(?<=firecracker-ci/)v[0-9]+\.[0-9]+(?=/)" \
    | sort -V | tail -1)
KERNEL_KEY=$(curl -s "${S3_CI_BASE}${CI_VERSION}/${ARCH}/vmlinux-&list-type=2" \
    | grep -oP "(?<=<Key>)(firecracker-ci/${CI_VERSION}/${ARCH}/vmlinux-[0-9]+\.[0-9]+\.[0-9]{1,3})(?=</Key>)" \
    | sort -V | tail -1)
mkdir -p resources
curl -fsSL -o resources/vmlinux "${S3_BASE}/${KERNEL_KEY}"
'@ -WorkDir $WslOblakPath
    Write-Ok "Kernel downloaded"
}

# ── Step 4: Root filesystem ───────────────────────────────────────────────────
Write-Step "Step 4: Root filesystem"

if (Test-Path "$OblakPath\resources\rootfs.ext4") {
    Write-Ok "Already present: resources/rootfs.ext4"
} else {
    $null = wsl -u root bash -c "docker version" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "docker not found in WSL2. Enable WSL integration in Docker Desktop: Settings -> Resources -> WSL Integration -> Ubuntu -> Apply"
    }
    $diskSize = Get-VmConfig "disk_size_mib" "512"
    Write-Info "Building rootfs (${diskSize}MiB)..."
    Invoke-WslScript ("DISK_SIZE=$diskSize`n" + @'
apt install -y e2fsprogs 2>/dev/null | tail -1
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
    Write-Ok "Root filesystem created: resources/rootfs.ext4 (${diskSize}MiB)"
}

# ── Step 5: Jailer ────────────────────────────────────────────────────────────
Write-Step "Step 5: Jailer"

if (Test-Wsl "id firecracker-jailer 2>/dev/null") {
    Write-Ok "User firecracker-jailer already exists"
} else {
    Invoke-WslScript "groupadd -f firecracker-jailer && useradd -r -s /sbin/nologin -g firecracker-jailer firecracker-jailer" -AsRoot
    Write-Ok "Created user firecracker-jailer"
}

if (Test-Wsl "test -d /srv/jailer") {
    Write-Ok "/srv/jailer already exists"
} else {
    Invoke-WslScript "mkdir -p /srv/jailer && chown firecracker-jailer:firecracker-jailer /srv/jailer" -AsRoot
    Write-Ok "Created /srv/jailer"
}

# ── Step 6: TAP networking ────────────────────────────────────────────────────
Write-Step "Step 6: TAP networking"

$null = wsl -u root bash -c "ip tuntap add dev tap-test mode tap 2>/dev/null && ip tuntap del dev tap-test mode tap 2>/dev/null" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Ok "TAP device creation works"
} else {
    Write-Fail "TAP device creation failed"
}

$null = wsl -u root bash -c "iptables -t nat -L 2>/dev/null" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Ok "iptables NAT available"
} else {
    Write-Fail "iptables NAT not available"
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host "`n✓  Setup complete." -ForegroundColor Green
Write-Info "Run .\firecracker\test.ps1 to verify the MicroVM boots."