# Oblak™

Platform for executing user-provided Python code using Firecracker MicroVMs. Inspired by cloud services such as AWS Lambda and Google Cloud Functions.

## Repository Structure

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
    ├── requirements.txt
    └── vmlib.py                    # Shared Jailer/Firecracker and netns helpers
```

## Setting up Firecracker on Windows with WSL2

Process of setting up Firecracker is automated with `firecracker/setup.ps1` script. To test if MicroVMs are able to run without the orchestrator use `firecracker/test.ps1` script. Run them from the `oblak/` directory in an elevated PowerShell:
```powershell
cd oblak
.\firecracker\setup.ps1
.\firecracker\test.ps1
```
More details alongside instructions for manual setup can be found [here](oblak/firecracker/README.md).

---

## Oblak™ CDK CLI

```
usage: oblak <command> [options]
```

### Commands
 
```
oblak login [-u <username>] [-p <password>]
```
Authenticates with the server. Prompts for credentials if `-u` or `-p` are not provided. Stores a time-limited JWT in `.oblak_credentials` next to the CLI script.
 
```
oblak deploy <file> [files ...] [-r <requirements>] [-n <name>]
```
Deploys a Lambda to the server. `<file>` is the main handler file and must contain a `main` function. Additional files are deployed alongside it. Prints deployment progress from the server and shows assigned `lambda_id` on success. Runs in interactive mode if no arguments are provided.
 
```
oblak invoke <lambda_id> [-i <input>] [-if <input_file>] [-o <output_file>]
```
Invokes a Lambda. `-i` and `-if` are mutually exclusive. Input defaults to an empty string if neither is provided. Output is printed to stdout unless `-o` is specified.
 
```
oblak list
```
Lists all Lambdas belonging to the authenticated user.
 
```
oblak destroy <lambda_id>
``` 
Destroys a Lambda and its associated resources.
 
### Handler contract
 
The handler file must define a `main` function:
 
```python
def main(input: str) -> str:
    ...
```
 
Input and output are plain strings. Input can be parsed as JSON or any other format at the handler's discretion.
 
---

## REST API

All endpoints except `POST /auth/login` and `POST /lambdas/<lambda_id>/invoke` require a JWT in the `Authorization: Bearer <token>` header.

### Authentication

```
POST /auth/login
```

```json
{ "username": "...", "password": "..." }
```

Returns:

```json
{ "token": "...", "expires_at": "2026-01-01T00:00:00Z" }
```

### Deploy a Lambda

```
POST /lambdas
Content-Type: multipart/form-data
```

| Field          | Required | Description                                       |
|----------------|----------|---------------------------------------------------|
| `files`        | yes      | One or more Python scripts, first is the handler. |
| `requirements` | no       | `requirements.txt`                                |
| `name`         | no       | Lambda name, generated if omitted                 |


Returns a chunked response streaming deployment progress, for example:
```json
{"status": "starting code analysis"}
{"status": "checking environment"}
{"status": "building environment"}
{"status": "environment ready"}
{"status": "storing files"}
{"status": "done", "lambda_id": "<uuid>"}
```

### Invoke a Lambda

```
POST /lambdas/<lambda_id>/invoke
```

```json
{ "input": "..." }
```

Returns:

```json
{ "output": "...", "stderr": "...", "exit_code": 0 }
```

### List Lambdas

```
GET /lambdas
```

Returns:

```json
[{ "id": "...", "name": "..." }]
```

### Destroy a Lambda

```
DELETE /lambdas/<lambda_id>
```