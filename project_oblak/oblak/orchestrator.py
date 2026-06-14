from dataclasses import dataclass
from pathlib import Path
import http.client
import subprocess
import threading
import tomllib
import shutil
import socket
import json
import time
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
_CHROOT_BASE = Path("/srv/jailer")


# ── Config ────────────────────────────────────────────────────────────────────

def _load_config() -> dict:
    with open(_BASE / "config" / "vm.toml", "rb") as f:
        return tomllib.load(f)


_cfg = _load_config()
_MEM = _cfg["vm"]["memory_mib"]
_VCPU = _cfg["vm"]["vcpu_count"]
_MAX_SLOTS = _cfg["vm"]["max_ip_slots"]
_LAMBDA_SIZE_MIB = _cfg["vm"]["lambda_size_mib"]
_IDLE_TIMEOUT = _cfg["vm"]["idle_timeout_seconds"]
_HANDLER_TIMEOUT = _cfg["vm"]["handler_timeout_seconds"]
_CPU_PERIOD_US = _cfg["vm"].get("cpu_period_us", 100000)
_CPU_QUOTA_US = _cfg["vm"].get("cpu_quota_us", 100000)

_JAILER_UID = int(subprocess.check_output(["id", "-u", "firecracker-jailer"]).strip())
_JAILER_GID = int(subprocess.check_output(["id", "-g", "firecracker-jailer"]).strip())

# ── IP slot pool ──────────────────────────────────────────────────────────────
# Slot N gets two /30 subnets:
#   VM subnet  172.16.{N*4>>8}.{N*4&0xff}/30  — tap0 (host) ↔ eth0 (guest)
#   Veth pair  172.17.{N*4>>8}.{N*4&0xff}/30  — veth-h{N} (host) ↔ veth-n{N} (namespace)

_VM_CIDR = "172.16.0.0/12"

_IPTABLES_RULES = [
    ("nat",    "POSTROUTING", ["-s", _VM_CIDR, "!", "-d", _VM_CIDR, "-j", "MASQUERADE"]),
    ("filter", "FORWARD",     ["-s", _VM_CIDR, "-j", "ACCEPT"]),
    ("filter", "FORWARD",     ["-d", _VM_CIDR, "-j", "ACCEPT"]),
]


def _slot_ips(slot: int) -> tuple[str, str]:
    offset = slot * 4
    return f"172.16.{offset >> 8}.{(offset + 1) & 0xff}", f"172.16.{offset >> 8}.{(offset + 2) & 0xff}"


def _slot_veth_ips(slot: int) -> tuple[str, str]:
    offset = slot * 4
    return f"172.17.{offset >> 8}.{(offset + 1) & 0xff}", f"172.17.{offset >> 8}.{(offset + 2) & 0xff}"


def _ns_name(slot: int) -> str:
    return f"vm{slot}"


def _veth_names(slot: int) -> tuple[str, str]:
    return f"veth-h{slot}", f"veth-n{slot}"


def _ns_up(slot: int) -> tuple[str, str]:
    ns = _ns_name(slot)
    veth_h, veth_n = _veth_names(slot)
    host_ip, guest_ip = _slot_ips(slot)
    veth_h_ip, veth_n_ip = _slot_veth_ips(slot)

    def _r(*cmd):
        subprocess.run(["ip", "netns", "exec", ns, *cmd], check=True, stdout=subprocess.DEVNULL)

    subprocess.run(["ip", "netns", "del", ns], check=False, stderr=subprocess.DEVNULL)
    subprocess.run(["ip", "netns", "add", ns], check=True)

    _r("ip", "tuntap", "add", "dev", "tap0", "mode", "tap", "user", str(_JAILER_UID))
    _r("ip", "addr", "add", f"{host_ip}/30", "dev", "tap0")
    _r("ip", "link", "set", "tap0", "up")
    _r("ip", "link", "set", "lo", "up")
    _r("sysctl", "-w", "net.ipv4.ip_forward=1")

    subprocess.run(["ip", "link", "del", veth_h], check=False, stderr=subprocess.DEVNULL)
    subprocess.run(["ip", "link", "add", veth_h, "type", "veth", "peer", "name", veth_n], check=True)
    subprocess.run(["ip", "link", "set", veth_n, "netns", ns], check=True)
    subprocess.run(["ip", "addr", "add", f"{veth_h_ip}/30", "dev", veth_h], check=True)
    subprocess.run(["ip", "link", "set", veth_h, "up"], check=True)

    _r("ip", "addr", "add", f"{veth_n_ip}/30", "dev", veth_n)
    _r("ip", "link", "set", veth_n, "up")
    _r("ip", "route", "add", "default", "via", veth_h_ip)
    _r("iptables", "-t", "nat", "-A", "POSTROUTING", "-o", veth_n, "-j", "MASQUERADE")

    return host_ip, guest_ip


