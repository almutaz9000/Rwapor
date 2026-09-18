"""Rwapor Control Room: read-only, live maintainer dashboard.

This app is separate from the package's Shiny application. It reads the
canonical agent-workflow ledger and repository files on every rerun; it never
edits tasks, issues, or source code.
"""

from __future__ import annotations

import html
import json
from pathlib import Path

import pandas as pd
import streamlit as st

try:
    from streamlit_autorefresh import st_autorefresh
except ImportError:  # timed refresh is optional; manual refresh still works
    st_autorefresh = None

from data import build_snapshot, compute_module_completion, build_mermaid_diagram, mermaid_html

STATUS_ORDER = ["active", "pending", "blocked", "done"]
STATUS_COLORS = {"active": "#087f5b", "pending": "#b7791f", "blocked": "#c53030", "done": "#2f855a"}
PRIORITY_COLORS = {"critical": "#c53030", "high": "#dd6b20", "medium": "#b7791f", "low": "#718096"}

st.set_page_config(page_title="Rwapor Control Room", page_icon="🛰️", layout="wide")
st.markdown(
    """
    <style>
    .pill {display:inline-block;padding:2px 8px;border-radius:999px;font:600 11px monospace;margin-left:4px}
    .card {padding:12px 14px;border:1px solid rgba(120,120,120,.25);border-radius:8px;margin:6px 0}
    .muted {color:#718096;font-size:12px}
    .decision {border-left:4px solid #c53030;background:rgba(197,48,48,.08);padding:12px 14px;border-radius:6px;margin:8px 0}
    </style>
    """, unsafe_allow_html=True,
)


def badge(value: str, color: str) -> str:
    return f'<span class="pill" style="color:{color};background:{color}18;border:1px solid {color}55">{html.escape(value)}</span>'


def task_frame(tasks: list[dict]) -> pd.DataFrame:
    if not tasks:
        return pd.DataFrame(columns=["id", "title", "status", "priority", "model", "notes", "files"])
    frame = pd.DataFrame(tasks)
    for column in ["id", "title", "status", "priority", "model", "notes", "files"]:
        if column not in frame:
            frame[column] = None
    frame["model"] = frame["model"].fillna("unassigned")
    frame["files"] = frame["files"].apply(lambda values: ", ".join(values or []))
    return frame


