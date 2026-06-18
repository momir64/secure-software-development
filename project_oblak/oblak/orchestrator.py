from dataclasses import dataclass
from pathlib import Path
import subprocess
import threading
import tomllib
import shutil
import socket
import vmlib
import json
import uuid
import os

# ── Paths ─────────────────────────────────────────────────────────────────────

_BASE = Path(__file__).parent
_RESOURCES = _BASE / "resources"
_ROOTFS = _RESOURCES / "rootfs.ext4"
_STUB = _RESOURCES / "stub.ext4"
_SNAP_VMSTATE = _RESOURCES / "snapshot" / "vmstate"
_SNAP_MEM = _RESOURCES / "snapshot" / "mem.snap"
_LAMBDAS = _BASE / "lambdas"
_ENVS = _BASE / "envs"
_CHROOT_BASE = Path("/srv/jailer")


# ── Config ────────────────────────────────────────────────────────────────────

def _load_config() -> dict:
    with open(_BASE / "config" / "vm.toml", "rb") as f:
        return tomllib.load(f)


_cfg = _load_config()
_MEM = _cfg["vm"]["memory_mib"]
_VCPU = _cfg["vm"]["vcpu_count"]
_MAX_SLOTS = _cfg["vm"]["max_ip_slots"]
_IDLE_TIMEOUT = _cfg["vm"]["idle_timeout_seconds"]
_HANDLER_TIMEOUT = _cfg["vm"]["handler_timeout_seconds"]
_CPU_PERIOD_US = _cfg["vm"].get("cpu_period_us", 100000)
_CPU_QUOTA_FRACTION = _cfg["vm"].get("cpu_quota_fraction", 1.0)
_CPU_QUOTA_US = int(_VCPU * _CPU_PERIOD_US * _CPU_QUOTA_FRACTION)

_JAILER_UID, _JAILER_GID = vmlib.jailer_ids()

# ── IP slot pool ──────────────────────────────────────────────────────────────
# Slot N gets two /30 subnets:
#   VM subnet  172.16.{N*4>>8}.{N*4&0xff}/30  — tap0 (host) ↔ eth0 (guest)
#   Veth pair  172.17.{N*4>>8}.{N*4&0xff}/30  — veth-h{N} (host) ↔ veth-n{N} (namespace)

_VM_CIDR = "172.16.0.0/12"

_IPTABLES_RULES = [
    ("nat", "POSTROUTING", ["-s", _VM_CIDR, "!", "-d", _VM_CIDR, "-j", "MASQUERADE"]),
    ("filter", "FORWARD", ["-s", _VM_CIDR, "-j", "ACCEPT"]),
    ("filter", "FORWARD", ["-d", _VM_CIDR, "-j", "ACCEPT"]),
]


# ── State ─────────────────────────────────────────────────────────────────────

@dataclass
class _VM:
    process: subprocess.Popen
    conn: socket.socket
    slot: int
    chroot: Path
    timer: threading.Timer | None = None


_warm: dict[str, _VM] = {}
_available_slots: list[int] = list(range(_MAX_SLOTS))
_lock = threading.Lock()


# ── vsock ─────────────────────────────────────────────────────────────────────

def _vsock_connect(uds: str) -> socket.socket:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(uds)
    sock.sendall(b"CONNECT 8080\n")
    line = b""
    while not line.endswith(b"\n"):
        chunk = sock.recv(1)
        if not chunk:
            raise ConnectionError("vsock handshake failed")
        line += chunk
    if not line.startswith(b"OK"):
        raise ConnectionError(f"vsock rejected: {line!r}")
    return sock


def _send_msg(conn: socket.socket, obj: dict) -> None:
    data = json.dumps(obj).encode()
    conn.sendall(len(data).to_bytes(4, "big") + data)


