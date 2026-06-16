# Oblak — Architecture & Implementation Guide

This document contains all context needed to implement the runner, orchestrator, and CDK CLI.
The project assignment PDF describes the high-level goals. The Firecracker setup README
(`oblak/firecracker/README.md`) and setup scripts (`setup.ps1`, `test.ps1`) handle
infrastructure setup and are already complete — do not reimplement them.

---

## Project Structure

```
├── cdk-cli/                        # Command-line client
│   ├── oblak.py                    # CDK CLI script
│   ├── oblak.cmd                   # Entry point wrapper (oblak <command>)
│   └── requirements.txt
└── oblak/                          # Server and orchestrator
    ├── firecracker/
    │   ├── rootfs/
    │   │   ├── Dockerfile          # Builds rootfs.ext4
    │   │   ├── env_builder.sh      # Baked into rootfs; runs as PID 1 in env-builder VMs
    │   │   └── runner.py           # Baked into rootfs; trusted runtime
    │   ├── README.md               # Firecracker setup instructions
    │   ├── setup.ps1               # Automated Firecracker setup (Windows)
    │   ├── setup.sh                # Automated Firecracker setup (Linux)
    │   ├── snapshot.ps1            # Take base VM snapshot (Windows)
    │   ├── snapshot.sh             # Take base VM snapshot (Linux)
    │   ├── test.ps1                # Test MicroVM boot (Windows)
    │   └── test.sh                 # Test MicroVM boot (Linux)
    ├── resources/
    │   ├── rootfs.ext4             # Base rootfs image
    │   ├── stub.ext4               # Stub drive image used in base snapshot
    │   ├── vmlinux                 # Firecracker CI kernel
    │   └── snapshot/
    │       ├── mem.snap            # Frozen VM memory state
    │       └── vmstate             # Firecracker VM state
    ├── envs/
    │   └── env_<hash>.ext4         # Per-requirements dependency layers
    ├── lambdas/
    │   └── <lambda_id>.ext4        # Deployed user scripts
    ├── config/
    │   ├── init.sql                # DB schema and seed data
    │   └── vm.toml                 # VM resource configuration
    ├── web_client/                 # Static frontend served by Sanic
    │   ├── index.html
    │   ├── script.js
    │   └── styles.css
    ├── analyzer.py                 # Code safety analysis
    ├── deployer.py                 # Lambda deployment and environment building
    ├── docker-compose.yml
    ├── main.py                     # Oblak entry point
    ├── orchestrator.py             # Orchestrator of MicroVMs lifecycle
    └── requirements.txt
```

---

## VM Configuration (`config/vm.toml`)

```toml
[vm]
vcpu_count = 1
memory_mib = 128
max_ip_slots = 128              # maximum number of concurrently running VMs
lambda_size_mib = 10            # size of each lambda ext4 image
env_size_mib = 256              # size of each env ext4 image
idle_timeout_seconds = 300      # time since last invoke before VM is destroyed
handler_timeout_seconds = 30    # max time main() can run before VM is killed
cpu_period_us = 100000          # cgroup cpu.max period
cpu_quota_us = 100000           # cgroup cpu.max quota (quota/period = max CPU fraction)

[rootfs]
disk_size_mib = 512
```

---

## Base Image (`firecracker/rootfs/Dockerfile`)

The Dockerfile already exists and produces `resources/rootfs.ext4`. It includes
the runner and env builder with the correct directory structure.

**Filesystem layout inside the image:**

```
/
├── usr/
│   ├── bin/python3
│   └── lib/python3/
├── var/
│   ├── runtime/
│   │   ├── runner.py       # baked in, trusted, read-only
│   │   └── env_builder.sh  # baked in, used as PID 1 in env-builder VMs
│   └── task/               # empty dir, mounted from task drive at cold start
├── env/                    # empty dir, mounted from env drive at cold start
├── proc/
├── dev/
└── tmp/                    # writable, user working directory
```

**Dockerfile:**

```dockerfile
FROM alpine:3.19

RUN apk add --no-cache python3 curl iproute2

RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

RUN mkdir -p /var/runtime /var/task /env

COPY runner.py /var/runtime/runner.py
RUN sed -i 's/\r$//' /var/runtime/runner.py && chmod 544 /var/runtime/runner.py

COPY env_builder.sh /var/runtime/env_builder.sh
RUN sed -i 's/\r$//' /var/runtime/env_builder.sh && chmod 544 /var/runtime/env_builder.sh
```

The base snapshot is taken with three drives:
- `rootfs` = `rootfs.ext4` mounted read-only as `/`
- `env` = `stub.ext4` attached as `/dev/vdb`, not mounted
- `task` = `stub.ext4` attached as `/dev/vdc`, not mounted