def make_module_graph_figure(modules: dict):
    """Layered flowchart SVG, styled after the reference lineage-diagram look.

    Pure inline SVG built with networkx layering only -- no Mermaid, no CDN
    fetch, no matplotlib/graphviz binary dependency, so it renders on any
    network including ones that block cdn.jsdelivr.net. Layer 0 = files with
    no incoming call/source edges (entry points); each downstream file sits
    one column to the right of its earliest caller, following the same
    left-to-right script -> table -> view lineage shape as the reference.
    """
    import networkx as nx

    strong_kinds = {"call", "source"}
    graph = nx.DiGraph()
    for node in modules["nodes"]:
        graph.add_node(node["id"], kind=node.get("kind", "r"))
    for edge in modules["edges"]:
        if edge["source"] in graph and edge["target"] in graph and edge["source"] != edge["target"]:
            kind = edge.get("kind", "reference")
            if graph.has_edge(edge["source"], edge["target"]):
                if kind in strong_kinds:
                    graph[edge["source"]][edge["target"]]["kind"] = kind
            else:
                graph.add_edge(edge["source"], edge["target"], kind=kind)

    if graph.number_of_nodes() == 0:
        return None

    strong = nx.DiGraph()
    strong.add_nodes_from(graph.nodes)
    strong.add_edges_from((u, v) for u, v, d in graph.edges(data=True) if d.get("kind") in strong_kinds)

    condensed = nx.condensation(strong)
    layer_of_scc = {n: 0 for n in condensed.nodes}
    for scc in nx.topological_sort(condensed):
        preds = list(condensed.predecessors(scc))
        if preds:
            layer_of_scc[scc] = max(layer_of_scc[p] for p in preds) + 1
    member_scc = condensed.graph["mapping"]
    layer = {node: layer_of_scc[member_scc[node]] for node in graph.nodes}

    by_layer: dict[int, list[str]] = {}
    for node, ly in layer.items():
        by_layer.setdefault(ly, []).append(node)
    for ly in by_layer:
        by_layer[ly].sort(key=lambda n: (-graph.out_degree(n), n))

    box_w, box_h = 230, 46
    col_gap, row_gap = 130, 26
    margin = 30

    pos: dict[str, tuple[float, float]] = {}
    for ly in sorted(by_layer):
        x = margin + ly * (box_w + col_gap)
        for i, node in enumerate(by_layer[ly]):
            y = margin + i * (box_h + row_gap)
            pos[node] = (x, y)

    width = margin * 2 + (max(by_layer) + 1) * (box_w + col_gap) - col_gap
    height = margin * 2 + max(len(v) for v in by_layer.values()) * (box_h + row_gap) - row_gap
    height = max(height, 200)

    colors = {
        "shiny": ("#dd6b20", "#fffaf0"),  # orange, matches Shiny module accent used elsewhere in this app
        "r": ("#2f855a", "#f0fff4"),      # green, matches the reference diagram's script/table palette
    }
    edge_style = {
        "call": ("#2f855a", "0"),
        "source": ("#2c3e50", "0"),
        "reference": ("#a0aec0", "4,3"),
    }

    def escape(text: str) -> str:
        return html.escape(text)

    svg_parts = [
        f'<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}" '
        f'xmlns="http://www.w3.org/2000/svg" font-family="Segoe UI, Arial, sans-serif">',
        '<defs>',
        '<marker id="arrow-call" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">'
        '<path d="M0,0 L8,4 L0,8 Z" fill="#2f855a"/></marker>',
        '<marker id="arrow-source" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">'
        '<path d="M0,0 L8,4 L0,8 Z" fill="#2c3e50"/></marker>',
        '<marker id="arrow-reference" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">'
        '<path d="M0,0 L8,4 L0,8 Z" fill="#a0aec0"/></marker>',
        '</defs>',
    ]

    # Edges first so boxes draw on top.
    for source, target, data in graph.edges(data=True):
        kind = data.get("kind", "reference")
        color, dash = edge_style.get(kind, edge_style["reference"])
        x0, y0 = pos[source]
        x1, y1 = pos[target]
        start_x, start_y = x0 + box_w, y0 + box_h / 2
        end_x, end_y = x1, y1 + box_h / 2
        mid_x = (start_x + end_x) / 2
        path = f"M{start_x},{start_y} C{mid_x},{start_y} {mid_x},{end_y} {end_x},{end_y}"
        dash_attr = f' stroke-dasharray="{dash}"' if dash != "0" else ""
        svg_parts.append(
            f'<path d="{path}" fill="none" stroke="{color}" stroke-width="1.4"{dash_attr} '
            f'marker-end="url(#arrow-{kind})" opacity="0.85"/>'
        )

    for node, (x, y) in pos.items():
        kind = graph.nodes[node].get("kind", "r")
        stroke, fill = colors.get(kind, colors["r"])
        label = Path(node).name
        degree = graph.in_degree(node) + graph.out_degree(node)
        svg_parts.append(
            f'<g><title>{escape(node)} (in+out: {degree})</title>'
            f'<rect x="{x}" y="{y}" width="{box_w}" height="{box_h}" rx="4" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="1.4"/>'
            f'<rect x="{x}" y="{y}" width="4" height="{box_h}" fill="{stroke}"/>'
            f'<text x="{x + 14}" y="{y + box_h / 2 + 4}" font-size="11.5" fill="#1a202c">{escape(label)}</text>'
            f'</g>'
        )

    svg_parts.append('</svg>')
    return "\n".join(svg_parts), width, height


# Sidebar controls are before loading so a rerun always gets a fresh snapshot.
st.sidebar.header("Control room")
refresh_seconds = st.sidebar.selectbox("Auto-refresh", ["Off", 15, 30, 60], index=2)
if refresh_seconds != "Off" and st_autorefresh:
    st_autorefresh(interval=int(refresh_seconds) * 1000, key="control-room-refresh")