def _recv_msg(conn: socket.socket) -> dict:
    def recv_exact(n: int) -> bytes:
        buf = bytearray()
        while len(buf) < n:
            chunk = conn.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("connection closed")
            buf.extend(chunk)
        return bytes(buf)

    return json.loads(recv_exact(int.from_bytes(recv_exact(4), "big")))


def _call(conn: socket.socket, msg: dict) -> dict:
    _send_msg(conn, msg)
    return _recv_msg(conn)


# ── Chroot ────────────────────────────────────────────────────────────────────

def _prepare_chroot(vm_id: str, lambda_id: str, env_hash: str | None) -> Path:
    chroot = _CHROOT_BASE / "firecracker" / vm_id / "root"
    res = chroot / "resources"
    res.mkdir(parents=True, exist_ok=True)
    (chroot / "run").mkdir(exist_ok=True)
    tmp = chroot / "tmp"
    tmp.mkdir(exist_ok=True)
    os.chmod(tmp, 0o1777)

    vmlib.link_or_copy(_ROOTFS, res / "rootfs.ext4")
    vmlib.link_or_copy(_STUB, res / "stub.ext4")
    vmlib.link_or_copy(_LAMBDAS / f"{lambda_id}.ext4", res / "lambda.ext4")
    vmlib.link_or_copy(_SNAP_VMSTATE, res / "vmstate")
    vmlib.link_or_copy(_SNAP_MEM, res / "mem.snap")

    if env_hash is not None:
        shutil.copy2(_ENVS / f"env_{env_hash}.ext4", res / "env.ext4")
        os.chmod(res / "env.ext4", 0o644)

    for d in (chroot, res, chroot / "run"):
        os.chown(d, _JAILER_UID, _JAILER_GID)

    for f in res.iterdir():
        os.chown(f, _JAILER_UID, _JAILER_GID)

    return chroot


# ── VM lifecycle ──────────────────────────────────────────────────────────────

