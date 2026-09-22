from datetime import datetime, timedelta, timezone
from pathlib import Path
import json

from data import (
    decision_records,
    extract_claim_tokens,
    load_board,
    module_control_records,
    module_inventory,
    parse_markdown_records,
    stale_active_claims,
    verify_task_claim,
)


def test_load_board_accepts_power_shell_bom(tmp_path: Path):
    path = tmp_path / "board.json"
    path.write_text("\ufeff" + json.dumps({"tasks": []}), encoding="utf-8")
    assert load_board(path) == {"tasks": []}


def test_parse_markdown_records_keeps_details():
    text = "## Pending\n\n- **1.5 — L3 policy** (critical)\n  Wire the UI and document the fallback.\n\n## Done\n"
    records = parse_markdown_records(text, "Pending")
    assert records == [{"title": "1.5 — L3 policy", "state": "critical", "detail": "Wire the UI and document the fallback."}]


def test_decisions_include_unresolved_alerts_and_decision_tasks():
    board = {
        "alerts": [{"id": "a1", "title": "Choose branch", "detail": "Pick a base.", "source": "git", "resolved": False}],
        "tasks": [{"id": "6.1", "title": "Vignettes", "status": "pending", "notes": "Needs a maintainer decision."}],
    }
    decisions = decision_records(board, {})
    assert [item["id"] for item in decisions] == ["a1", "6.1"]


def test_module_inventory_is_grounded_in_repo_files():
    inventory = module_inventory()
    ids = {node["id"] for node in inventory["nodes"]}
    assert "R/api_client.R" in ids
    assert "inst/shiny/app.R" in ids
    assert all(edge["source"] in ids and edge["target"] in ids for edge in inventory["edges"])


def test_module_inventory_resolves_real_function_calls(tmp_path: Path, monkeypatch):
    """_function_definition_index maps a defined function to its file's relative path."""
    r_dir = tmp_path / "R"
    r_dir.mkdir(parents=True)
    (r_dir / "core.R").write_text("wapor_do_thing <- function(x) x + 1\n", encoding="utf-8")

    import data as data_module
    monkeypatch.setattr(data_module, "REPO_ROOT", tmp_path)

    index = data_module._function_definition_index([r_dir / "core.R"])
    assert index["wapor_do_thing"] == "R/core.R"


def test_module_inventory_call_edges_beat_weak_reference_edges(tmp_path: Path, monkeypatch):
    """A resolvable Rwapor::fn() call produces a 'call' edge, not just 'reference'."""
    r_dir = tmp_path / "R"
    shiny_dir = tmp_path / "inst" / "shiny"
    r_dir.mkdir(parents=True)
    shiny_dir.mkdir(parents=True)
    (r_dir / "core.R").write_text("wapor_do_thing <- function(x) x + 1\n", encoding="utf-8")
    (shiny_dir / "mod_x.R").write_text("result <- Rwapor::wapor_do_thing(5)\n", encoding="utf-8")

    import data as data_module
    monkeypatch.setattr(data_module, "REPO_ROOT", tmp_path)

    inventory = data_module.module_inventory()
    call_edges = [e for e in inventory["edges"] if e["kind"] == "call"]
    assert {"source": "inst/shiny/mod_x.R", "target": "R/core.R", "kind": "call"} in call_edges


# --- Claim verification (a) ---------------------------------------------

def test_extract_claim_tokens_pulls_backticked_and_call_and_snake_case():
    text = "Implemented `wapor_build_kc_by_class()` and the resampling_method param."
    tokens = extract_claim_tokens(text)
    assert "wapor_build_kc_by_class" in tokens
    assert "resampling_method" in tokens


def test_extract_claim_tokens_empty_for_pure_prose():
    assert extract_claim_tokens("Needs a maintainer decision on naming.") == []


def test_verify_task_claim_verified_when_token_present_in_file(tmp_path: Path):
    target = tmp_path / "R" / "analysis_engine.R"
    target.parent.mkdir(parents=True)
    target.write_text("reference_layer <- function(x) x", encoding="utf-8")
    task = {"id": "1.6", "title": "Add `reference_layer` support", "notes": "", "files": ["R/analysis_engine.R"], "status": "pending"}
    result = verify_task_claim(task, repo_root=tmp_path)
    assert result["verdict"] == "verified"
    assert "reference_layer" in result["tokens_matched"]


def test_verify_task_claim_unverified_when_token_absent(tmp_path: Path):
    target = tmp_path / "R" / "analysis_engine.R"
    target.parent.mkdir(parents=True)
    target.write_text("some_other_function <- function(x) x", encoding="utf-8")
    task = {"id": "3.4", "title": "Add `linear_trend` support", "notes": "", "files": ["R/analysis_engine.R"], "status": "done"}
    result = verify_task_claim(task, repo_root=tmp_path)
    assert result["verdict"] == "unverified"
    assert "linear_trend" in result["tokens_missing"]


def test_verify_task_claim_partial_when_some_tokens_missing(tmp_path: Path):
    target = tmp_path / "R" / "x.R"
    target.parent.mkdir(parents=True)
    target.write_text("wapor_build_kc_by_class <- function(x) x", encoding="utf-8")
    task = {
        "id": "x",
        "title": "Add `wapor_build_kc_by_class()` and `wapor_missing_helper()`",
        "notes": "",
        "files": ["R/x.R"],
        "status": "done",
    }
    result = verify_task_claim(task, repo_root=tmp_path)
    assert result["verdict"] == "partial"