def _ns_down(slot: int) -> None:
    veth_h, _ = _veth_names(slot)
    subprocess.run(["ip", "link", "del", veth_h], check=False)
    subprocess.run(["ip", "netns", "del", _ns_name(slot)], check=False)


# ── State ─────────────────────────────────────────────────────────────────────

@dataclass
class _VM:
    process: subprocess.Popen
    conn:    socket.socket
    slot:    int
    chroot:  Path
    timer:   threading.Timer | None = None


_warm: dict[str, _VM] = {}
_available_slots: list[int] = list(range(_MAX_SLOTS))
_lock = threading.Lock()


# ── Firecracker API ───────────────────────────────────────────────────────────

def _fc(sock_path: str, method: str, path: str, body: dict | None = None) -> None:
    class _UnixHTTP(http.client.HTTPConnection):
        def connect(self):
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.connect(sock_path)

    conn = _UnixHTTP("localhost")
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    conn.request(method, path, body=data, headers=headers)
    resp = conn.getresponse()
    resp_body = resp.read()
    conn.close()
    if resp.status >= 300:
        raise RuntimeError(f"Firecracker {method} {path} → {resp.status}: {resp_body.decode()}")


def _wait_path(path: str, timeout: float = 15.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.exists(path):
            return
        time.sleep(0.1)
    raise TimeoutError(f"path did not appear: {path}")


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

def _link_or_copy(src: Path, dst: Path) -> None:
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)
    os.chmod(dst, 0o644)


def _prepare_chroot(vm_id: str, lambda_id: str) -> Path:
    chroot = _CHROOT_BASE / "firecracker" / vm_id / "root"
    res = chroot / "resources"
    res.mkdir(parents=True, exist_ok=True)
    (chroot / "run").mkdir(exist_ok=True)
    tmp = chroot / "tmp"
    tmp.mkdir(exist_ok=True)
    os.chmod(tmp, 0o1777)

    _link_or_copy(_ROOTFS, res / "rootfs.ext4")
    _link_or_copy(_STUB, res / "stub.ext4")
    _link_or_copy(_LAMBDAS / f"{lambda_id}.ext4", res / "lambda.ext4")
    _link_or_copy(_SNAP_VMSTATE, res / "vmstate")
    _link_or_copy(_SNAP_MEM, res / "mem.snap")

    for d in (chroot, res, chroot / "run"):
        os.chown(d, _JAILER_UID, _JAILER_GID)

    return chroot


# ── VM lifecycle ──────────────────────────────────────────────────────────────

def _cold_start(lambda_id: str) -> _VM:
    with _lock:
        if not _available_slots:
            raise RuntimeError("no available IP slots")
        slot = _available_slots.pop(0)

    vm_id = str(uuid.uuid4())
    chroot = None
    ns_created = False

    try:
        chroot = _prepare_chroot(vm_id, lambda_id)
        host_ip, guest_ip = _ns_up(slot)
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
                "--netns", f"/var/run/netns/{_ns_name(slot)}",
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

        _wait_path(api_sock)

        _fc(api_sock, "PUT", "/snapshot/load", {
            "snapshot_path": "resources/vmstate",
            "mem_backend": {"backend_path": "resources/mem.snap", "backend_type": "File"},
            "enable_diff_snapshots": False,
            "resume_vm": False,
        })
        _fc(api_sock, "PATCH", "/drives/task", {
            "drive_id": "task", "path_on_host": "resources/lambda.ext4",
        })
        _fc(api_sock, "PATCH", "/vm", {"state": "Resumed"})

        _wait_path(vsock_uds)
        conn = _vsock_connect(vsock_uds)

        result = _call(conn, {
            "type": "setup",
            "task_dev": "/dev/vdc",
            "network": {"guest_ip": guest_ip, "prefix": 30, "gateway": host_ip},
        })
        if result.get("status") != "ok":
            raise RuntimeError(f"runner setup failed: {result}")

        return _VM(process=process, conn=conn, slot=slot, chroot=chroot)

    except Exception:
        if ns_created:
            _ns_down(slot)
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
    _ns_down(vm.slot)
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

def deploy(lambda_id: str, script_dir: str) -> None:
    _LAMBDAS.mkdir(exist_ok=True)
    out = str(_LAMBDAS / f"{lambda_id}.ext4")
    subprocess.run(["truncate", "-s", f"{_LAMBDA_SIZE_MIB}M", out], check=True)
    subprocess.run(["mkfs.ext4", "-q", "-d", script_dir, "-F", out], check=True)
    os.chown(out, _JAILER_UID, _JAILER_GID)
    os.chmod(out, 0o640)


def invoke(lambda_id: str, script: str, input_str: str) -> dict:
    with _lock:
        vm = _warm.get(lambda_id)
        if vm and vm.timer:
            vm.timer.cancel()
            vm.timer = None

    if vm is None:
        vm = _cold_start(lambda_id)
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