elif refresh_seconds != "Off" and not st_autorefresh:
    st.sidebar.info("Install streamlit-autorefresh to enable timed refresh. Manual refresh remains available.")
if st.sidebar.button("Refresh now", use_container_width=True):
    st.rerun()
st.sidebar.caption("Read-only monitor. Updates come from the canonical agent-workflow files and the repository working tree.")

# Module connection map controls in sidebar
st.sidebar.divider()
st.sidebar.subheader("Module map options")
show_mermaid = st.sidebar.checkbox("Show Mermaid overview (CDN)", value=True,
                                    help="Requires internet for mermaid.js CDN. Uncheck if blocked.")
show_detailed = st.sidebar.checkbox("Show detailed file-level map", value=True)
show_reference_edges = st.sidebar.checkbox("Show weak reference edges", value=False,
                                            help="Weak textual mention edges (very noisy). Keep off for clarity.")

snapshot = build_snapshot()
board = snapshot["board"]
tasks = task_frame(board.get("tasks", []))
issues = pd.DataFrame(board.get("issues", []))
sessions = pd.DataFrame(board.get("sessions", []))
counts = snapshot["task_counts"]

st.title("🛰️ Rwapor Control Room")
st.caption(f"Live coordination view · loaded {snapshot['loaded_utc']} · board updated {board.get('updated_utc', 'unknown')}")

# Preflight and health are deliberately first: operators see trust signals before detail.
git = snapshot["git"]
health_cols = st.columns(5)
health_cols[0].metric("Active work", counts["active"])
health_cols[1].metric("Pending", counts["pending"])
health_cols[2].metric("Blocked", counts["blocked"])
health_cols[3].metric("Finished", counts["done"])
health_cols[4].metric("Working-tree changes", git["changed"], delta=f"{git['untracked']} untracked", delta_color="inverse")

with st.expander("Preflight and data freshness", expanded=True):
    for warning in snapshot["warnings"]:
        st.warning(f"{warning['title']}: {warning['detail']} ({warning['source']})")
    c1, c2 = st.columns(2)
    with c1:
        st.write(f"**Branch:** `{git['branch']}`")
        st.write(f"**HEAD:** `{git['head']}`")
        st.write(f"**Known models:** {', '.join(board.get('known_models', []))}")
    with c2:
        freshness = pd.DataFrame(snapshot["source_files"])
        st.dataframe(freshness, hide_index=True, use_container_width=True)

# Decision queue is prominent even when it is empty.
st.subheader("Decisions requiring maintainer input")
decisions = snapshot["decisions"]
if decisions:
    for decision in decisions:
        priority = str(decision.get("priority", "warning")).lower()
        color = PRIORITY_COLORS.get(priority, "#c53030")
        st.markdown(
            f'<div class="decision"><b>{html.escape(decision["id"])}</b> '
            f'{badge(priority, color)}<br><b>{html.escape(decision["title"])}</b>'
            f'<div class="muted">{html.escape(decision["detail"])}<br>Source: {html.escape(decision["source"])}</div></div>',
            unsafe_allow_html=True,
        )
else:
    st.success("No unresolved decision records were found in the board or workflow logs.")

st.divider()

# Main operator view: focus, evidence, and the connections behind the work.
tab_focus, tab_issues, tab_modules, tab_explorer, tab_agents, tab_verify, tab_history = st.tabs([
    "Focus and work queue", "Issues and fixes", "Module connections", "Module Explorer", "Agents and models", "Claim verification", "History and evidence",
])

