import ast
import hashlib
import json
import os
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from dotenv import load_dotenv

try:
    import anthropic as _anthropic
    _ANTHROPIC_AVAILABLE = True
except ImportError:
    _ANTHROPIC_AVAILABLE = False

try:
    import yara as _yara
    _YARA_AVAILABLE = True
except ImportError:
    _YARA_AVAILABLE = False

try:
    import bandit.core.config as _b_config
    import bandit.core.manager as _b_manager
    import tempfile
    _BANDIT_AVAILABLE = True
except ImportError:
    _BANDIT_AVAILABLE = False

# Load anthropic api key
def _load_api_key() -> str | None:
    # 1. Environment variable
    key = os.environ.get("ANTHROPIC_API_KEY")
    if key:
        return key.strip()

    # 2. .env file next to this script
    env_file = Path(__file__).parent / ".env"
    load_dotenv(dotenv_path=env_file)
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if api_key:
        return api_key.strip()
    return None

# Result types ============================================================

@dataclass
class CheckResult:
    """Result of a single analysis check."""
    name: str                        # human-readable check name
    status: str                      # "pass" | "warn" | "fail" | "error" | "skip"
    description: str                 # one-line summary
    details: list[str] = field(default_factory=list)   # per-finding lines
    raw: dict[str, Any] = field(default_factory=dict)  # tool-specific data


@dataclass
class AnalysisReport:
    """Aggregated result returned by analyze()."""
    safe: bool                        # final verdict
    confidence: str                   # "high" | "medium" | "low"
    summary: str                      # one-line overall summary
    checks: list[CheckResult] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "safe": self.safe,
            "confidence": self.confidence,
            "summary": self.summary,
            "checks": [
                {
                    "name": c.name,
                    "status": c.status,
                    "description": c.description,
                    "details": c.details,
                }
                for c in self.checks
            ],
            "metadata": self.metadata,
        }


# File validation ==============================================
def _check_file_type(code_bytes: bytes) -> CheckResult:
    # Empty file is not valid Python
    if not code_bytes or len(code_bytes.strip()) == 0:
        return CheckResult(
            name="File validation",
            status="fail",
            description="Input is empty, nothing to analyze or execute.",
        )
    
    if b"\x00" in code_bytes:
        return CheckResult(
            name="File validation",
            status="fail",
            description="Input contains null bytes, not a Python source file.",
        )

    # Must decode as UTF-8
    try:
        source = code_bytes.decode("utf-8")
    except UnicodeDecodeError:
        return CheckResult(
            name="File validation",
            status="fail",
            description="Input is not valid UTF-8 text.",
        )

    # Must parse as Python
    try:
        ast.parse(source)
    except SyntaxError as e:
        return CheckResult(
            name="File validation",
            status="fail",
            description=f"Python syntax error: {e}",
            details=[str(e)],
        )

    lines = source.splitlines()
    return CheckResult(
        name="File validation",
        status="pass",
        description=f"Valid Python source file ({len(lines)} lines).",
        raw={"lines": len(lines), "size_bytes": len(code_bytes)},
    )


# Antivirus (YARA) =====================================

_YARA_COMPILED: "_yara.Rules | None" = None
_YARA_LOCK = threading.Lock()

def _get_yara_rules() -> "_yara.Rules":
    global _YARA_COMPILED
    if _YARA_COMPILED is None:
        with _YARA_LOCK:
            if _YARA_COMPILED is None:
                rules_path = Path(__file__).parent / "config" / "antivirus" / "rules.yar"
                if not rules_path.exists():
                    raise FileNotFoundError(f"YARA rules file missing at: {rules_path}")
                
                _YARA_COMPILED = _yara.compile(filepath=str(rules_path))                
    return _YARA_COMPILED


