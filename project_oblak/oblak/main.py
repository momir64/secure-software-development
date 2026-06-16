from sanic.exceptions import NotFound, MethodNotAllowed, SanicException
from datetime import datetime, timezone, timedelta
from sanic.response import json as json_resp
from sanic import Sanic, Request
from dotenv import load_dotenv
from analyzer import analyze
from functools import wraps
from pathlib import Path
import orchestrator
import deployer
import tempfile
import asyncio
import asyncpg
import bcrypt
import sanic
import json
import uuid
import jwt
import os

load_dotenv(dotenv_path=Path(__file__).parent / ".env")

# ── Config ────────────────────────────────────────────────────────────────────

_BASE = Path(__file__).parent
_PORT = int(os.environ.get("PORT", "8000"))
_JWT_EXPIRES_HOURS = int(os.environ.get("JWT_EXPIRES_HOURS", "24"))
_JWT_SECRET = os.environ["JWT_SECRET"]
_DB_DSN = os.environ["DATABASE_URL"]

app = Sanic("oblak")
app.static("/", _BASE / "web_client", index="index.html")
app.config.RESPONSE_TIMEOUT = 600
app.config.REQUEST_TIMEOUT = 600

# ── DB / lifecycle ────────────────────────────────────────────────────────────

@app.before_server_start
async def on_startup(sanic_app):
    sanic_app.ctx.db = await asyncpg.create_pool(_DB_DSN)
    orchestrator.startup()


@app.after_server_stop
async def on_shutdown(sanic_app):
    orchestrator.shutdown()
    await sanic_app.ctx.db.close()


# ── Auth helpers ──────────────────────────────────────────────────────────────

def _make_token(user_id: str) -> tuple[str, str]:
    expires_at = datetime.now(timezone.utc) + timedelta(hours=_JWT_EXPIRES_HOURS)
    token = jwt.encode({"sub": user_id, "exp": expires_at}, _JWT_SECRET, algorithm="HS256")
    return token, expires_at.isoformat()


def authenticated(func):
    @wraps(func)
    async def wrapper(request: Request, *args, **kwargs):
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return json_resp({"error": "missing or malformed Authorization header"}, status=401)
        try:
            payload = jwt.decode(auth[7:], _JWT_SECRET, algorithms=["HS256"])
            request.ctx.user_id = payload["sub"]
        except jwt.PyJWTError as exc:
            return json_resp({"error": str(exc)}, status=401)
        return await func(request, *args, **kwargs)

    return wrapper


def _client_ip(request: Request) -> str:
    return request.headers.get("CF-Connecting-IP") or request.ip


async def _audit(db, user_id: str | None, lambda_id: str | None, action: str, ip: str, detail: dict | None = None) -> None:
    await db.execute(
        """
        INSERT INTO audit_logs (user_id, lambda_id, action, ip_address, detail)
        VALUES ($1, $2, $3, $4, $5::jsonb)
        """, uuid.UUID(user_id) if user_id else None, uuid.UUID(lambda_id) if lambda_id else None,
        action, ip, json.dumps(detail) if detail is not None else None)


# ── Exceptions ────────────────────────────────────────────────────────────────


@app.exception(NotFound)
async def handle_404(request: Request, exc):
    return await sanic.response.file(_BASE / "web_client" / "index.html")


@app.exception(MethodNotAllowed)
async def handle_405(request: Request, exc):
    return json_resp({"error": "method not allowed"}, status=405)


@app.exception(SanicException)
async def handle_sanic(request: Request, exc):
    return json_resp({"error": str(exc)}, status=exc.status_code)


# ── Endpoints ─────────────────────────────────────────────────────────────────


@app.post("/auth/login")
async def login(request: Request):
    body = request.json or {}
    username = body.get("username", "").strip()
    password = body.get("password", "")
    if not username or not password:
        return json_resp({"error": "username and password required"}, status=400)

    row = await request.app.ctx.db.fetchrow("SELECT id, password_hash FROM users WHERE username = $1", username)
    if row is None or not bcrypt.checkpw(password.encode(), row["password_hash"].encode()):
        return json_resp({"error": "invalid credentials"}, status=401)

    token, expires_at = _make_token(str(row["id"]))
    return json_resp({"token": token, "expires_at": expires_at})