with tab_focus:
    left, right = st.columns([1, 1])
    with left:
        st.subheader("Work by priority")
        if tasks.empty:
            st.info("No tasks recorded.")
        else:
            focus = tasks[tasks["status"].isin(["active", "pending", "blocked"])].copy()
            if focus.empty:
                st.success("No open tasks. All board tasks are finished.")
            else:
                st.dataframe(
                    focus[["id", "title", "status", "priority", "model", "updated_utc"]].sort_values(["status", "priority"]),
                    hide_index=True, use_container_width=True, height=330,
                    column_config={"status": st.column_config.TextColumn("State"), "updated_utc": "Last update"},
                )
    with right:
        st.subheader("Pending, proposed fixes, and finished evidence")
        workflow = snapshot["workflow"]
        st.write(f"**Pending workflow entries:** {len(workflow['pending_markdown'])}")
        st.write(f"**Recently completed entries:** {len(workflow['completed_markdown'])}")
        for item in (workflow["pending_markdown"] + workflow["completed_markdown"][:4]):
            state = "pending" if item in workflow["pending_markdown"] else "finished"
            color = "#b7791f" if state == "pending" else "#2f855a"
            with st.expander(f"{state.upper()} · {item.get('title', '')}"):
                st.write(item.get("detail", ""))

    st.subheader("Task detail and proposed solution")
    if not tasks.empty:
        selected_id = st.selectbox("Select a task", tasks["id"].tolist())
        selected = next(task for task in board.get("tasks", []) if task.get("id") == selected_id)
        st.write(f"**{selected.get('title', '')}** {badge(selected.get('status', 'unknown'), STATUS_COLORS.get(selected.get('status', ''), '#718096'))}", unsafe_allow_html=True)
        st.write(selected.get("notes") or "No notes recorded.")
        st.caption("Files: " + (", ".join(selected.get("files") or []) or "none"))

with tab_issues:
    st.subheader("Open issues, warnings, and resolved fixes")
    issue_state = st.multiselect("Show issue state", ["open", "resolved"], default=["open", "resolved"])
    if issues.empty:
        st.info("No issues recorded in agents-board.json.")
    else:
        for issue in issues.to_dict("records"):
            if issue.get("status") not in issue_state:
                continue
            color = "#c53030" if issue.get("status") == "open" else "#2f855a"
            with st.expander(f"{issue.get('id')} · {issue.get('title')} · {issue.get('status')}"):
                st.write(issue.get("summary", ""))
                st.caption(f"Where: {issue.get('where', 'not recorded')} · Owner: {issue.get('owner', issue.get('model', 'unassigned'))}")
        st.caption("The dashboard does not mark issues resolved. Update the canonical board and issues-log.md through the normal workflow.")

with tab_modules:
    st.subheader("R and Shiny module connection map")

    # Mermaid diagram (like waporbox) - completion % colored
    if show_mermaid:
        st.caption("Nodes colored by completion % from task board. Green = done, yellow = in progress, red = not started. Solid arrows = module dependencies.")
        tasks = board.get("tasks", [])
        module_pct = compute_module_completion(tasks)
        mermaid_diag = build_mermaid_diagram(module_pct)
        mermaid_html_content = mermaid_html(mermaid_diag, height=500)
        
        # Check if CDN might be blocked - provide fallback note
        st.components.v1.html(mermaid_html_content, height=520, scrolling=True)
        
        # Fallback: show as code if mermaid fails to render
        with st.expander("Raw mermaid source (copy to https://mermaid.live if diagram above is empty)"):
            st.code(mermaid_diag)
        
        st.info("💡 If the diagram above is empty, your network may block the mermaid.js CDN (cdn.jsdelivr.net). Use the raw source above at mermaid.live, or uncheck 'Show Mermaid overview' in the sidebar.")
        st.divider()

    # Existing detailed SVG diagram
    if show_detailed:
        st.subheader("Detailed file-level connection map")
        
        # Filter edges based on sidebar option
        modules = snapshot["modules"]
        if not show_reference_edges:
            # Create filtered copy with only call and source edges
            filtered_modules = {
                "nodes": modules["nodes"],
                "edges": [e for e in modules["edges"] if e["kind"] in ("call", "source")]
            }
        else:
            filtered_modules = modules
            
        st.caption(
            "Solid green arrows are resolved function-call edges; solid dark arrows are "
            "source() references; " + ("dotted grey arrows are weaker textual mentions. " if show_reference_edges else "weak reference edges hidden (enable in sidebar). ")
            + "Files flow left-to-right from entry points to what they call. "
            "Orange = Shiny module (inst/shiny/), green = core R package file (R/). "
            "The table remains the authoritative evidence when the graph is dense."
        )
        result = make_module_graph_figure(filtered_modules)
        if result is None:
            st.info("No module nodes found.")
        else:
            svg_markup, svg_width, svg_height = result
            st.components.v1.html(
                f'<div style="overflow:auto; border:1px solid #e2e8f0; border-radius:6px; padding:8px;">{svg_markup}</div>',
                height=min(svg_height + 40, 700), scrolling=True,
            )
        # Edge table also filtered
        edge_frame = pd.DataFrame(filtered_modules["edges"])
        st.dataframe(edge_frame if not edge_frame.empty else pd.DataFrame(columns=["source", "target", "kind"]), hide_index=True, use_container_width=True)

