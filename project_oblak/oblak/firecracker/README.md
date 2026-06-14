# Setting up Firecracker on Windows with WSL2 or Native Linux

## Automated setup

### Native Linux

Three shell scripts handle the full setup on native Linux. Run them from the `oblak/` directory:

```bash
# Step 1: one-time environment setup (installs Firecracker, builds rootfs, configures KVM)
sudo bash firecracker/setup.sh

# Step 2 (optional): verify the MicroVM boots before continuing
sudo bash firecracker/test.sh

# Step 3: build rootfs and take the base memory snapshot (re-run whenever Dockerfile or runner.py changes)
sudo bash firecracker/snapshot.sh
```

- `setup.sh` reads `config/vm.toml` for resource limits, installs Firecracker + Jailer, downloads the CI kernel, builds `resources/rootfs.ext4`, and configures KVM permissions
- `test.sh` boots a test MicroVM with `init=/bin/sh` so you can verify the full stack interactively — type `reboot` to exit
- `snapshot.sh` rebuilds `rootfs.ext4` and takes a full memory snapshot of a booted runner, storing it in `resources/snapshot/`

> **Note:** After `setup.sh`, run `newgrp kvm` or log out and back in for the `kvm` group membership to take effect before running the other scripts.

### Windows with WSL2

Process of setting up Firecracker is automated with `firecracker/setup.ps1` script. To test if MicroVMs are able to run without the orchestrator use `firecracker/test.ps1` script. Run them from `oblak/` directory in an elevated PowerShell:

```powershell
cd oblak
.\firecracker\setup.ps1
.\firecracker\test.ps1
.\firecracker\snapshot.ps1
```

- `setup.ps1` handles WSL2 restarts automatically and reads `config/vm.toml` for resource limits
- `test.ps1` boots a test MicroVM using values from `config/vm.toml`
- `snapshot.ps1` rebuilds `rootfs.ext4` and takes the base memory snapshot

If there's a problem with running the scripts, try to execute:
```powershell
Set-ExecutionPolicy -Scope Process RemoteSigned
Unblock-File -Path .\firecracker\setup.ps1
Unblock-File -Path .\firecracker\test.ps1
Unblock-File -Path .\firecracker\snapshot.ps1
```

More details about what setup does are provided in the steps below.

---

## Manual setup

### Step 0: Set up WSL2 with virtualization (Windows only)

