from pathlib import Path
import subprocess
import threading
import hashlib
import tomllib
import shutil
import vmlib
import time
import uuid
import os

# ── Paths ─────────────────────────────────────────────────────────────────────

_BASE = Path(__file__).parent
_RESOURCES = _BASE / "resources"
_ROOTFS = _RESOURCES / "rootfs.ext4"
_ENVS = _BASE / "envs"
_LAMBDAS = _BASE / "lambdas"
_CHROOT_BASE = Path("/srv/jailer")

# ── Config ────────────────────────────────────────────────────────────────────

with open(_BASE / "config" / "vm.toml", "rb") as _f:
    _cfg = tomllib.load(_f)

_MEM = _cfg["vm"]["env_memory_mib"]
_VCPU = _cfg["vm"]["env_vcpu_count"]
_LAMBDA_SIZE_MIB = _cfg["vm"]["lambda_size_mib"]
_ENV_SIZE_MIB = _cfg["vm"].get("env_size_mib", 256)
_ENV_BUILD_TIMEOUT = _cfg["vm"].get("env_build_timeout_seconds", 600)
_MAX_ENV_SLOTS = _cfg["vm"].get("max_env_build_slots", 4)
_CPU_PERIOD_US = _cfg["vm"].get("cpu_period_us", 100000)
_CPU_QUOTA_FRACTION = _cfg["vm"].get("cpu_quota_fraction", 1.0)
_CPU_QUOTA_US = int(_VCPU * _CPU_PERIOD_US * _CPU_QUOTA_FRACTION)

_JAILER_UID, _JAILER_GID = vmlib.jailer_ids()

# ── Build slot pool ───────────────────────────────────────────────────────────
# Slot N gets two /30 subnets:
#   tap subnet   172.18.{N*4>>8}.{N*4&0xff}/30  — tap0 (host) ↔ eth0 (guest)
#   veth pair    172.19.{N*4>>8}.{N*4&0xff}/30  — veth-eh{N} (host) ↔ veth-en{N} (namespace)

_available_env_slots: list[int] = list(range(_MAX_ENV_SLOTS))
_env_slot_cv = threading.Condition()


def _acquire_env_slot() -> int:
    with _env_slot_cv:
        while not _available_env_slots:
            _env_slot_cv.wait()
        return _available_env_slots.pop(0)


def _release_env_slot(slot: int) -> None:
    with _env_slot_cv:
        _available_env_slots.append(slot)
        _env_slot_cv.notify()


# ── Helpers ───────────────────────────────────────────────────────────────────

def _env_hash(requirements: str) -> str:
    normalized = "\n".join(sorted(requirements.splitlines()))
    return hashlib.sha256(normalized.encode()).hexdigest()[:16]


def _wait_exit(pid: int, timeout: float = _ENV_BUILD_TIMEOUT) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return
        if subprocess.run(["kill", "-0", str(pid)], capture_output=True).returncode != 0:
            return
        time.sleep(0.5)
    subprocess.run(["kill", "-9", str(pid)], check=False)
    raise TimeoutError("env builder VM did not exit in time")


def _make_ext4(path: Path, size_mib: int, src_dir: Path | None = None, extra_opts: list[str] | None = None, capture_output: bool = False) -> None:
    subprocess.run(["truncate", "-s", f"{size_mib}M", str(path)], check=True)
    cmd = ["mkfs.ext4", "-q", *(extra_opts or []), *(["-d", str(src_dir)] if src_dir else []), "-F", str(path)]
    subprocess.run(cmd, check=True, capture_output=capture_output)


def _prepare_env_chroot(vm_id: str) -> Path:
    chroot = _CHROOT_BASE / "firecracker" / vm_id / "root"
    res = chroot / "resources"
    res.mkdir(parents=True, exist_ok=True)
    (chroot / "run").mkdir(exist_ok=True)

    vmlib.link_or_copy(_ROOTFS, res / "rootfs.ext4")
    vmlib.link_or_copy(_RESOURCES / "vmlinux", res / "vmlinux")

    for d in (chroot, res, chroot / "run"):
        os.chown(d, _JAILER_UID, _JAILER_GID)
    for f in res.iterdir():
        os.chown(f, _JAILER_UID, _JAILER_GID)

    return chroot