def _check_antivirus(code_bytes: bytes) -> CheckResult:
    if not _YARA_AVAILABLE:
        return CheckResult(
            name="Antivirus (YARA)",
            status="skip",
            description="yara-python not installed. Run: pip install yara-python",
        )

    try:
        rules = _get_yara_rules()
        matches = rules.match(data=code_bytes)
    except Exception as e:
        return CheckResult(
            name="Antivirus (YARA)",
            status="error",
            description=f"YARA scan error: {e}",
        )

    if not matches:
        return CheckResult(
            name="Antivirus (YARA)",
            status="pass",
            description="No malware signatures matched.",
        )

    findings = []
    for match in matches:
        severity = match.meta.get("severity", "unknown").upper()
        desc = match.meta.get("description", match.rule)
        findings.append(f"[{severity}] {match.rule}: {desc}")

    critical = any("CRITICAL" in f for f in findings)
    return CheckResult(
        name="Antivirus (YARA)",
        status="fail" if critical else "warn",
        description=f"{len(matches)} YARA rule(s) matched.",
        details=findings,
        raw={"rules_matched": [m.rule for m in matches]},
    )


# Static analysis (AST + Bandit) ===================================

_DANGEROUS_CALLS = {
    # (module, attr) or (None, builtin_name)
    (None, "eval"),
    (None, "exec"),
    (None, "compile"),
    (None, "__import__"),
    ("os", "system"),
    ("os", "popen"),
    ("os", "execv"),
    ("os", "execve"),
    ("os", "execvp"),
    ("subprocess", "call"),
    ("subprocess", "run"),
    ("subprocess", "Popen"),
    ("subprocess", "check_output"),
    ("ctypes", "CDLL"),
    ("ctypes", "cdll"),
}

_DANGEROUS_IMPORTS = {
    "pickle", "marshal", "shelve",   # arbitrary code execution via deserialization
    "pty",                           # terminal hijacking
    "socket",                        # raw network access
}


def _ast_scan(source: str) -> list[str]:
    findings: list[str] = []
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return findings

    for node in ast.walk(tree):
        # Dangerous imports
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            mod = ""
            if isinstance(node, ast.Import):
                for alias in node.names:
                    mod = alias.name.split(".")[0]
                    if mod in _DANGEROUS_IMPORTS:
                        findings.append(f"Line {node.lineno}: import of '{mod}' (potentially dangerous)")
            elif isinstance(node, ast.ImportFrom) and node.module:
                mod = node.module.split(".")[0]
                if mod in _DANGEROUS_IMPORTS:
                    findings.append(f"Line {node.lineno}: from '{mod}' import (potentially dangerous)")

        # Dangerous function calls
        if isinstance(node, ast.Call):
            func = node.func
            # bare call: eval(...), exec(...)
            if isinstance(func, ast.Name):
                if (None, func.id) in _DANGEROUS_CALLS:
                    findings.append(f"Line {node.lineno}: call to '{func.id}()' (dangerous builtin)")
            # attribute call: os.system(...), subprocess.run(...)
            elif isinstance(func, ast.Attribute):
                if isinstance(func.value, ast.Name):
                    key = (func.value.id, func.attr)
                    if key in _DANGEROUS_CALLS:
                        findings.append(f"Line {node.lineno}: call to '{func.value.id}.{func.attr}()' (dangerous)")

        # __dunder__ attribute access (e.g. func.__globals__, __builtins__ manipulation)
        if isinstance(node, ast.Attribute) and node.attr.startswith("__") and node.attr.endswith("__"):
            if node.attr in ("__globals__", "__builtins__", "__class__", "__subclasses__", "__code__"):
                findings.append(f"Line {node.lineno}: access to '{node.attr}' (sandbox escape attempt)")

    return findings


def _run_bandit(source: str) -> list[str]:
    if not _BANDIT_AVAILABLE:
        return []

    with tempfile.NamedTemporaryFile(suffix=".py", delete=False, mode="w", encoding="utf-8") as tf:
        tf.write(source)
        tmp_path = tf.name

    findings: list[str] = []
    try:
        conf = _b_config.BanditConfig()
        mgr = _b_manager.BanditManager(conf, "file", False)
        mgr.discover_files([tmp_path], False)
        mgr.run_tests()

        for issue in mgr.get_issue_list():
            sev  = issue.severity.upper()    # LOW / MEDIUM / HIGH
            conf_str = issue.confidence.upper()
            text = issue.text
            line = issue.lineno
            findings.append(f"Line {line} [{sev}/{conf_str}]: {text}")
    except Exception:
        pass  # bandit errors are non-fatal, AST scan can still catch issues
    finally:
        os.unlink(tmp_path)

    return findings