with tab_explorer:
    st.subheader("Interactive Module Explorer")
    st.caption("Live AST scan of R/ and inst/shiny/. Select a module group, then a file to see its functions and methods.")

    module_tree = snapshot["modules"].get("module_tree", {})
    if not module_tree:
        st.error("No module tree data. Check R/ and inst/shiny/ directories.")
    else:
        raw_groups = sorted(module_tree.keys(), key=lambda g: (g != "__root__", g))
        if "__root__" in raw_groups:
            raw_groups = ["__root__"] + [g for g in raw_groups if g != "__root__"]

        glabels = [f"{g} ({len(module_tree[g])} files)" for g in raw_groups]
        l2r = dict(zip(glabels, raw_groups))

        sel_gl = st.selectbox("Module group", glabels, index=0)
        sel_g = l2r[sel_gl]
        files = module_tree.get(sel_g, [])

        sc1, sc2, sc3, sc4 = st.columns(4)
        sc1.metric("Files", len(files))
        sc2.metric("Total lines", sum(f["line_count"] for f in files))
        sc3.metric("Public functions", sum(len(f["public_functions"]) for f in files))
        sc4.metric("Private functions", sum(len(f["private_functions"]) for f in files))

        if not files:
            st.warning("No .R files in this group.")
        else:
            fopts = [f["rel_path"] for f in files]
            sfp = st.selectbox("File", fopts)
            sf = next((f for f in files if f["rel_path"] == sfp), None)
            if sf:
                fc1, fc2, fc3 = st.columns(3)
                fc1.metric("Lines", sf["line_count"])
                fc2.metric("Public fns", len(sf["public_functions"]))
                fc3.metric("Private fns", len(sf["private_functions"]))

                show_priv = st.checkbox("Show private (prefix _)", value=False)

                if sf["exported"]:
                    st.markdown("#### Exported functions")
                    for fn in sorted(sf["exported"]):
                        st.markdown(f"- `{fn}`")

                if sf["public_functions"]:
                    st.markdown("#### Public functions")
                    for fn in sorted(sf["public_functions"]):
                        if fn not in sf["exported"]:
                            st.markdown(f"- `{fn}`")

                if show_priv and sf["private_functions"]:
                    st.markdown("#### Private functions")
                    for fn in sorted(sf["private_functions"]):
                        st.markdown(f"- `{fn}`")

                if sf["methods"]:
                    st.markdown("#### S3/S4 methods")
                    for fn in sorted(sf["methods"]):
                        st.markdown(f"- `{fn}`")

                with st.expander("All files in this group"):
                    for fi in files:
                        mk = ">> " if fi["rel_path"] == sfp else "   "
                        st.markdown(
                            f"`{mk}{fi['rel_path']}` - "
                            f"{fi['line_count']} lines, "
                            f"{len(fi['public_functions'])} pub fns, "
                            f"{len(fi['private_functions'])} priv fns"
                        )

with tab_agents:
    st.subheader("Agents and model workload")
    if tasks.empty:
        st.info("No model activity recorded.")
    else:
        workload = tasks.groupby(["model", "status"], dropna=False).size().reset_index(name="tasks")
        st.bar_chart(workload.pivot(index="model", columns="status", values="tasks").fillna(0), stack=False)
        st.dataframe(workload.sort_values(["model", "status"]), hide_index=True, use_container_width=True)
    st.subheader("Active claims")
    active = tasks[tasks["status"] == "active"] if not tasks.empty else tasks
    st.dataframe(active[["id", "title", "model", "priority", "notes"]], hide_index=True, use_container_width=True) if not active.empty else st.info("No active claims.")