def test_verify_task_claim_files_missing_when_listed_file_absent(tmp_path: Path):
    task = {"id": "y", "title": "Add `some_function()`", "notes": "", "files": ["R/does_not_exist.R"], "status": "done"}
    result = verify_task_claim(task, repo_root=tmp_path)
    assert result["verdict"] == "files_missing"
    assert result["files_missing"] == ["R/does_not_exist.R"]


def test_verify_task_claim_no_files_listed():
    task = {"id": "z", "title": "Vague task", "notes": "", "files": [], "status": "pending"}
    result = verify_task_claim(task, repo_root=Path("."))
    assert result["verdict"] == "no_files_listed"


def test_verify_task_claim_not_checkable_for_prose_only_claim(tmp_path: Path):
    target = tmp_path / "R" / "x.R"
    target.parent.mkdir(parents=True)
    target.write_text("# nothing relevant", encoding="utf-8")
    task = {"id": "w", "title": "Needs a maintainer decision", "notes": "", "files": ["R/x.R"], "status": "pending"}
    result = verify_task_claim(task, repo_root=tmp_path)
    assert result["verdict"] == "not_checkable"


# --- Stale active claims (b) ---------------------------------------------

def test_stale_active_claims_flags_old_claimed_utc():
    now = datetime(2026, 9, 17, tzinfo=timezone.utc)
    old = (now - timedelta(hours=48)).isoformat()
    tasks = [{"id": "1.1", "title": "T", "status": "active", "model": "claude", "claimed_utc": old}]
    stale = stale_active_claims(tasks, now=now, threshold_hours=24)
    assert len(stale) == 1
    assert stale[0]["id"] == "1.1"
    assert stale[0]["hours_since_claim"] == 48.0


def test_stale_active_claims_ignores_recent_claims():
    now = datetime(2026, 9, 17, tzinfo=timezone.utc)
    recent = (now - timedelta(hours=2)).isoformat()
    tasks = [{"id": "1.1", "title": "T", "status": "active", "model": "claude", "claimed_utc": recent}]
    assert stale_active_claims(tasks, now=now, threshold_hours=24) == []


def test_stale_active_claims_flags_missing_claimed_utc():
    tasks = [{"id": "1.2", "title": "T", "status": "active", "model": "codex", "claimed_utc": None}]
    stale = stale_active_claims(tasks, now=datetime.now(timezone.utc))
    assert len(stale) == 1
    assert stale[0]["reason"] == "active with no claimed_utc timestamp"


def test_stale_active_claims_ignores_non_active_tasks():
    tasks = [{"id": "1.3", "title": "T", "status": "pending", "model": "claude", "claimed_utc": None}]
    assert stale_active_claims(tasks, now=datetime.now(timezone.utc)) == []


def test_stale_active_claims_date_only_format():
    now = datetime(2026, 9, 20, tzinfo=timezone.utc)
    tasks = [{"id": "1.4", "title": "T", "status": "active", "model": "claude", "claimed_utc": "2026-09-15"}]
    stale = stale_active_claims(tasks, now=now, threshold_hours=24)
    assert len(stale) == 1


# --- Module graph SVG rendering -------------------------------------------

def test_make_module_graph_figure_produces_svg_with_nodes_and_edges():
    import sys
    sys.path.insert(0, str(Path(__file__).parent))
    from app import make_module_graph_figure

    modules = {
        "nodes": [{"id": "R/core.R", "kind": "r"}, {"id": "inst/shiny/mod_x.R", "kind": "shiny"}],
        "edges": [{"source": "inst/shiny/mod_x.R", "target": "R/core.R", "kind": "call"}],
    }
    result = make_module_graph_figure(modules)
    assert result is not None
    svg, width, height = result
    assert svg.startswith("<svg")
    assert "core.R" in svg
    assert "mod_x.R" in svg
    assert width > 0 and height > 0


def test_make_module_graph_figure_handles_empty_modules():
    import sys
    sys.path.insert(0, str(Path(__file__).parent))
    from app import make_module_graph_figure

    assert make_module_graph_figure({"nodes": [], "edges": []}) is None


def test_module_control_records_join_tasks_issues_and_recommendations():
    modules = {
        "nodes": [
            {"id": "R/analysis_tiled.R", "kind": "r"},
            {"id": "R/untracked.R", "kind": "r"},
        ],
        "module_tree": {
            "analysis": [{"rel_path": "R/analysis_tiled.R"}, {"rel_path": "R/untracked.R"}],
        },
    }
    tasks = [{
        "id": "1.4", "title": "Tiled engine", "status": "pending", "files": ["R/analysis_tiled.R"],
    }]
    issues = [{
        "id": "ISS-1", "status": "active", "where": "R/analysis_tiled.R", "title": "Duplicate reads",
    }]

    records = module_control_records(modules, tasks, issues)
    tiled = next(record for record in records if record["path"] == "R/analysis_tiled.R")
    assert tiled["status"] == "pending"
    assert tiled["open_task_count"] == 1
    assert tiled["open_issue_count"] == 1
    assert tiled["recommendations"]