def _check_static(code_bytes: bytes) -> CheckResult:
    try:
        source = code_bytes.decode("utf-8")
    except UnicodeDecodeError:
        return CheckResult(
            name="Static analysis",
            status="error",
            description="Cannot decode source for static analysis.",
        )

    findings: list[str] = []

    # AST scan
    findings.extend(_ast_scan(source))

    # Bandit scan
    bandit_findings = _run_bandit(source)
    findings.extend(bandit_findings)

    if not findings:
        return CheckResult(
            name="Static analysis",
            status="pass",
            description=f"No dangerous patterns detected. {'(bandit skipped)' if not _BANDIT_AVAILABLE else ''}",
            raw={"bandit_available": _BANDIT_AVAILABLE},
        )

    high = any("HIGH" in f for f in findings)
    status = "fail" if (high or len(findings) > 3) else "warn"

    return CheckResult(
        name="Static analysis",
        status=status,
        description=f"{len(findings)} suspicious pattern(s) found. (bandit: {'yes' if _BANDIT_AVAILABLE else 'not installed'})",
        details=findings,
        raw={"bandit_available": _BANDIT_AVAILABLE},
    )


# LLM analysis (Claude) ===========================================

def _check_llm(code_bytes: bytes) -> CheckResult:
    if not _ANTHROPIC_AVAILABLE:
        return CheckResult(
            name="LLM analysis (Claude)",
            status="skip",
            description="anthropic package not installed. Run: pip install anthropic",
        )

    api_key = _load_api_key()
    if not api_key:
        return CheckResult(
            name="LLM analysis (Claude)",
            status="skip",
            description=(
                "No API key configured. Set ANTHROPIC_API_KEY env var or add it to .env."
            ),
        )
    
    prompt_path = Path(__file__).parent / "config" / "prompts" / "llm_analyst.txt"
    if not prompt_path.exists():
        return CheckResult(
            name="LLM analysis (Claude)",
            status="error",
            description=f"System prompt file missing at {prompt_path}",
        )
    
    try:
        system_prompt = prompt_path.read_text(encoding="utf-8").strip()
    except Exception as e:
        return CheckResult(
            name="LLM analysis (Claude)",
            status="error",
            description=f"Failed to read system prompt: {e}",
        )

    try:
        source = code_bytes.decode("utf-8")
    except UnicodeDecodeError:
        return CheckResult(
            name="LLM analysis (Claude)",
            status="error",
            description="Cannot decode source for LLM analysis.",
        )

    try:
        client = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-haiku-4-5",
            max_tokens=1024,
            system=system_prompt,
            messages=[
                {
                    "role": "user",
                    "content": f"Analyze this Python code:\n\n```python\n{source}\n```",
                }
            ],
        )

        raw_text = message.content[0].text.strip()

        # Skip markdown code fences if present, to extract the JSON
        if raw_text.startswith("```"):
            raw_text = "\n".join(
                line for line in raw_text.splitlines()
                if not line.strip().startswith("```")
            ).strip()

        llm_result = json.loads(raw_text)

    except json.JSONDecodeError as e:
        return CheckResult(
            name="LLM analysis (Claude)",
            status="error",
            description=f"LLM returned non-JSON response: {e}",
        )
    except Exception as e:
        return CheckResult(
            name="LLM analysis (Claude)",
            status="error",
            description=f"LLM API error: {e}",
        )

    verdict = llm_result.get("verdict", "unknown")
    recommendation = llm_result.get("recommendation", "review")
    findings = llm_result.get("findings", [])

    if verdict == "safe" and recommendation == "allow":
        status = "pass"
    elif verdict == "malicious" or recommendation == "block":
        status = "fail"
    else:
        status = "warn"

    details = [
        f"[{f.get('severity', '?').upper()}] {f.get('description', '')}"
        for f in findings
    ]

    return CheckResult(
        name="LLM analysis (Claude)",
        status=status,
        description=f"Verdict: {verdict} | Recommendation: {recommendation} | Confidence: {llm_result.get('confidence', '?')}",
        details=details,
        raw=llm_result,
    )


# Aggregation ===============================================================