@app.post("/lambdas")
@authenticated
async def deploy_lambda(request: Request):
    ip = _client_ip(request)
    user_id = request.ctx.user_id
    files = request.files.getlist("files") if request.files else []
    loop = asyncio.get_event_loop()
    response = await request.respond(content_type="application/x-ndjson")

    if not files:
        return json_resp({"error": "at least one file is required"}, status=400)

    async def send(obj: dict) -> None:
        await response.send(json.dumps(obj) + "\n")
        await asyncio.sleep(0)

    await send({"status": "starting code analysis"})

    analysis_reports = []
    for uploaded in files:
        report = analyze(uploaded.body)
        analysis_reports.append({"file": uploaded.name, "report": report})
        if not report["safe"]:
            await _audit(request.app.ctx.db, user_id, None, "deploy_rejected", ip, {"analysis": analysis_reports})
            await send({"status": "error", "message": f"code analysis failed\n{report}"})
            await response.eof()
            return

    name = request.form.get("name") or f"lambda-{uuid.uuid4().hex[:8]}"
    req_file = request.files.get("requirements")
    lambda_id = str(uuid.uuid4())

    try:
        requirements = req_file.body.decode("utf-8") if req_file else ""
    except UnicodeDecodeError:
        await send({"status": "error", "message": "requirements must be a UTF-8 text file"})
        await response.eof()
        return

    await send({"status": "checking environment"})

    try:
        if deployer.env_needs_build(requirements):
            await send({"status": "building environment"})
        env_hash = await loop.run_in_executor(None, deployer.ensure_env, requirements)
        if requirements.strip():
            await send({"status": "environment ready"})
    except Exception as exc:
        await send({"status": "error", "message": str(exc)})
        await response.eof()
        return

    await send({"status": "storing files"})

    with tempfile.TemporaryDirectory() as tmp:
        for uploaded in files:
            (Path(tmp) / uploaded.name).write_bytes(uploaded.body)
        try:
            await loop.run_in_executor(None, deployer.deploy_lambda, lambda_id, tmp)
        except Exception as exc:
            await send({"status": "error", "message": str(exc)})
            await response.eof()
            return

    await request.app.ctx.db.execute(
        """
        INSERT INTO lambdas (id, owner_id, name, script_filename, env_hash)
        VALUES ($1, $2, $3, $4, $5)
        """,
        uuid.UUID(lambda_id), uuid.UUID(user_id), name, files[0].name, env_hash)

    await _audit(request.app.ctx.db, user_id, lambda_id, "deploy", ip, {"name": name, "analysis": analysis_reports})
    await send({"status": "done", "lambda_id": lambda_id})
    await response.eof()


@app.get("/lambdas")
@authenticated
async def list_lambdas(request: Request):
    rows = await request.app.ctx.db.fetch(
        "SELECT id, name FROM lambdas WHERE owner_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC",
        uuid.UUID(request.ctx.user_id))
    return json_resp([{"id": str(row["id"]), "name": row["name"]} for row in rows])


@app.post("/lambdas/<lambda_id>/invoke")
async def invoke_lambda(request: Request, lambda_id: str):
    row = await request.app.ctx.db.fetchrow(
        "SELECT script_filename, env_hash FROM lambdas WHERE id = $1 AND deleted_at IS NULL", uuid.UUID(lambda_id))
    if row is None:
        return json_resp({"error": "not found"}, status=404)

    input_str = (request.json or {}).get("input", "")

    try:
        result = await asyncio.get_event_loop().run_in_executor(None, lambda:
        orchestrator.invoke(lambda_id, row["script_filename"], input_str, row["env_hash"] or None))
    except Exception as exc:
        return json_resp({"error": str(exc)}, status=500)

    await _audit(request.app.ctx.db, None, lambda_id, "invoke", _client_ip(request),
                 {"exit_code": result.get("exit_code"), "stderr": result.get("stderr")})
    return json_resp(result)


@app.delete("/lambdas/<lambda_id>")
@authenticated
async def destroy_lambda(request: Request, lambda_id: str):
    row = await request.app.ctx.db.fetchrow(
        "SELECT id FROM lambdas WHERE id = $1 AND owner_id = $2 AND deleted_at IS NULL",
        uuid.UUID(lambda_id), uuid.UUID(request.ctx.user_id))
    if row is None:
        return json_resp({"error": "not found"}, status=404)

    orchestrator.destroy(lambda_id)
    await request.app.ctx.db.execute("UPDATE lambdas SET deleted_at = NOW() WHERE id = $1", uuid.UUID(lambda_id))
    await _audit(request.app.ctx.db, request.ctx.user_id, lambda_id, "destroy", _client_ip(request))
    return json_resp({"status": "destroyed"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=_PORT, single_process=True)