At cold start the orchestrator substitutes the stub drives with the lambda's actual images
before resuming the VM. The runner mounts them in response to the setup message.

---

## Base Snapshot

After building the base image, a memory snapshot must be taken:

1. Boot a VM with `rootfs.ext4` (read-only) and two stub drives (`stub.ext4` for both
   `/dev/vdb` and `/dev/vdc`) attached but not mounted, passing `init=/var/runtime/runner.py`
   as the kernel boot arg so the runner starts directly as PID 1
2. Runner mounts tmpfs at `/tmp` and proc at `/proc` on startup, then listens on vsock port 8080
3. Wait for the runner to be ready (vsock port 8080 accepts connections via the vsock UDS)
4. Call Firecracker's snapshot API to freeze the VM
5. Store result in `resources/snapshot/mem.snap` and `resources/snapshot/vmstate`

Every cold start restores from this snapshot and substitutes the stub drives: `task` with
`lambda.ext4` (the lambda's script image, copied into the chroot), and `env` with
`env_<hash>.ext4` if the lambda has requirements. The snapshot must be retaken whenever
`rootfs.ext4` changes.

---

## Lambda Contract

User scripts must define a `main` function with this exact signature:

```python
def main(input: str) -> str:
    ...
    return "result"
```

- Input is always a string (user may parse it as JSON or any format they choose)
- Output must be a string (serialized however the user prefers)
- The script filename is not enforced — only the function name `main` is required
- Relative file paths inside the handler resolve to `/tmp` (runner sets cwd to `/tmp`)
- `/tmp` persists across warm invocations of the same lambda
- `/tmp` is destroyed when the VM is destroyed (idle timeout or explicit destroy)

---

## Runner (`/var/runtime/runner.py`)

The runner is a trusted Python script baked into the base image. It starts on VM boot
and handles invocations over vsock. It is intentionally simple — security and timeout
enforcement are handled by the orchestrator and the VM boundary, not the runner.

**Responsibilities:**
1. Mount tmpfs at `/tmp` and proc at `/proc`
2. Open vsock server on port 8080 (bound to `VMADDR_CID_ANY`)
3. Accept connection from orchestrator
4. Read message (JSON), dispatch by `type` field
5. On `type: setup`: mount drives and configure network, send `{"status": "ok"}`
6. On invoke: set `os.cwd('/tmp')`, dynamically import `/var/task/<script_filename>`,
   call `mod.main(input_string)`, send result payload
7. Loop back to step 3 for next invocation

**Setup payload (orchestrator → runner, cold start only):**
```json
{
    "type": "setup",
    "env_dev": "/dev/vdb",
    "task_dev": "/dev/vdc",
    "network": {
        "guest_ip": "172.16.x.y",
        "prefix": 30,
        "gateway": "172.16.x.z"
    }
}
```

`env_dev` is optional (omit if no requirements). `network` is always sent to reconfigure
eth0 away from the snapshot's baked-in IP.

**Invocation payload (orchestrator → runner):**
```json
{
    "script": "handler.py",
    "input": "some string input"
}
```

**Result payload (runner → orchestrator):**
```json
{
    "output": "return value of main()",
    "stderr": "any stderr output",
    "exit_code": 0
}
```

**Error handling:**
- If `main()` raises an exception, send `exit_code: 1` and the traceback in `stderr`
- If the script file is missing or has no `main`, send `exit_code: 1` and a clear error message

**Timeout:** The runner does NOT enforce timeouts. The orchestrator kills the VM if
`handler_timeout_seconds` is exceeded. The runner is unaware of timeouts entirely.

**Note on security:** User code runs in the same process as the runner. The VM
boundary (enforced by Jailer + KVM) is the primary isolation mechanism. The runner
only needs to be protected from user code tampering with its vsock server — this is
achieved by the read-only filesystem (user code cannot modify `runner.py`) and the
fact that the runner holds the server socket file descriptor privately.

---

## Environment Layer Builder (`deployer.py`)

Creates `env_<hash>.ext4` for a given `requirements.txt`. Exposed as `ensure_env(requirements) -> str | None` — returns the hash, or `None` if requirements is empty.

**Process:**
1. Sort `requirements.txt` lines, compute SHA256 → `<hash>` (first 16 hex chars)
2. Check if `envs/env_<hash>.ext4` already exists — if yes, return hash immediately
3. Create a temp work directory under `envs/.build-<uuid>/`
4. Package `requirements.txt` into `req.ext4` (4 MiB, no journal, `-O ^has_journal`) with `mkfs.ext4 -d`
5. Create a blank `out.ext4` of `env_size_mib`
6. Set up a TAP interface on the host (`tenv<random>`): assign `172.18.0.1/30`, bring it up, add an iptables MASQUERADE rule on `eth0`
7. Start a Firecracker VM (no jailer, no namespace) with:
   - drive `rootfs` — `rootfs.ext4`, root, read-only
   - drive `req` — `req.ext4`, `/dev/vdb`, read-only
   - drive `env` — `out.ext4`, `/dev/vdc`, read-write
   - network interface on the tap above
   - boot arg `init=/var/runtime/env_builder.sh`
8. `env_builder.sh` runs as PID 1 inside the VM:
   - Mounts `/dev/vdb` → `/var/task` (read-only)
   - Mounts `/dev/vdc` → `/env` (read-write)
   - Configures `eth0` to `172.18.0.2/30`, default route via `172.18.0.1`
   - Runs `uv pip install --no-cache --system --target /env -r /var/task/requirements.txt`
   - Unmounts `/env`, then calls `reboot -f`
9. Wait for the Firecracker process to exit (up to `env_build_timeout_seconds`, default 600 s)
10. Rename `out.ext4` → `envs/env_<hash>.ext4`
11. Cleanup: remove iptables rule, delete tap, remove work directory

`deploy_lambda(lambda_id, script_dir)` packages a script directory into `lambdas/<lambda_id>.ext4` using `mkfs.ext4 -d` and sets ownership to the jailer uid/gid.

---

## VM Lifecycle

### Cold Start
1. Allocate an IP slot, create a network namespace `vm{N}` with a `tap0` inside it and a
   veth pair (`veth-h{N}` / `veth-n{N}`) connecting the namespace to the host
2. Prepare a per-VM chroot under `/srv/jailer/firecracker/<vm_id>/root/`, hard-linking
   `rootfs.ext4`, `stub.ext4`, the snapshot files, the lambda image (as `lambda.ext4`),
   and (if the lambda has requirements) the env image (as `env.ext4`) into `resources/`
3. Start Jailer with `--netns /var/run/netns/vm{N}` so Firecracker runs inside the namespace
4. Load snapshot via Firecracker API (`/snapshot/load`), patch `task` drive to
   `resources/lambda.ext4` and (if the lambda has requirements) patch `env` drive to
   `resources/env.ext4`, then resume VM (`PATCH /vm {"state": "Resumed"}`)
5. Connect to runner via vsock UDS (`tmp/v.sock` inside the chroot)
6. Send setup message: mount task drive (and env drive if present), configure eth0 to slot's guest IP
7. Send invocation payload, receive result
8. Start idle timer (`idle_timeout_seconds`)
9. Mark VM as warm for this `lambda_id`

### Warm Start
1. Find warm VM for `lambda_id`
2. Reset idle timer
3. Send invocation payload over vsock
4. Receive result
5. `/tmp` contents from previous invocations are still present

### Idle Timeout
1. Timer expires since last invocation
2. Kill VM process, close vsock connection
3. Tear down network namespace and veth pair
4. Delete chroot directory
5. Free IP slot
6. `rootfs.ext4` and `env_<hash>.ext4` remain untouched; `<lambda_id>.ext4` remains on disk
7. Remove VM from warm instances tracker

### Handler Timeout
1. Orchestrator sends invocation and starts `handler_timeout_seconds` timer
2. If no response received before timer expires: kill VM process, return timeout error
3. VM is fully destroyed (same as idle timeout)

### VM Networking

Each VM gets a dedicated network namespace (`vm{N}`) containing:
- `tap0` — TAP device Firecracker connects the guest's `eth0` to; has the host-side IP of the /30 subnet
- `lo` — loopback, brought up
- `veth-n{N}` — one end of a veth pair moved into the namespace; has the namespace-side IP of a second /30 subnet; default route via `veth-h{N}`
- NAT masquerade rule inside the namespace on `veth-n{N}` for outbound traffic

On the host side, `veth-h{N}` holds the host-side IP of the second /30 subnet.

IP allocation uses two /30 subnets per slot `N`:
- VM subnet: `172.16.{N*4>>8}.{(N*4)&0xff}/30` — tap0 (host-side) ↔ eth0 (guest)
- Veth subnet: `172.17.{N*4>>8}.{(N*4)&0xff}/30` — veth-h{N} (host) ↔ veth-n{N} (namespace)

Global iptables rules (installed once at startup, removed at shutdown):
- `nat POSTROUTING`: masquerade all traffic from `172.16.0.0/12` not destined for `172.16.0.0/12`
- `filter FORWARD`: accept traffic from and to `172.16.0.0/12`

IP forwarding is enabled on orchestrator startup (`net.ipv4.ip_forward=1`).

---

## Orchestrator (`oblak/orchestrator.py`)

Python module that manages VM lifecycle and exposes a public API consumed by the HTTP server.

### In-memory State
```python
_warm: dict[str, _VM]           # lambda_id -> running VM
_available_slots: list[int]     # available slot indices for namespace/IP allocation
_lock: threading.Lock

# _VM dataclass fields: process, conn, slot, chroot, timer
```

### Public Functions
- `startup()` — enable IP forwarding, install global iptables rules
- `shutdown()` — destroy all warm VMs, remove iptables rules
- `invoke(lambda_id, script, input_str, env_hash=None) -> dict` — cold or warm start, returns result payload
- `destroy(lambda_id)` — destroy warm VM if running (does not delete files)

### Startup
1. Read `config/vm.toml`
2. Enable IP forwarding
3. Install global iptables rules

### Shutdown
1. Kill all warm VMs
2. Tear down all network namespaces and veth pairs
3. Remove global iptables rules

---

## Database Schema (Postgres)

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE lambdas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    script_filename TEXT NOT NULL,
    env_hash TEXT,
    deleted_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    lambda_id UUID REFERENCES lambdas(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    ip_address TEXT NOT NULL,
    detail JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);
```

Lambda files live on disk at `lambdas/<lambda_id>.ext4`. The `script_filename` column
identifies which file contains the `main` handler. `env_hash` is nullable (null when the lambda
has no requirements). Deletes are soft — `deleted_at` is set rather than removing the row or files.
Timeouts are global and read from `vm.toml`.

---

## Server API

All endpoints except `/auth/login` and `POST /lambdas/<lambda_id>/invoke` require a valid JWT in the `Authorization: Bearer <token>` header.

```
POST   /auth/login
       Body: {"username": "...", "password": "..."}
       Returns: {"token": "<jwt>", "expires_at": "<iso timestamp>"}

POST   /lambdas
       Body: multipart/form-data
         - files: one or more script files
         - requirements: requirements.txt (optional)
         - name: lambda name (optional, generated if absent)
       Returns: chunked response streaming deployment progress, ends with:
         {"status": "done", "lambda_id": "<uuid>"}

DELETE /lambdas/<lambda_id>
       Verifies ownership. Destroys warm VM if running, soft-deletes DB record (sets deleted_at). Lambda files remain on disk.

GET    /lambdas
       Returns list of caller's lambdas: [{"id": "...", "name": "..."}]

POST   /lambdas/<lambda_id>/invoke
       Body: {"input": "..."}
       Returns: {"output": "...", "stderr": "...", "exit_code": 0}
```

### Deployment Progress (chunked response)
The `POST /lambdas` endpoint streams newline-delimited JSON status messages:
```json
{"status": "starting code analysis"}
{"status": "checking environment"}
{"status": "building environment"}
{"status": "environment ready"}
{"status": "storing files"}
{"status": "done", "lambda_id": "<uuid>"}
```

---

## CDK CLI (`cdk-cli/`)

Python package installable via pip. Exposes an `oblak` console entry point.

Credentials stored in `.oblak_credentials` (JSON) at the same directory as the CLI script:
```json
{
    "token": "<jwt>",
    "expires_at": "<iso timestamp>"
}
```

### `oblak login`
- Prompts for username and password interactively
- Flags: `-u <username>`, `-p <password>` skip prompts
- Stores JWT in `.oblak_credentials`

### `oblak deploy <file> [files...] [-r <requirements>] [-n <name>]`
- First positional arg is the main handler file (must contain `main` function)
- Additional positional args are helper files placed in `/var/task/` alongside the handler
- `-r` path to `requirements.txt`
- `-n` lambda name (generated if omitted)
- No args → interactive mode (Enter to skip optional fields)
- Streams and prints deployment progress from server
- Prints `lambda_id` on completion

### `oblak destroy <lambda_id>`
- Sends DELETE request, prints confirmation

### `oblak list`
- Prints table of lambda names and IDs for logged-in user

### `oblak invoke [lambda_id] [-i <input>] [-if <input_file>] [-o <output_file>]`
- `-i` and `-if` are mutually exclusive (error if both provided)
- Input defaults to empty string if neither provided
- Output printed to stdout unless `-o` specified

---

## TODO: Implementation Order

1. **Orchestrator core** — snapshot restore with drive substitution, vsock communication, warm/cold lifecycle, network namespace management ✓
2. **Environment builder** — `env_<hash>.ext4` creation from `requirements.txt` ✓
3. **Server API** — Sanic endpoints, JWT auth, Postgres integration ✓
4. **CDK CLI** — all five commands ✓