def _aggregate(checks: list[CheckResult]) -> tuple[bool, str, str]:
    statuses = {c.status for c in checks}
    names_failed = [c.name for c in checks if c.status == "fail"]

    # Required checks that must not error out
    required = {"File validation", "Static analysis"}
    critical_errors = [c.name for c in checks if c.status == "error" and c.name in required]

    if names_failed:
        safe = False
        confidence = "high"
        summary = f"Rejected: failed checks, {', '.join(names_failed)}."
    elif critical_errors:
        safe = False
        confidence = "low"
        summary = f"Rejected: analysis errors in required checks, {', '.join(critical_errors)}."
    elif "warn" in statuses:
        safe = True
        confidence = "medium"
        summary = "Suspicious patterns detected, manual review recommended."
    else:
        safe = True
        confidence = "high"
        summary = "No issues detected across all available checks."

    return safe, confidence, summary


# Public API ================================================================

def analyze(code_bytes: bytes) -> dict:
    start = time.monotonic()
    checks = []

    file_check = _check_file_type(code_bytes)
    checks.append(file_check)

    if file_check.status == "fail":
        safe, confidence, summary = _aggregate(checks)
        
        report = AnalysisReport(
            safe=safe,
            confidence=confidence,
            summary=summary,
            checks=checks,
            metadata={
                "size_bytes": len(code_bytes),
                "sha256": hashlib.sha256(code_bytes).hexdigest(),
                "elapsed_seconds": round(time.monotonic() - start, 3),
            },
        )
        return report.to_dict()

    checks.extend([
        _check_antivirus(code_bytes),
        _check_static(code_bytes),
        _check_llm(code_bytes),
    ])

    safe, confidence, summary = _aggregate(checks)

    report = AnalysisReport(
        safe=safe,
        confidence=confidence,
        summary=summary,
        checks=checks,
        metadata={
            "size_bytes": len(code_bytes),
            "sha256": hashlib.sha256(code_bytes).hexdigest(),
            "elapsed_seconds": round(time.monotonic() - start, 3),
        },
    )

    return report.to_dict()

# CLI mode ==================================================================

def _status_icon(status: str) -> str:
    return {"pass": "✓", "warn": "⚠", "fail": "✗", "error": "!", "skip": "–"}.get(status, "?")


def _print_report(path: Path, report: dict) -> None:
    safe_label = "\033[32mSAFE\033[0m" if report["safe"] else "\033[31mUNSAFE\033[0m"
    conf = report["confidence"].upper()
    print(f"\n{'='*60}")
    print(f"  {path}")
    print(f"  Verdict : {safe_label}  ({conf} confidence)")
    print(f"  Summary : {report['summary']}")
    print(f"  SHA256  : {report['metadata']['sha256'][:16]}…")
    print(f"  Elapsed : {report['metadata']['elapsed_seconds']}s")
    print()
    for check in report["checks"]:
        icon = _status_icon(check["status"])
        print(f"  [{icon}] {check['name']}: {check['description']}")
        for detail in check.get("details", [])[:5]:  # cap at 5 lines per check
            print(f"       • {detail}")

def _print_file_analysis(path: Path) -> None:
    try:
        code_bytes = path.read_bytes()
    except OSError as e:
        print(f"Cannot read {path}: {e}")
        return

    report = analyze(code_bytes)
    _print_report(path, report)


def _scan_directory(root: Path) -> None:
    py_files = sorted(
        p for p in root.rglob("*.py")
        if p.resolve() != Path(__file__).resolve()  # skip self
    )

    if not py_files:
        print(f"No .py files found under {root}")
        return

    print(f"Scanning {len(py_files)} file(s) under {root} …")

    for path in py_files:
        _print_file_analysis(path)


if __name__ == "__main__":
    if len(os.sys.argv) == 1:
        scan_root = Path(__file__).parent
        _scan_directory(scan_root)
    elif len(os.sys.argv) == 2:
        file_path = Path(os.sys.argv[1])
        if file_path.is_file():
            _print_file_analysis(file_path)
            print(f"\n{'='*60}")
            print("Done.")
        elif file_path.is_dir():
            _scan_directory(file_path)
            print(f"\n{'='*60}")
            print("Done.")
        else:
            print(f"Path not found: {file_path}")
