from pathlib import Path
import http.client
import subprocess
import shutil
import socket
import json
import time
import os


def jailer_ids() -> tuple[int, int]:
    uid = int(subprocess.check_output(["id", "-u", "firecracker-jailer"]).strip())
    gid = int(subprocess.check_output(["id", "-g", "firecracker-jailer"]).strip())
    return uid, gid


def fc(sock_path: str, method: str, path: str, body: dict | None = None) -> None:
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


def wait_path(path: str, timeout: float = 15.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.exists(path):
            return
        time.sleep(0.1)
    raise TimeoutError(f"path did not appear: {path}")


def link_or_copy(src: Path, dst: Path) -> None:
    if not src.exists():
        raise FileNotFoundError(f"source does not exist: {src}")
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)
    os.chmod(dst, 0o644)


def slot_ips(prefix: str, slot: int) -> tuple[str, str]:
    offset = slot * 4
    return f"{prefix}.{offset >> 8}.{(offset + 1) & 0xff}", f"{prefix}.{offset >> 8}.{(offset + 2) & 0xff}"


def slot_name(slot: int, env_builder: bool = False) -> str:
    env_prefix = 'envb' if env_builder else 'vm'
    return f"{env_prefix}{slot}"


def veth_names(slot: int, env_builder: bool = False) -> tuple[str, str]:
    env_infix = 'e' if env_builder else ''
    return f"veth-{env_infix}h{slot}", f"veth-{env_infix}n{slot}"


def netns_up(ns: str, veth_h: str, veth_n: str, host_ip: str, guest_ip: str,
             veth_h_ip: str, veth_n_ip: str, jailer_uid: int) -> None:
    def _r(*cmd):
        subprocess.run(["ip", "netns", "exec", ns, *cmd], check=True, stdout=subprocess.DEVNULL)

    subprocess.run(["ip", "netns", "del", ns], check=False, stderr=subprocess.DEVNULL)
    subprocess.run(["ip", "netns", "add", ns], check=True)

    _r("ip", "tuntap", "add", "dev", "tap0", "mode", "tap", "user", str(jailer_uid))
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


def slot_up(veth_h: str, veth_n: str, vm_prefix: str, veth_prefix: str,
            slot: int, jailer_uid: int, env_builder: bool = False) -> tuple[str, str]:
    ns = slot_name(slot, env_builder)
    host_ip, guest_ip = slot_ips(vm_prefix, slot)
    veth_h_ip, veth_n_ip = slot_ips(veth_prefix, slot)
    netns_up(ns, veth_h, veth_n, host_ip, guest_ip, veth_h_ip, veth_n_ip, jailer_uid)
    return host_ip, guest_ip


def netns_down(slot: int, env_builder: bool = False) -> None:
    veth_h, _ = veth_names(slot, env_builder)
    subprocess.run(["ip", "link", "del", veth_h], check=False)
    subprocess.run(["ip", "netns", "del", slot_name(slot, env_builder)], check=False)
