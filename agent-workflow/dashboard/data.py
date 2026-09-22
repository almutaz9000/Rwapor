"""Read-only data layer for the Rwapor control-room dashboard.

No Streamlit imports belong here so parsers and repository diagnostics can be
unit-tested without starting a web server.
"""

from __future__ import annotations

import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HUB_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = HUB_ROOT.parent
BOARD_PATH = HUB_ROOT / "agents-board.json"
WORKFLOW_FILES = {
    "task_status": HUB_ROOT / "task-status.md",
    "issues_log": HUB_ROOT / "issues-log.md",
    "session_brief": HUB_ROOT / "session-brief.md",
    "change_log": HUB_ROOT / "change-log.md",
    "project_memory": HUB_ROOT / "project-memory.md",
}


def load_board(path: Path = BOARD_PATH) -> dict[str, Any]:
    """Load the board, accepting the UTF-8 BOM written by Windows PowerShell."""
    return json.loads(path.read_text(encoding="utf-8-sig"))


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig")
    except OSError:
        return ""


def file_fingerprint(path: Path) -> dict[str, Any]:
    try:
        stat = path.stat()
    except OSError:
        return {"path": str(path.relative_to(REPO_ROOT)), "exists": False}
    return {
        "path": str(path.relative_to(REPO_ROOT)),
        "exists": True,
        "modified": datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat(),
        "bytes": stat.st_size,
    }


def git_snapshot() -> dict[str, Any]:
    def run(*args: str) -> str:
        try:
            result = subprocess.run(
                ["git", *args], cwd=REPO_ROOT, capture_output=True,
                text=True, timeout=5, check=False,
            )
            return result.stdout.strip() if result.returncode == 0 else ""
        except (OSError, subprocess.SubprocessError):
            return ""

    status_lines = [line for line in run("status", "--porcelain").splitlines() if line]
    return {
        "branch": run("branch", "--show-current") or "unavailable",
        "head": run("log", "-1", "--pretty=format:%h %ad %s", "--date=short") or "unavailable",
        "changed": len(status_lines),
        "untracked": sum(line.startswith("??") for line in status_lines),
        "status_lines": status_lines,
    }


def parse_markdown_records(text: str, heading: str) -> list[dict[str, str]]:
    """Return compact records from a markdown heading section."""
    match = re.search(
        rf"^##\s+{re.escape(heading)}\s*$([\s\S]*?)(?=^##\s+|\Z)",
        text, re.MULTILINE | re.IGNORECASE,
    )
    if not match:
        return []
    records: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for raw in match.group(1).splitlines():
        line = raw.strip()
        item = re.match(r"^-\s+\*\*(.+?)\*\*\s*(?:\((.*?)\))?\s*(.*)$", line)
        subheading = re.match(r"^###\s+(.+)$", line)
        if subheading:
            if current:
                records.append(current)
            current = {"title": subheading.group(1).strip(), "detail": ""}
        elif item:
            if current:
                records.append(current)
            current = {
                "title": item.group(1).strip(),
                "state": (item.group(2) or "").strip(),
                "detail": item.group(3).strip(),
            }
        elif current and line and not line.startswith("_"):
            current["detail"] = (current.get("detail", "") + " " + line).strip()
    if current:
        records.append(current)
    return records


def workflow_records() -> dict[str, list[dict[str, str]]]:
    task_text = read_text(WORKFLOW_FILES["task_status"])
    issue_text = read_text(WORKFLOW_FILES["issues_log"])
    return {
        "pending_markdown": parse_markdown_records(task_text, "Pending — Next Session (Production Hardening continuation)"),
        "blocked_markdown": parse_markdown_records(task_text, "Blocked"),
        "completed_markdown": parse_markdown_records(task_text, "Recently Completed"),
        "open_issue_markdown": parse_markdown_records(issue_text, "Open"),
        "resolved_issue_markdown": parse_markdown_records(issue_text, "Resolved"),
    }