def _cold_start(lambda_id: str, env_hash: str | None) -> _VM:
    with _lock:
        if not _available_slots:
            raise RuntimeError("no available IP slots")
        slot = _available_slots.pop(0)

    vm_id = str(uuid.uuid4())
    chroot = None
    ns_created = False
    process = None

    try:
        chroot = _prepare_chroot(vm_id, lambda_id, env_hash)
        veth_h, veth_n = vmlib.veth_names(slot)
        host_ip, guest_ip = vmlib.slot_up(veth_h, veth_n, "172.16", "172.17", slot, _JAILER_UID)
        ns_created = True
        api_sock = str(chroot / "run" / "fc.sock")
        vsock_uds = str(chroot / "tmp" / "v.sock")

        process = subprocess.Popen(
            [
                "jailer",
                "--id", vm_id,
                "--exec-file", "/usr/local/bin/firecracker",
                "--uid", str(_JAILER_UID),
                "--gid", str(_JAILER_GID),
                "--chroot-base-dir", str(_CHROOT_BASE),
                "--netns", f"/var/run/netns/{vmlib.slot_name(slot)}",
                "--resource-limit", "no-file=2048",
                "--resource-limit", f"fsize={_cfg['rootfs']['disk_size_mib'] * 1024 * 1024}",
                "--cgroup-version", "2",
                "--cgroup", f"memory.max={_MEM * 1024 * 1024}",
                "--cgroup", f"cpu.max={_CPU_QUOTA_US} {_CPU_PERIOD_US}",
                "--",
                "--api-sock", "run/fc.sock",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        vmlib.wait_path(api_sock)

        vmlib.fc(api_sock, "PUT", "/snapshot/load", {
            "snapshot_path": "resources/vmstate",
            "mem_backend": {"backend_path": "resources/mem.snap", "backend_type": "File"},
            "enable_diff_snapshots": False,
            "resume_vm": False,
        })
        vmlib.fc(api_sock, "PATCH", "/drives/task", {
            "drive_id": "task", "path_on_host": "resources/lambda.ext4",
        })
        if env_hash is not None:
            vmlib.fc(api_sock, "PATCH", "/drives/env", {
                "drive_id": "env", "path_on_host": "resources/env.ext4",
            })
        vmlib.fc(api_sock, "PATCH", "/vm", {"state": "Resumed"})

        vmlib.wait_path(vsock_uds)
        conn = _vsock_connect(vsock_uds)

        setup_msg = {
            "type": "setup",
            "task_dev": "/dev/vdc",
            "network": {"guest_ip": guest_ip, "prefix": 30, "gateway": host_ip},
        }
        if env_hash is not None:
            setup_msg["env_dev"] = "/dev/vdb"

        result = _call(conn, setup_msg)
        if result.get("status") != "ok":
            raise RuntimeError(f"runner setup failed: {result}")

        return _VM(process=process, conn=conn, slot=slot, chroot=chroot)

    except Exception:
        if process is not None:
            process.kill()
            process.wait()
        if ns_created:
            vmlib.netns_down(slot)
        if chroot:
            subprocess.run(["rm", "-rf", str(chroot.parent)], check=False)
        with _lock:
            _available_slots.append(slot)
        raise


def _destroy(vm: _VM) -> None:
    try:
        vm.conn.close()
    except OSError:
        pass
    vm.process.kill()
    vm.process.wait()
    vmlib.netns_down(vm.slot)
    subprocess.run(["rm", "-rf", str(vm.chroot.parent)], check=False)
    with _lock:
        _available_slots.append(vm.slot)


def _reset_timer(lambda_id: str, vm: _VM) -> None:
    if vm.timer:
        vm.timer.cancel()

    def on_idle():
        with _lock:
            if _warm.get(lambda_id) is vm:
                del _warm[lambda_id]
        _destroy(vm)

    vm.timer = threading.Timer(_IDLE_TIMEOUT, on_idle)
    vm.timer.daemon = True
    vm.timer.start()


# ── Public API ────────────────────────────────────────────────────────────────

def invoke(lambda_id: str, script: str, input_str: str, env_hash: str | None = None) -> dict:
    with _lock:
        vm = _warm.get(lambda_id)
        if vm and vm.timer:
            vm.timer.cancel()
            vm.timer = None

    if vm is None:
        vm = _cold_start(lambda_id, env_hash)
        with _lock:
            _warm[lambda_id] = vm

    try:
        vm.conn.settimeout(_HANDLER_TIMEOUT)
        result = _call(vm.conn, {"script": script, "input": input_str})
        vm.conn.settimeout(None)
    except socket.timeout:
        with _lock:
            _warm.pop(lambda_id, None)
        _destroy(vm)
        return {"output": "", "stderr": "handler timeout exceeded", "exit_code": 1}
    except (ConnectionError, OSError) as exc:
        with _lock:
            _warm.pop(lambda_id, None)
        _destroy(vm)
        raise RuntimeError(f"VM connection lost during invoke: {exc}") from exc

    _reset_timer(lambda_id, vm)
    return result


def startup() -> None:
    subprocess.run(["sysctl", "-w", "net.ipv4.ip_forward=1"], check=True, stdout=subprocess.DEVNULL)
    for table, chain, rule in _IPTABLES_RULES:
        exists = subprocess.run(["iptables", "-t", table, "-C", chain] + rule, capture_output=True)
        if exists.returncode != 0:
            subprocess.run(["iptables", "-t", table, "-A", chain] + rule, check=True)


def destroy(lambda_id: str) -> None:
    with _lock:
        vm = _warm.pop(lambda_id, None)
    if vm is None:
        return
    if vm.timer:
        vm.timer.cancel()
    _destroy(vm)


def shutdown() -> None:
    with _lock:
        items = list(_warm.items())
        _warm.clear()
    for _, vm in items:
        if vm.timer:
            vm.timer.cancel()
        _destroy(vm)
    for table, chain, rule in _IPTABLES_RULES:
        subprocess.run(["iptables", "-t", table, "-D", chain] + rule, check=False)
