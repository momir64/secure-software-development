from pathlib import Path
import subprocess
import hashlib
import tomllib
import socket
import time
import uuid
import os

# ── Paths ─────────────────────────────────────────────────────────────────────

_BASE = Path(__file__).parent
_RESOURCES = _BASE / "resources"
_ROOTFS = _RESOURCES / "rootfs.ext4"
_ENVS = _BASE / "envs"
_LAMBDAS = _BASE / "lambdas"

# ── Config ────────────────────────────────────────────────────────────────────

with open(_BASE / "config" / "vm.toml", "rb") as _f:
    _cfg = tomllib.load(_f)

_MEM = _cfg["vm"]["env_memory_mib"]
_VCPU = _cfg["vm"]["env_vcpu_count"]
_LAMBDA_SIZE_MIB = _cfg["vm"]["lambda_size_mib"]
_ENV_SIZE_MIB = _cfg["vm"].get("env_size_mib", 256)
_ENV_BUILD_TIMEOUT = _cfg["vm"].get("env_build_timeout_seconds", 600)

_JAILER_UID = int(subprocess.check_output(["id", "-u", "firecracker-jailer"]).strip())
_JAILER_GID = int(subprocess.check_output(["id", "-g", "firecracker-jailer"]).strip())


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


def _fc(sock_path: str, method: str, path: str, body: dict | None = None) -> None:
    import http.client, json

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


def _wait_sock(path: str, timeout: float = 15.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.exists(path):
            return
        time.sleep(0.1)
    raise TimeoutError(f"socket did not appear: {path}")


def _make_ext4(path: Path, size_mib: int, src_dir: Path | None = None, extra_opts: list[str] | None = None, capture_output: bool = False) -> None:
    subprocess.run(["truncate", "-s", f"{size_mib}M", str(path)], check=True)
    cmd = ["mkfs.ext4", "-q", *(extra_opts or []), *(["-d", str(src_dir)] if src_dir else []), "-F", str(path)]
    subprocess.run(cmd, check=True, capture_output=capture_output)


def _configure_fc_vm(fc_sock: str, req_image: Path, out_image: Path, tap: str) -> None:
    _fc(fc_sock, "PUT", "/machine-config", {
        "vcpu_count": _VCPU,
        "mem_size_mib": _MEM,
    })
    _fc(fc_sock, "PUT", "/boot-source", {
        "kernel_image_path": str(_RESOURCES / "vmlinux"),
        "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/var/runtime/env_builder.sh",
    })
    _fc(fc_sock, "PUT", "/drives/rootfs", {
        "drive_id": "rootfs",
        "path_on_host": str(_ROOTFS),
        "is_root_device": True,
        "is_read_only": True,
    })
    _fc(fc_sock, "PUT", "/drives/req", {
        "drive_id": "req",
        "path_on_host": str(req_image),
        "is_root_device": False,
        "is_read_only": True,
    })
    _fc(fc_sock, "PUT", "/drives/env", {
        "drive_id": "env",
        "path_on_host": str(out_image),
        "is_root_device": False,
        "is_read_only": False,
    })
    _fc(fc_sock, "PUT", "/network-interfaces/eth0", {
        "iface_id": "eth0",
        "host_dev_name": tap,
        "guest_mac": "AA:FC:00:00:00:02",
    })
    _fc(fc_sock, "PUT", "/actions", {"action_type": "InstanceStart"})


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

    work_dir = _ENVS / f".build-{uuid.uuid4().hex}"
    work_dir.mkdir()

    req_image = work_dir / "req.ext4"
    out_image = work_dir / "env.ext4"
    fc_sock = Path(f"/tmp/oblak-fc-{uuid.uuid4().hex}.sock")
    req_dir = work_dir / "req"
    req_dir.mkdir()

    process = None
    tap = f"tenv{uuid.uuid4().hex[:7]}"

    try:
        (req_dir / "requirements.txt").write_text(requirements)
        _make_ext4(req_image, 4, src_dir=req_dir, extra_opts=["-O", "^has_journal"])
        _make_ext4(out_image, _ENV_SIZE_MIB)

        subprocess.run(["ip", "tuntap", "add", "dev", tap, "mode", "tap"], check=True)
        subprocess.run(["ip", "addr", "add", "172.18.0.1/30", "dev", tap], check=True)
        subprocess.run(["ip", "link", "set", tap, "up"], check=True)
        subprocess.run(["iptables", "-t", "nat", "-I", "POSTROUTING", "-o", "eth0", "-j", "MASQUERADE"], check=True)

        with open(work_dir / "fc.log", "w") as log_fh:
            process = subprocess.Popen(
                ["firecracker", "--api-sock", str(fc_sock)],
                stdout=log_fh,
                stderr=log_fh,
            )

        _wait_sock(str(fc_sock))
        _configure_fc_vm(str(fc_sock), req_image, out_image, tap)
        _wait_exit(process.pid)
        process = None

        result = subprocess.run(["debugfs", "-R", "ls /", str(out_image)], capture_output=True, text=True)
        if ".__build_ok__" not in result.stdout:
            log_contents = (work_dir / "fc.log").read_text() if (work_dir / "fc.log").exists() else "no log"
            raise RuntimeError(f"env build failed: pip install failed\n{log_contents}")

        out_image.rename(env_image)
        return hash_

    finally:
        if process is not None:
            process.kill()
            process.wait()
        subprocess.run(["iptables", "-t", "nat", "-D", "POSTROUTING", "-o", "eth0", "-j", "MASQUERADE"], check=False)
        subprocess.run(["ip", "link", "del", tap], check=False)
        fc_sock.unlink(missing_ok=True)
        subprocess.run(["rm", "-rf", str(work_dir)], check=False)