def _module_name(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def _function_definition_index(files: list[Path]) -> dict[str, str]:
    """Map every top-level `name <- function(...)` to the file that defines it."""
    index: dict[str, str] = {}
    definition_re = re.compile(r"^\s*([a-zA-Z_.][a-zA-Z0-9_.]*)\s*<-\s*function\s*\(", re.MULTILINE)
    for path in files:
        name = _module_name(path)
        for match in definition_re.finditer(read_text(path)):
            index.setdefault(match.group(1), name)
    return index


def module_inventory() -> dict[str, Any]:
    """Build a source map with real call edges, not just filename mentions.

    Three edge kinds, strongest first:
      call      -- caller text has `Rwapor::fn(` or `fn(` and `fn` is defined
                   in exactly one other known file (the real dependency).
      source    -- a literal `source("...")` / `sys.source("...")` reference.
      reference -- fallback: the target file's stem appears in the caller's
                   text with no resolvable function call (weak signal, kept
                   for the evidence table but excluded from the diagram).
    """
    roots = [REPO_ROOT / "R", REPO_ROOT / "inst" / "shiny"]
    files = sorted(p for root in roots if root.exists() for p in root.glob("*.R"))
    known = {_module_name(path): path for path in files}
    nodes = [{"id": name, "kind": "shiny" if name.startswith("inst/shiny") else "r"} for name in known]
    function_index = _function_definition_index(files)

    call_pattern = re.compile(r"(?:Rwapor::)?\b([a-zA-Z_.][a-zA-Z0-9_.]*)\s*\(")

    edges: set[tuple[str, str, str]] = set()
    for source_path in files:
        source_name = _module_name(source_path)
        text = read_text(source_path)

        for match in re.finditer(r"(?:source|sys\.source)\s*\(\s*['\"]([^'\"]+)", text):
            raw = match.group(1).replace("\\", "/")
            candidates = [REPO_ROOT / raw, source_path.parent / raw]
            candidate = next((path.resolve() for path in candidates if path.exists()), None)
            if candidate is not None:
                target = _module_name(candidate)
                if target in known:
                    edges.add((source_name, target, "source"))

        for match in call_pattern.finditer(text):
            fn_name = match.group(1)
            target_name = function_index.get(fn_name)
            if target_name and target_name != source_name:
                edges.add((source_name, target_name, "call"))

        for target_name in known:
            if target_name == source_name:
                continue
            stem = Path(target_name).stem
            if re.search(rf"(?:^|[/_.]){re.escape(stem)}(?:$|[/_.])", text, re.IGNORECASE):
                edges.add((source_name, target_name, "reference"))

    # Build module tree with file/function/class detail (for Module Explorer)
    module_tree = _build_module_tree(files, known)

    return {
        "nodes": nodes,
        "edges": [{"source": s, "target": t, "kind": k} for s, t, k in sorted(edges)],
        "module_tree": module_tree,
    }


def _build_module_tree(files: list[Path], known: dict[str, Path]) -> dict[str, list[dict]]:
    """Group files by logical module group and extract AST-like detail.
    
    Rwapor uses a flat R/ directory, so we group by functional prefix:
    - analysis_* -> analysis
    - api_* -> api
    - crop_* -> crop
    - metadata_*, wapor_metadata_* -> metadata
    - wapor_* -> wapor (core waPOR functions)
    - mod_* (shiny) -> shiny
    - others -> core
    """
    def group_for_file(rel: str) -> str:
        name = Path(rel).name
        # Check shiny modules first
        if rel.startswith("inst/shiny/"):
            if name.startswith("mod_"):
                return "shiny"
            if name == "app.R":
                return "shiny"
            return "shiny"
        # R package files
        if name.startswith("analysis_"):
            return "analysis"
        if name.startswith("api_"):
            return "api"
        if name.startswith("crop_"):
            return "crop"
        if name.startswith("metadata_") or name.startswith("wapor_metadata_"):
            return "metadata"
        if name.startswith("wapor_"):
            return "wapor"
        if name.startswith("interval_") or name.startswith("plan_wapor_"):
            return "temporal"
        if name.startswith("indicators_") or name == "analysis_indicators.R":
            return "indicators"
        if name in ("diagnose.R", "run_dashboard.R", "rwapor_favorites.R", "unit_convertor.R", "viz.R"):
            return "utils"
        return "core"

    tree: dict[str, list[dict]] = {}

    for path in files:
        rel = _module_name(path)
        group = group_for_file(rel)
        if group not in tree:
            tree[group] = []

        text = read_text(path)

        # Extract top-level functions: name <- function(...)
        func_re = re.compile(r"^\s*([a-zA-Z_.][a-zA-Z0-9_.]*)\s*<-\s*function\s*\(", re.MULTILINE)
        functions = [m.group(1) for m in func_re.finditer(text)]

        # Extract S3/S4 methods: function_name.class <- function
        method_re = re.compile(r"^\s*([a-zA-Z_.][a-zA-Z0-9_.]*)\.\w+\s*<-\s*function\s*\(", re.MULTILINE)
        methods = [m.group(1) for m in method_re.finditer(text)]

        # Heuristic: exported if in NAMESPACE or has @export tag
        exported = set()
        namespace_path = REPO_ROOT / "NAMESPACE"
        if namespace_path.exists():
            ns_text = read_text(namespace_path)
            for fn in functions:
                if f"export({fn})" in ns_text or f"exportPattern" in ns_text:
                    exported.add(fn)

        # Public vs private
        public_funcs = [f for f in functions if not f.startswith("_") or f in exported]
        private_funcs = [f for f in functions if f.startswith("_") and f not in exported]

        tree[group].append({
            "rel_path": rel,
            "line_count": len(text.splitlines()),
            "functions": functions,
            "public_functions": public_funcs,
            "private_functions": private_funcs,
            "methods": methods,
            "exported": list(exported & set(functions)),
        })

    # Sort files within each group
    for group in tree:
        tree[group].sort(key=lambda f: f["rel_path"])

    return tree


# ---- Mermaid diagram support (like waporbox) ----

# Rwapor module groups in dependency order
RWAPOR_MODULE_GROUPS = [
    "core",
    "api",
    "metadata",
    "crop",
    "temporal",
    "indicators",
    "wapor",
    "analysis",
    "utils",
    "shiny",
]

# Module dependency edges (source -> target = source depends on target)
RWAPOR_MODULE_DEPENDENCY_EDGES = [
    ("api", "core"),
    ("metadata", "core"),
    ("metadata", "api"),
    ("crop", "core"),
    ("temporal", "core"),
    ("temporal", "metadata"),
    ("indicators", "core"),
    ("wapor", "core"),
    ("wapor", "metadata"),
    ("wapor", "crop"),
    ("analysis", "core"),
    ("analysis", "wapor"),
    ("analysis", "temporal"),
    ("analysis", "indicators"),
    ("utils", "core"),
    ("shiny", "core"),
    ("shiny", "analysis"),
    ("shiny", "wapor"),
    ("shiny", "metadata"),
    ("shiny", "temporal"),
]

# Task/milestone to module group mapping (for completion %)
# Maps IMPROVEMENT_PLAN.md task IDs to the module groups they touch
RWAPOR_TASK_MODULE_GROUPS = {
    "1.1": ["analysis", "wapor"],           # Latitude-aware area weighting
    "1.2": ["indicators", "analysis"],       # Pure math layer
    "1.3": ["analysis", "indicators"],       # Step registry
    "1.4": ["analysis", "wapor", "temporal"], # Tiled engine
    "1.5": ["shiny", "wapor", "analysis"],   # L3 selection UI
    "1.6": ["analysis"],                     # Alignment reference
    "2.1": ["api", "metadata"],              # Disk URL cache
    "2.2": ["wapor", "analysis"],            # COG write
    "2.3": ["analysis"],                     # Memory benchmarks
    "3.1": ["crop"],                         # Extra crop defaults
    "3.3": ["utils"],                        # Publication map helpers (viz.R)
    "3.4": ["utils", "analysis"],            # Anomaly & trend
    "3.5": ["analysis"],                     # Preflight validation
    "4.1": ["shiny"],                        # Dashboard indicator selection
    "4.2": ["wapor", "shiny"],               # DuckDB monitoring
    "5.1": ["indicators"],                   # Unit tests math layer
    "5.2": ["analysis"],                     # Integration tests
    "5.3": ["utils"],                        # CI linting
    "6.1": ["utils"],                        # Vignettes
    "6.2": ["utils"],                        # README
    "7.0": ["api", "metadata"],              # %||% dedup
    "7.1": ["api", "metadata"],              # RET/PCP fallback
    "7.2": ["wapor"],                        # wapor_res_key
    "7.3": ["metadata"],                     # Memoise metadata catalog
    "7.6": ["temporal"],                     # Memoise temporal codes
}

RWAPOR_MODULE_DESCRIPTIONS = {
    "core": "Core utilities, %||% operator, GDAL config, diagnostics",
    "api": "FAO GIS Manager API client, URL generation, HTTP retries",
    "metadata": "WaPOR L1/L2/L3 metadata cache, variable catalogs, manifests",
    "crop": "FAO-56 crop parameter tables (Kc, HI, MC, growth stages)",
    "temporal": "Seasonal time-slice planning, interval decomposition",
    "indicators": "Pure math layer: adequacy, Peff, green/blue water, CWP/BWP",
    "wapor": "Core WaPOR functions: TS, Map, COG write, pixel area, res keys",
    "analysis": "Seasonal analysis engine (tiled + standard), indicator registry",
    "utils": "Visualization helpers, unit conversion, favorites, diagnostics",
    "shiny": "Interactive Shiny dashboard: download, analysis, monitoring tabs",
}


def compute_module_completion(tasks: list[dict]) -> dict[str, float]:
    """Calculate completion % per module group from task board.
    
    A task contributes its completion (100% if done, 0% otherwise) to 
    all module groups it touches.
    """
    totals: dict[str, list[float]] = {mod: [] for mod in RWAPOR_MODULE_GROUPS}
    
    for task in tasks:
        task_id = task.get("id", "")
        status = task.get("status", "pending")
        is_done = (status == "done")
        
        # Find module groups for this task ID
        groups = RWAPOR_TASK_MODULE_GROUPS.get(task_id, [])
        if not groups and "." in task_id:
            # Try prefix match (e.g., "1.5" for "1.5")
            prefix = task_id.split(".")[0] + "."
            for k, v in RWAPOR_TASK_MODULE_GROUPS.items():
                if k.startswith(prefix):
                    groups = v
                    break
        
        for g in groups:
            if g in totals:
                totals[g].append(100.0 if is_done else 0.0)
    
    return {mod: (sum(v) / len(v) if v else 0.0) for mod, v in totals.items()}


def build_mermaid_diagram(module_pct: dict[str, float]) -> str:
    """Build mermaid.js flowchart diagram colored by completion %."""
    # Color bands: 0-20 red, 20-40 orange, 40-60 yellow, 60-80 light green, 80-100 green
    def band(pct: float) -> tuple[str, str]:
        if pct <= 20: return "#f7d8d2", "#9c3d2c"
        if pct <= 40: return "#f8ecd8", "#b5651d"
        if pct <= 60: return "#faf3c0", "#a68a1a"
        if pct <= 80: return "#e6f0d2", "#5c8a2e"
        return "#cdeadd", "#1f6b3a"

    lines = ["graph LR"]
    
    # Node definitions with completion %
    for mod in RWAPOR_MODULE_GROUPS:
        pct = module_pct.get(mod, 0.0)
        label = f"{mod}\\n{pct:.0f}% done"
        lines.append(f'    {mod}["{label}"]')
    
    # Dependency edges
    for src, dst in RWAPOR_MODULE_DEPENDENCY_EDGES:
        lines.append(f"    {src} --> {dst}")
    
    # Styling
    for mod in RWAPOR_MODULE_GROUPS:
        pct = module_pct.get(mod, 0.0)
        fill, stroke = band(pct)
        lines.append(f"    style {mod} fill:{fill},stroke:{stroke},stroke-width:2px,color:#152220")
    
    return "\\n".join(lines)


def mermaid_html(diagram: str, height: int = 500) -> str:
    """Self-contained HTML fragment that renders diagram via mermaid.js CDN."""
    return f"""
<div class="mermaid">
{diagram}
</div>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<script>
  mermaid.initialize({{ startOnLoad: true, theme: "default", flowchart: {{ curve: "basis" }} }});
</script>
<style>
  body {{ margin: 0; }}
  .mermaid {{ display: flex; justify-content: center; }}
</style>
"""


def extract_claim_tokens(text: str) -> list[str]:
    """Pull code-like identifiers out of a task's title/notes.

    These are the concrete, checkable pieces of a claim: backticked names,
    function calls, snake_case identifiers, and quoted identifiers. Prose
    words are deliberately excluded -- a vague claim yields zero tokens and
    is reported as "not_checkable" rather than guessed at.
    """
    if not text:
        return []
    tokens: set[str] = set()
    patterns = (
        r"`([A-Za-z_][A-Za-z0-9_.]{2,})`",
        r"\b([a-zA-Z_][a-zA-Z0-9_.]*)\s*\(",
        r"\b([a-z][a-z0-9]*(?:_[a-z0-9]+){1,})\b",
        r"'([A-Za-z_][A-Za-z0-9_.]{2,})'",
    )
    for pattern in patterns:
        for match in re.finditer(pattern, text):
            token = match.group(1)
            if len(token) >= 4:
                tokens.add(token)
    return sorted(tokens)


def verify_task_claim(task: dict[str, Any], repo_root: Path = REPO_ROOT) -> dict[str, Any]:
    """Check a task's claimed deliverables against the files it names.

    Read-only, evidence-based: extracts identifier-like tokens from the
    title/notes, then greps the task's listed files for each token. This is
    the same check a reviewer does by hand (see session-brief.md 2026-09-17
    "critical re-review"), automated so overclaiming is caught without a
    manual audit every time.
    """
    files = task.get("files") or []
    title = task.get("title", "") or ""
    notes = task.get("notes", "") or ""
    tokens = extract_claim_tokens(f"{title} {notes}")

    checked_files: list[str] = []
    missing_files: list[str] = []
    file_texts: list[str] = []
    for rel in files:
        path = repo_root / rel
        if path.exists():
            checked_files.append(rel)
            file_texts.append(read_text(path))
        else:
            missing_files.append(rel)

    combined_text = "\n".join(file_texts)
    matched = [t for t in tokens if re.search(re.escape(t), combined_text, re.IGNORECASE)]
    missing_tokens = [t for t in tokens if t not in matched]

    if not files:
        verdict = "no_files_listed"
    elif not checked_files:
        verdict = "files_missing"
    elif not tokens:
        verdict = "not_checkable"
    elif not missing_tokens:
        verdict = "verified"
    elif matched:
        verdict = "partial"
    else:
        verdict = "unverified"

    return {
        "id": task.get("id"),
        "title": title,
        "status": task.get("status"),
        "model": task.get("model") or "unassigned",
        "verdict": verdict,
        "tokens_checked": tokens,
        "tokens_matched": matched,
        "tokens_missing": missing_tokens,
        "files_checked": checked_files,
        "files_missing": missing_files,
    }


def claim_verification_report(tasks: list[dict[str, Any]], repo_root: Path = REPO_ROOT) -> list[dict[str, Any]]:
    return [verify_task_claim(task, repo_root) for task in tasks]


def _parse_utc(value: str) -> datetime:
    """Parse the board's claimed_utc/updated_utc formats (date-only or ISO-Z)."""
    value = value.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return datetime.strptime(value, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def stale_active_claims(
    tasks: list[dict[str, Any]], now: datetime | None = None, threshold_hours: float = 24,
) -> list[dict[str, Any]]:
    """Flag tasks stuck "active" -- an agent that crashed or never closed out.

    A task claimed by a model and left active past the threshold, or active
    with no claimed_utc timestamp at all, is surfaced here instead of
    silently blocking the task for the next model that checks the board.
    """
    now = now or datetime.now(timezone.utc)
    stale: list[dict[str, Any]] = []
    for task in tasks:
        if task.get("status") != "active":
            continue
        claimed = task.get("claimed_utc")
        entry = {
            "id": task.get("id"),
            "title": task.get("title", ""),
            "model": task.get("model") or "unassigned",
            "claimed_utc": claimed,
        }
        if not claimed:
            stale.append({**entry, "hours_since_claim": None, "reason": "active with no claimed_utc timestamp"})
            continue
        try:
            claimed_dt = _parse_utc(claimed)
        except ValueError:
            stale.append({**entry, "hours_since_claim": None, "reason": f"unparseable claimed_utc: {claimed}"})
            continue
        hours = (now - claimed_dt).total_seconds() / 3600
        if hours >= threshold_hours:
            stale.append({**entry, "hours_since_claim": round(hours, 1), "reason": f"claimed {hours:.1f}h ago, no status change since"})
    return stale


def decision_records(board: dict[str, Any], workflow: dict[str, list[dict[str, str]]]) -> list[dict[str, str]]:
    """Find unresolved human decisions without inventing a second tracker."""
    records: list[dict[str, str]] = []
    for alert in board.get("alerts", []):
        if not alert.get("resolved"):
            records.append({"id": alert.get("id", "alert"), "title": alert.get("title", ""), "detail": alert.get("detail", ""), "source": alert.get("source", "board alert"), "priority": alert.get("severity", "warning")})
    for task in board.get("tasks", []):
        text = f"{task.get('title', '')} {task.get('notes', '')}"
        if task.get("status") != "done" and re.search(r"\b(decision|decide|maintainer decision|choice)\b", text, re.IGNORECASE):
            records.append({"id": task.get("id", "task"), "title": task.get("title", ""), "detail": task.get("notes", ""), "source": "agents-board.json", "priority": task.get("priority", "medium")})
    return records


def build_snapshot() -> dict[str, Any]:
    board = load_board()
    workflow = workflow_records()
    tasks = board.get("tasks", [])
    git = git_snapshot()
    warnings: list[dict[str, str]] = []
    if git["changed"]:
        warnings.append({"severity": "warning", "title": "Working tree contains uncommitted changes", "detail": f"{git['changed']} changed paths on branch {git['branch']}; {git['untracked']} are untracked.", "source": "git status"})
    missing_sources = [item["path"] for item in [file_fingerprint(path) for path in [BOARD_PATH, *WORKFLOW_FILES.values()]] if not item["exists"]]
    if missing_sources:
        warnings.append({"severity": "critical", "title": "Canonical workflow source is missing", "detail": ", ".join(missing_sources), "source": "repository preflight"})

    claims = claim_verification_report(tasks)
    unverified_claims = [c for c in claims if c["verdict"] in ("unverified", "partial", "files_missing")]
    if unverified_claims:
        warnings.append({
            "severity": "warning",
            "title": f"{len(unverified_claims)} task claim(s) not fully backed by the files they list",
            "detail": ", ".join(f"{c['id']} ({c['verdict']})" for c in unverified_claims),
            "source": "claim verification",
        })

    stale_claims = stale_active_claims(tasks)
    if stale_claims:
        warnings.append({
            "severity": "critical",
            "title": f"{len(stale_claims)} task(s) stuck active past the staleness threshold",
            "detail": ", ".join(f"{c['id']} ({c['model']}, {c['reason']})" for c in stale_claims),
            "source": "stale claim check",
        })

    return {
        "board": board,
        "workflow": workflow,
        "decisions": decision_records(board, workflow),
        "warnings": warnings,
        "git": git,
        "modules": module_inventory(),
        "claims": claims,
        "stale_claims": stale_claims,
        "source_files": [file_fingerprint(path) for path in [BOARD_PATH, *WORKFLOW_FILES.values()]],
        "loaded_utc": datetime.now(timezone.utc).isoformat(),
        "task_counts": {status: sum(task.get("status") == status for task in tasks) for status in ("active", "pending", "blocked", "done")},
    }