with tab_verify:
    st.subheader("Automated claim-vs-code verification")
    st.caption(
        "Extracts identifier-like tokens (function names, backticked terms, snake_case "
        "names) from each task's title/notes and checks whether the files that task "
        "lists actually contain them. Catches the exact overclaiming pattern found "
        "manually in the 2026-09-17 re-review (7 of 43 tasks were already done but "
        "still marked pending)."
    )
    VERDICT_COLORS = {
        "verified": "#2f855a", "partial": "#dd6b20", "unverified": "#c53030",
        "not_checkable": "#718096", "no_files_listed": "#718096", "files_missing": "#c53030",
    }
    claims = pd.DataFrame(snapshot["claims"])
    if claims.empty:
        st.info("No tasks to verify.")
    else:
        verdict_counts = claims["verdict"].value_counts()
        vcols = st.columns(len(VERDICT_COLORS))
        for i, (verdict, color) in enumerate(VERDICT_COLORS.items()):
            vcols[i].markdown(
                f'<div class="card"><b>{verdict}</b><br>'
                f'<span style="font-size:22px">{int(verdict_counts.get(verdict, 0))}</span></div>',
                unsafe_allow_html=True,
            )
        flagged = st.checkbox("Show only claims needing attention (partial / unverified / files_missing)", value=True)
        show = claims[claims["verdict"].isin(["partial", "unverified", "files_missing"])] if flagged else claims
        if show.empty:
            st.success("No flagged claims. Every checkable task claim is backed by its listed files.")
        else:
            for row in show.to_dict("records"):
                color = VERDICT_COLORS.get(row["verdict"], "#718096")
                with st.expander(f"{row['id']} · {row['title']} · {row['verdict']}", expanded=False):
                    st.markdown(badge(row["verdict"], color), unsafe_allow_html=True)
                    st.markdown(f"Status: `{row['status']}` · Model: `{row['model']}`")
                    st.write(f"**Matched tokens** ({len(row['tokens_matched'])}): {', '.join(row['tokens_matched']) or 'none'}")
                    st.write(f"**Missing tokens** ({len(row['tokens_missing'])}): {', '.join(row['tokens_missing']) or 'none'}")
                    if row["files_missing"]:
                        st.warning(f"Listed files that don't exist: {', '.join(row['files_missing'])}")
        st.caption("Verdicts: verified = all tokens found in listed files · partial = some found · unverified = none found · "
                   "not_checkable = no extractable tokens in the claim text · files_missing = listed file(s) don't exist · "
                   "no_files_listed = task has no files array to check against.")

    st.divider()
    st.subheader("Stale active claims")
    st.caption("Tasks marked \"active\" for more than 24h with no status change, or active with no claimed_utc -- likely an agent that crashed or never closed out.")
    stale = pd.DataFrame(snapshot["stale_claims"])
    if stale.empty:
        st.success("No stale active claims.")
    else:
        st.dataframe(stale, hide_index=True, use_container_width=True)

with tab_history:
    st.subheader("Sessions, changes, and machine-readable export")
    if not sessions.empty:
        show = sessions.copy()
        columns = [c for c in ["date", "label", "model", "summary", "tests", "commit"] if c in show.columns]
        st.dataframe(show[columns].sort_values("date", ascending=False), hide_index=True, use_container_width=True)
    else:
        st.info("No sessions recorded.")
    st.download_button("Download current board JSON", json.dumps(board, indent=2), file_name="agents-board.json", mime="application/json")
    st.download_button("Download dashboard snapshot JSON", json.dumps(snapshot, indent=2, default=str), file_name="rwapor-control-room-snapshot.json", mime="application/json")

st.divider()
st.caption("Sources: agents-board.json, task-status.md, issues-log.md, session-brief.md, change-log.md, project-memory.md, R/, inst/shiny/, and git status. This is a monitoring view, not a live process monitor.")