def _configure_fc_vm(fc_sock: str, guest_ip: str, host_ip: str) -> None:
    vmlib.fc(fc_sock, "PUT", "/machine-config", {
        "vcpu_count": _VCPU,
        "mem_size_mib": _MEM,
    })
    vmlib.fc(fc_sock, "PUT", "/boot-source", {
        "kernel_image_path": "resources/vmlinux",
        "boot_args": f"console=ttyS0 reboot=k panic=1 pci=off env_ip={guest_ip}/30 env_gw={host_ip} init=/var/runtime/env_builder.sh",
    })
    vmlib.fc(fc_sock, "PUT", "/drives/rootfs", {
        "drive_id": "rootfs",
        "path_on_host": "resources/rootfs.ext4",
        "is_root_device": True,
        "is_read_only": True,
    })
    vmlib.fc(fc_sock, "PUT", "/drives/req", {
        "drive_id": "req",
        "path_on_host": "resources/req.ext4",
        "is_root_device": False,
        "is_read_only": True,
    })
    vmlib.fc(fc_sock, "PUT", "/drives/env", {
        "drive_id": "env",
        "path_on_host": "resources/env.ext4",
        "is_root_device": False,
        "is_read_only": False,
    })
    vmlib.fc(fc_sock, "PUT", "/network-interfaces/eth0", {
        "iface_id": "eth0",
        "host_dev_name": "tap0",
        "guest_mac": "AA:FC:00:00:00:02",
    })
    vmlib.fc(fc_sock, "PUT", "/actions", {"action_type": "InstanceStart"})


# ── Public API ────────────────────────────────────────────────────────────────

def deploy_lambda(lambda_id: str, script_dir: str) -> None:
    _LAMBDAS.mkdir(exist_ok=True)
    out = _LAMBDAS / f"{lambda_id}.ext4"
    _make_ext4(out, _LAMBDA_SIZE_MIB, src_dir=Path(script_dir), capture_output=True)
    os.chown(out, _JAILER_UID, _JAILER_GID)
    os.chmod(out, 0o640)


def env_needs_build(requirements: str) -> bool:
    if not requirements.strip():
        return False
    return not (_ENVS / f"env_{_env_hash(requirements)}.ext4").exists()


def ensure_env(requirements: str) -> str | None:
    """
    Build an env image for the given requirements.txt contents if one doesn't
    already exist. Returns the env hash, or None if requirements is empty.
    """
    if not requirements.strip():
        return None

    hash_ = _env_hash(requirements)
    env_image = _ENVS / f"env_{hash_}.ext4"

    if env_image.exists():
        return hash_

    _ENVS.mkdir(exist_ok=True)

    vm_id = str(uuid.uuid4())
    work_dir = _ENVS / f".build-{uuid.uuid4().hex}"
    work_dir.mkdir()
    req_dir = work_dir / "req"
    req_dir.mkdir()

    process = None
    chroot = None
    ns_created = False
    slot = _acquire_env_slot()

    try:
        (req_dir / "requirements.txt").write_text(requirements)

        chroot = _prepare_env_chroot(vm_id)
        res = chroot / "resources"

        _make_ext4(res / "req.ext4", 4, src_dir=req_dir, extra_opts=["-O", "^has_journal"])
        _make_ext4(res / "env.ext4", _ENV_SIZE_MIB)
        for f in (res / "req.ext4", res / "env.ext4"):
            os.chown(f, _JAILER_UID, _JAILER_GID)

        veth_h, veth_n = vmlib.veth_names(slot, True)
        host_ip, guest_ip = vmlib.slot_up(veth_h, veth_n, "172.18", "172.19", slot, _JAILER_UID, True)
        ns_created = True

        fc_sock = str(chroot / "run" / "fc.sock")
        log_path = work_dir / "fc.log"

        with open(log_path, "w") as log_fh:
            process = subprocess.Popen(
                [
                    "jailer",
                    "--id", vm_id,
                    "--exec-file", "/usr/local/bin/firecracker",
                    "--uid", str(_JAILER_UID),
                    "--gid", str(_JAILER_GID),
                    "--chroot-base-dir", str(_CHROOT_BASE),
                    "--netns", f"/var/run/netns/{vmlib.slot_name(slot, True)}",
                    "--resource-limit", "no-file=2048",
                    "--resource-limit", f"fsize={_ENV_SIZE_MIB * 1024 * 1024}",
                    "--cgroup-version", "2",
                    "--cgroup", f"memory.max={_MEM * 1024 * 1024}",
                    "--cgroup", f"cpu.max={_CPU_QUOTA_US} {_CPU_PERIOD_US}",
                    "--",
                    "--api-sock", "run/fc.sock",
                ],
                stdout=log_fh,
                stderr=log_fh,
            )

        vmlib.wait_path(fc_sock)
        _configure_fc_vm(fc_sock, guest_ip, host_ip)
        _wait_exit(process.pid)
        process = None

        result = subprocess.run(["debugfs", "-R", "ls /", str(res / "env.ext4")], capture_output=True, text=True)
        if ".__build_ok__" not in result.stdout:
            log_contents = log_path.read_text() if log_path.exists() else "no log"
            raise RuntimeError(f"env build failed: pip install failed\n{log_contents}")

        shutil.copy2(res / "env.ext4", env_image)
        os.chmod(env_image, 0o644)
        return hash_

    finally:
        if process is not None:
            process.kill()
            process.wait()
        if ns_created:
            vmlib.netns_down(slot, True)
        if chroot:
            subprocess.run(["rm", "-rf", str(chroot.parent)], check=False)
        _release_env_slot(slot)
        subprocess.run(["rm", "-rf", str(work_dir)], check=False)
