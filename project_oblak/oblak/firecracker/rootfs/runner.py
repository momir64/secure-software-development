#!/usr/bin/python3
from contextlib import contextmanager
import importlib.util
import subprocess
import traceback
import socket
import fcntl
import json
import sys
import io
import os

VSOCK_PORT = 8080


def _recv_exact(conn: socket.socket, n: int) -> bytes:
    buf = bytearray()
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("connection closed")
        buf.extend(chunk)
    return bytes(buf)


def _recv_msg(conn: socket.socket) -> dict:
    length = int.from_bytes(_recv_exact(conn, 4), "big")
    return json.loads(_recv_exact(conn, length))


def _send_msg(conn: socket.socket, obj: dict) -> None:
    data = json.dumps(obj).encode()
    conn.sendall(len(data).to_bytes(4, "big") + data)


def _run(*cmd: str) -> int:
    return subprocess.run(list(cmd), capture_output=True, env={"PATH": "/usr/local/bin:/usr/bin:/bin:/sbin"}).returncode


def _load_module(script: str):
    path = f"/var/task/{script}"
    if "/var/task" not in sys.path:
        sys.path.insert(0, "/var/task")
    spec = importlib.util.spec_from_file_location("user_module", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {path!r}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@contextmanager
def _capture_stderr():
    buf = io.StringIO()
    r, w = os.pipe()
    flags = fcntl.fcntl(w, fcntl.F_GETFL)
    fcntl.fcntl(w, fcntl.F_SETFL, flags | os.O_NONBLOCK)
    old = os.dup(2)
    os.dup2(w, 2)
    os.close(w)
    try:
        yield buf
    finally:
        os.dup2(old, 2)
        os.close(old)
        buf.write(os.read(r, 65536).decode(errors="replace"))
        os.close(r)


def _handle_setup(payload: dict) -> dict:
    errors = []
    env_dev = payload.get("env_dev", "")
    if env_dev and _run("mount", "-t", "ext4", "-o", "ro", env_dev, "/env") != 0:
        errors.append(f"failed to mount env {env_dev}")
    elif env_dev:
        sys.path.insert(0, "/env")
    task_dev = payload.get("task_dev", "")
    if task_dev and _run("mount", "-t", "ext4", "-o", "ro", task_dev, "/var/task") != 0:
        errors.append(f"failed to mount task {task_dev}")
    net = payload.get("network")
    if net:
        _run("ip", "addr", "flush", "dev", "eth0")
        _run("ip", "route", "flush", "dev", "eth0")
        _run("ip", "addr", "add", f"{net['guest_ip']}/{net['prefix']}", "dev", "eth0")
        _run("ip", "link", "set", "eth0", "up")
        _run("ip", "route", "add", "default", "via", net['gateway'])
    if errors:
        return {"status": "error", "errors": errors}
    return {"status": "ok"}


def _handle(payload: dict) -> dict:
    script = payload.get("script", "")
    input_str = payload.get("input", "")
    output = ""
    exit_code = 0

    with _capture_stderr() as stderr_buf:
        try:
            os.chdir("/tmp")
            mod = _load_module(script)
            if not hasattr(mod, "main"):
                raise AttributeError(f"no 'main' function in {script!r}")
            output = str(mod.main(input_str))
        except KeyboardInterrupt:
            raise
        except BaseException:
            exit_code = 1
            stderr_buf.write(traceback.format_exc())

    return {"output": output, "stderr": stderr_buf.getvalue(), "exit_code": exit_code}


def _setup_mounts() -> None:
    if _run("mount", "-t", "tmpfs", "tmpfs", "/tmp") != 0:
        print("Failed to mount tmpfs at /tmp", flush=True)
        sys.exit(1)
    _run("mount", "-t", "proc", "proc", "/proc")


def main() -> None:
    _setup_mounts()
    try:
        server = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((socket.VMADDR_CID_ANY, VSOCK_PORT))
        server.listen(1)
        while True:
            conn, _ = server.accept()
            try:
                while True:
                    msg = _recv_msg(conn)
                    if msg.get("type") == "setup":
                        _send_msg(conn, _handle_setup(msg))
                    else:
                        _send_msg(conn, _handle(msg))
            except (ConnectionError, OSError):
                pass
            finally:
                conn.close()
    except Exception as e:
        print(f"Runner error: {e}", flush=True)
        sys.exit(1)


if __name__ == "__main__":
    main()