Instructions on how to install Ubuntu on Windows using WSL2 can be found on [Microsoft Learn article](https://learn.microsoft.com/en-us/windows/wsl/install).

Verify that virtualization is enabled:
```powershell
(Get-ComputerInfo).HyperVisorPresent
```

If this returns `False`, first enable Intel VT-x or AMD-V in your BIOS/UEFI settings, then enable Hyper-V from an elevated PowerShell:
```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

Restart your machine before continuing.

On native Linux, verify that your CPU supports virtualization and it is enabled in BIOS/UEFI:
```bash
grep -E 'vmx|svm' /proc/cpuinfo
```

### Step 1: Set up KVM access

Firecracker relies on KVM (Kernel-based Virtual Machine), a Linux kernel module that virtualizes hardware resources and sits between the host kernel and Firecracker. It allows Firecracker to run isolated MicroVMs with near-native performance.

Inside WSL2 (or on native Linux), verify that KVM is available:

```bash
ls /dev/kvm
```

If the device is not present, load the kernel module manually (use `kvm_amd` on AMD CPUs):
```bash
sudo modprobe kvm_intel
```

Set up a `kvm` group and add your user to it:

```bash
sudo groupadd -f kvm
sudo usermod -aG kvm $USER
```

**WSL2 only** — configure the modules and permissions via the boot command in `/etc/wsl.conf` so they persist across WSL2 restarts (use `kvm_amd` instead of `kvm_intel` on AMD CPUs):

```bash
sudo tee /etc/wsl.conf << 'EOF'
[boot]
command = /sbin/modprobe kvm_intel; chown root:kvm /dev/kvm && chmod 660 /dev/kvm
EOF
```

Then restart WSL2 from PowerShell:

```powershell
wsl --shutdown
```

**Native Linux** — set permissions directly:
```bash
sudo chown root:kvm /dev/kvm && sudo chmod 660 /dev/kvm
```

Reopen WSL2 (or re-login on Linux) and verify:

```bash
ls -l /dev/kvm
groups | grep kvm
```

You should see `crw-rw----` with group `kvm`, and `kvm` listed in your groups.


### Step 2: Download and install Firecracker

First, resolve the latest release version:
```bash
ARCH="$(uname -m)"
RELEASES_URL="https://github.com/firecracker-microvm/firecracker/releases"
LATEST=$(basename $(curl -fsSLI -o /dev/null -w %{url_effective} ${RELEASES_URL}/latest))
BASE_URL="${RELEASES_URL}/download/${LATEST}/firecracker-${LATEST}-${ARCH}"
FILENAME="firecracker-${LATEST}-${ARCH}.tgz"
```

Download the release and verify its checksum:
```bash
curl -fsSL -o "${FILENAME}" "${BASE_URL}.tgz"
curl -fsSL -o "${FILENAME}.sha256.txt" "${BASE_URL}.tgz.sha256.txt"
sha256sum -c "${FILENAME}.sha256.txt"
```

If checksum passes, extract and install the firecracker and jailer binaries:
```bash
tar -xzf "${FILENAME}"
for binary in firecracker jailer; do
    sudo mv "release-${LATEST}-${ARCH}/${binary}-${LATEST}-${ARCH}" /usr/local/bin/"${binary}"
    sudo chmod +x /usr/local/bin/"${binary}"
done
rm -rf "${FILENAME}" "${FILENAME}.sha256.txt" "release-${LATEST}-${ARCH}"
```

Verify the installation:
```bash
firecracker --version
jailer --version
```


### Step 3: Set up guest kernel and base root filesystem

The guest kernel is a Linux kernel binary that Firecracker boots inside each MicroVM. The root filesystem is the base disk image MicroVMs start from and is prebuilt with Python. Instead of installing Lambda dependencies on each cold start, the orchestrator maintains a dedicated snapshot for each Lambda. On deployment, the orchestrator boots a MicroVM from the base image, installs its dependencies, and snapshots the VM state. Subsequent invocations restore that snapshot, bypassing the boot and install process.

Snapshots are identified by a hash of the sorted contents of `requirements.txt`, so Lambdas sharing the same dependencies reuse the same snapshot regardless of declaration order. The script itself is not included in the snapshot and is injected into the running VM at invocation time.

**Run these commands from the root of the Oblak directory.** 

#### Kernel

Download the latest Firecracker CI kernel:
```bash
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
```

#### Root filesystem image

Docker is used to build the base filesystem image for the MicroVM. If `docker` is not available in WSL2, enable WSL integration in Docker Desktop under **Settings → Resources → WSL Integration**, enable **Ubuntu** distro and click **Apply**.

Using `firecracker/rootfs/Dockerfile`:
```dockerfile
FROM alpine:3.19

RUN apk add --no-cache python3 curl

# Install uv instead of pip for faster Python dependency management
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Configure serial console for Firecracker
RUN echo "ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100" >> /etc/inittab && \
    echo "ttyS0" >> /etc/securetty
```

Build the base Docker image and convert it to an ext4 disk image that Firecracker mounts as the MicroVM's root drive. The `truncate` size should match `disk_size_mib` in `config/vm.toml`:
```bash
sudo apt install -y e2fsprogs
mkdir -p resources /tmp/oblak-rootfs

docker build -t oblak-base firecracker/rootfs/
docker create --name oblak-base-tmp oblak-base
docker export oblak-base-tmp | sudo tar -x -C /tmp/oblak-rootfs/
docker rm oblak-base-tmp

truncate -s 512M resources/rootfs.ext4
sudo mkfs.ext4 -d /tmp/oblak-rootfs -F resources/rootfs.ext4
sudo rm -rf /tmp/oblak-rootfs
```

#### VM configuration

Use `config/vm.toml` to configure MicroVM resource limits. These values are used both by the automated setup script and the orchestrator at runtime:
```toml
[vm]
vcpu_count = 1
memory_mib = 128
idle_timeout_seconds = 300
handler_timeout_seconds = 30

[rootfs]
disk_size_mib = 512
```

`vcpu_count` and `memory_mib` are passed directly to Firecracker's machine configuration API. `timeout_seconds` is enforced by the orchestrator to terminate VMs that exceed the execution time limit. `disk_size_mib` determines the size of the root filesystem image.


### Step 4: Set up Jailer

Jailer wraps Firecracker in a chroot jail, drops privileges to a dedicated unprivileged user, and enforces cgroup resource limits. It is the secure way to run Firecracker in production.

Create a dedicated user and group for Jailer to drop privileges to:
```bash
sudo groupadd -f firecracker-jailer
sudo useradd -r -s /sbin/nologin -g firecracker-jailer firecracker-jailer
```

Create the chroot base directory:
```bash
sudo mkdir -p /srv/jailer
sudo chown firecracker-jailer:firecracker-jailer /srv/jailer
```

Verify the setup:
```bash
id firecracker-jailer
ls -ld /srv/jailer
```

You should see the `firecracker-jailer` user and group, and `/srv/jailer` owned by `firecracker-jailer`.


### Step 5: Verify TAP networking support

A TAP device is a virtual network interface on the host that Firecracker connects the MicroVM to, giving it network access. Traffic is forwarded to the internet via NAT while iptables rules prevent MicroVMs from accessing the local network. The orchestrator manages TAP devices dynamically — this step only verifies that the necessary support is available.

Verify that TAP device creation works:
```bash
sudo ip tuntap add dev tap-test mode tap
sudo ip link show tap-test
sudo ip tuntap del dev tap-test mode tap
```

Any error on the `add` or `del` commands means TAP support is not available.  
`ip link show tap-test` should print a line starting with `tap-test:`

Verify that iptables NAT is available:
```bash
sudo iptables -t nat -L
```

This should print four chains: `PREROUTING`, `INPUT`, `OUTPUT`, and `POSTROUTING`.  
An error here means NAT is not available in your setup.

If either check fails, the orchestrator will not be able to provide MicroVMs with network access.


### Step 6: Verify vsock support

Vsock (Virtual Socket) is a communication channel between the host and a MicroVM. The orchestrator uses it to inject Python scripts into the running VM, pass input, and receive output back.

**WSL2 only** — change `/etc/wsl.conf` to add `vhost_vsock` alongside the KVM boot command from Step 1 (use `kvm_amd` instead of `kvm_intel` on AMD CPUs):
```bash
sudo tee /etc/wsl.conf << 'EOF'
[boot]
command = /sbin/modprobe kvm_intel; /sbin/modprobe vhost_vsock; chown root:kvm /dev/kvm && chmod 660 /dev/kvm; chown root:kvm /dev/vhost-vsock && chmod 660 /dev/vhost-vsock
EOF
```

Then restart WSL2 from PowerShell:
```powershell
wsl --shutdown
```

**Native Linux** — load the module and set permissions directly:
```bash
sudo modprobe vhost_vsock
sudo chown root:kvm /dev/vhost-vsock && sudo chmod 660 /dev/vhost-vsock
```

Reopen WSL2 (or re-login on Linux) and verify:
```bash
ls -l /dev/vhost-vsock
```

You should see `crw-rw----` with group `kvm`.


### Step 7: Test boot a MicroVM (optional)

This step boots a MicroVM through Jailer using the kernel and rootfs from Step 3 to verify the full stack works without using the orchestrator. On Linux you can also use `sudo bash firecracker/test.sh` to do this automatically.

Create the chroot directory and copy the required resources into it:
```bash
VM_ID="test-vm"
CHROOT_DIR="/srv/jailer/firecracker/${VM_ID}/root"

sudo mkdir -p "${CHROOT_DIR}/resources"
sudo cp resources/vmlinux "${CHROOT_DIR}/resources/vmlinux"
sudo cp resources/rootfs.ext4 "${CHROOT_DIR}/resources/rootfs.ext4"
sudo chown -R firecracker-jailer:firecracker-jailer "${CHROOT_DIR}"
```

Create a Firecracker config file inside the chroot:
```bash
sudo tee "${CHROOT_DIR}/vm-config.json" << 'EOF'
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
        "vcpu_count": 1,
        "mem_size_mib": 128
    }
}
EOF
```

Boot the MicroVM through Jailer:
```bash
sudo jailer \
    --id "${VM_ID}" \
    --exec-file /usr/local/bin/firecracker \
    --uid $(id -u firecracker-jailer) \
    --gid $(id -g firecracker-jailer) \
    --chroot-base-dir /srv/jailer \
    -- \
    --config-file vm-config.json
```

You should see the Alpine Linux boot sequence in the terminal. You can run `reboot` inside the MicroVM to shut it down.

Clean up after the test:
```bash
sudo rm -rf /srv/jailer/firecracker/${VM_ID}
```