#!/usr/bin/python3
from contextlib import contextmanager
import importlib.util
import traceback
import socket
import fcntl
import json
import sys
import io
import os

TCP_PORT = 8080


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


def main() -> None:
    try:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("", TCP_PORT))
        server.listen(1)
        while True:
            conn, _ = server.accept()
            try:
                while True:
                    _send_msg(conn, _handle(_recv_msg(conn)))
            except (ConnectionError, OSError):
                pass
            finally:
                conn.close()
    except Exception as e:
        print(f"Runner error: {e}", flush=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
