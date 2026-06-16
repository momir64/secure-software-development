#!/usr/bin/env python3
from contextlib import ExitStack
from pathlib import Path
import argparse
import requests
import getpass
import json
import sys

_SERVER   = "https://oblak.moma.rs"
_CRED_FILE = Path(__file__).parent / ".oblak_credentials"


def _load_creds() -> dict:
    if not _CRED_FILE.exists():
        print("Not logged in. Run: oblak login")
        sys.exit(1)
    return json.loads(_CRED_FILE.read_text())


def _url(path: str) -> str:
    return _SERVER + path


def _headers(creds: dict) -> dict:
    return {"Authorization": f"Bearer {creds['token']}"}


def _req(method: str, url: str, **kwargs) -> requests.Response:
    resp = requests.request(method, url, **kwargs)
    if resp.status_code != 200:
        try:
            error = resp.json().get("error", resp.text)
        except Exception:
            error = resp.text
        print(f"Error: {error}")
        sys.exit(1)
    return resp


# ── Commands ──────────────────────────────────────────────────────────────────

def cmd_login(args):
    username = args.u or input("Username: ").strip()
    password = args.p or getpass.getpass("Password: ")

    data = _req("POST", _url("/auth/login"),
                json={"username": username, "password": password}).json()
    _CRED_FILE.write_text(json.dumps({"token": data["token"], "expires_at": data["expires_at"]}, indent=2))
    print(f"Logged in. Token expires at {data['expires_at']}")


def cmd_deploy(args):
    creds = _load_creds()

    if not args.files:
        handler = input("Handler file: ").strip()
        extra = []
        while True:
            f = input("Additional file (or Enter to skip/finish): ").strip()
            if not f: break
            extra.append(f)
        req_path = input("Requirements file (or Enter to skip): ").strip() or None
        lambda_name = input("Lambda name (or Enter to auto-generate): ").strip() or None
        file_paths = [handler] + extra
    else:
        file_paths, req_path, lambda_name = args.files, args.r, args.n

    with ExitStack() as stack:
        file_parts: list[tuple] = [("files", (Path(p).name, stack.enter_context(open(p, "rb")), "text/x-python")) for p in file_paths]
        if req_path:
            file_parts.append(("requirements", (Path(req_path).name, stack.enter_context(open(req_path, "rb")), "text/plain")))
        resp = requests.post(
            _url("/lambdas"),
            files=file_parts,
            data={"name": lambda_name} if lambda_name else {},
            headers=_headers(creds),
            stream=True
        )

    if resp.status_code != 200:
        print(f"Error: {resp.text}")
        sys.exit(1)

    lambda_id = None
    for line in resp.iter_lines():
        if not line: continue
        msg = json.loads(line)
        status = msg.get("status", "")
        print(f"  {status}")
        if status == "done":
            lambda_id = msg.get("lambda_id")
        elif status == "error":
            print(f"  Error: {msg.get('message', '')}")
            sys.exit(1)

    if lambda_id:
        print(f"\nLambda deployed: {lambda_id}")
        print(f"URL: {_SERVER}/invoke/{lambda_id}")


def cmd_invoke(args):
    lambda_id = args.lambda_id or input("Lambda ID: ").strip()

    if args.i and args.input_file:
        print("Error: -i and -if are mutually exclusive")
        sys.exit(1)

    input_str = Path(args.input_file).read_text() if args.input_file else (args.i or "")

    resp = requests.post(_url(f"/lambdas/{lambda_id}/invoke"), json={"input": input_str})
    if resp.status_code != 200:
        try:
            error = resp.json().get("error", resp.text)
        except Exception:
            error = resp.text
        print(f"Error: {error}")
        sys.exit(1)
    result = resp.json()

    output = result.get("output", "")
    if args.o:
        Path(args.o).write_text(output)
    else:
        print(output, end="" if output.endswith("\n") else "\n")

    if result.get("stderr"):
        print(f"[stderr]\n{result['stderr']}", file=sys.stderr)

    if result.get("exit_code", 0) != 0:
        sys.exit(result["exit_code"])


def cmd_list(args):
    creds = _load_creds()
    lambdas = _req("GET", _url("/lambdas"), headers=_headers(creds)).json()
    if not lambdas:
        print("No lambdas deployed.")
        return
    name_w = max(len(lam["name"]) for lam in lambdas)
    print(f"{'NAME':<{name_w}}  ID")
    print(f"{'-' * name_w}  {'-' * 36}")
    for lam in lambdas:
        print(f"{lam['name']:<{name_w}}  {lam['id']}")


def cmd_destroy(args):
    creds = _load_creds()
    _req("DELETE", _url(f"/lambdas/{args.lambda_id}"), headers=_headers(creds))
    print(f"Lambda {args.lambda_id} destroyed.")


# ── Arg parsing ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(prog="oblak")
    sub = parser.add_subparsers(dest="command")

    login_p = sub.add_parser("login")
    login_p.add_argument("-u", metavar="username")
    login_p.add_argument("-p", metavar="password")

    deploy_p = sub.add_parser("deploy")
    deploy_p.add_argument("files", nargs="*", metavar="file")
    deploy_p.add_argument("-r", metavar="requirements")
    deploy_p.add_argument("-n", metavar="name")

    invoke_p = sub.add_parser("invoke")
    invoke_p.add_argument("lambda_id", nargs="?")
    invoke_p.add_argument("-i", metavar="input")
    invoke_p.add_argument("-if", dest="input_file", metavar="input_file")
    invoke_p.add_argument("-o", metavar="output_file")

    sub.add_parser("list")

    destroy_p = sub.add_parser("destroy")
    destroy_p.add_argument("lambda_id")

    args = parser.parse_args()
    commands = {"login": cmd_login, "deploy": cmd_deploy, "invoke": cmd_invoke, "list": cmd_list, "destroy": cmd_destroy}

    if args.command not in commands:
        parser.print_help()
        sys.exit(1)

    commands[args.command](args)


if __name__ == "__main__":
    main()