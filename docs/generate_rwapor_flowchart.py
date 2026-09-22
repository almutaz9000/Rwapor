from __future__ import annotations

import html
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DASHBOARD = REPO / "agent-workflow" / "dashboard"
sys.path.insert(0, str(DASHBOARD))
import data  # noqa: E402

OUTPUT = REPO / "docs" / "rwapor-module-flowchart.html"
SVG_OUTPUT = REPO / "docs" / "rwapor-module-flowchart.svg"

GROUPS = [
    ("Shiny app (inst/shiny)", [
        "inst/shiny/app.R", "inst/shiny/mod_aoi.R", "inst/shiny/mod_download.R",
        "inst/shiny/mod_visualisation.R", "inst/shiny/mod_dual_map.R",
        "inst/shiny/mod_analysis.R", "inst/shiny/mod_timeseries.R",
        "inst/shiny/mod_monitoring.R", "inst/shiny/utils_shiny.R",
        "inst/shiny/monitoring_helpers.R", "inst/shiny/mod_analysis_ui_body.R",
        "inst/shiny/mod_analysis_ui_sidebar.R",
    ]),
    ("API & metadata", [
        "R/api_client.R", "R/metadata.R", "R/wapor_metadata_cache.R", "R/wapor_res_key.R",
    ]),
    ("Planning & download", [
        "R/plan_wapor_time_slices.R", "R/seasonal_download.R", "R/interval_helpers.R",
    ]),
    ("Geospatial access", [
        "R/wapor_cog.R", "R/gdal_config.R", "R/wapor_map.R", "R/wapor_ts.R",
        "R/unit_convertor.R", "R/utils.R",
    ]),
    ("Analysis engine", [
        "R/analysis.R", "R/analysis_engine.R", "R/analysis_tiled.R", "R/analysis_indicators.R",
        "R/analysis_registry.R", "R/analysis_utils.R", "R/analysis_validation.R",
        "R/indicators_math.R", "R/crop_defaults.R", "R/anomaly.R",
    ]),
    ("Monitoring & support", [
        "R/wapor_monitoring.R", "R/rwapor_favorites.R", "R/viz.R", "R/run_dashboard.R", "R/diagnose.R",
    ]),
]

GROUP_COLORS = {
    "Shiny app (inst/shiny)": ("#f8f1e5", "#a78b6f"),
    "API & metadata": ("#f5eee2", "#9c876d"),
    "Planning & download": ("#f8f0df", "#a98e63"),
    "Geospatial access": ("#f2eee7", "#8f8579"),
    "Analysis engine": ("#f4ece5", "#9b806e"),
    "Monitoring & support": ("#f3eee9", "#96867b"),
}


def group_for(path: str) -> str:
    for group, members in GROUPS:
        if path in members:
            return group
    return "Other"


def label(path: str) -> str:
    return Path(path).name


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def make_svg(inventory: dict) -> tuple[str, int, int]:
    known = {n["id"] for n in inventory["nodes"]}
    nodes = [path for _, members in GROUPS for path in members if path in known]
    edges = [
        e for e in inventory["edges"]
        if e["kind"] in {"call", "source"}
        and e["source"] in known and e["target"] in known
        and e["source"] != e["target"]
    ]

    # Keep the diagram readable while preserving all cross-boundary dependencies.
    # Within a group, show only edges touching a central or entry-point file.
    central = {
        "inst/shiny/app.R", "inst/shiny/mod_analysis.R", "inst/shiny/mod_download.R",
        "inst/shiny/mod_monitoring.R", "R/api_client.R", "R/wapor_map.R", "R/wapor_ts.R",
        "R/seasonal_download.R", "R/analysis_engine.R", "R/analysis_tiled.R",
        "R/wapor_monitoring.R", "R/utils.R",
    }
    visible_edges = []
    seen = set()
    for e in edges:
        a, b = e["source"], e["target"]
        if group_for(a) != group_for(b) or a in central or b in central:
            key = (a, b, e["kind"])
            if key not in seen:
                visible_edges.append(e)
                seen.add(key)

    width = 1900
    group_x = {
        "Shiny app (inst/shiny)": 35,
        "API & metadata": 670,
        "Planning & download": 670,
        "Geospatial access": 1255,
        "Analysis engine": 35,
        "Monitoring & support": 1255,
    }
    group_y = {
        "Shiny app (inst/shiny)": 55,
        "API & metadata": 55,
        "Planning & download": 380,
        "Geospatial access": 55,
        "Analysis engine": 640,
        "Monitoring & support": 780,
    }
    group_w = {
        "Shiny app (inst/shiny)": 550,
        "API & metadata": 530,
        "Planning & download": 530,
        "Geospatial access": 610,
        "Analysis engine": 1160,
        "Monitoring & support": 610,
    }
    positions: dict[str, tuple[float, float, float, float]] = {}
    group_boxes = []

    for group, members in GROUPS:
        members = [m for m in members if m in known]
        x, y = group_x[group], group_y[group]
        w = group_w[group]
        cols = 2 if len(members) <= 8 else 3
        node_w, node_h = 180, 44
        gap_x, gap_y = 24, 30
        rows = (len(members) + cols - 1) // cols
        h = 58 + rows * node_h + max(0, rows - 1) * gap_y + 28
        group_boxes.append((group, x, y, w, h))
        for i, member in enumerate(members):
            col, row = i % cols, i // cols
            nx = x + 30 + col * (node_w + gap_x)
            ny = y + 40 + row * (node_h + gap_y)
            positions[member] = (nx, ny, node_w, node_h)

    # Expand the lower analysis group around its actual contents.
    max_bottom = max(y + h for _, _, y, _, h in group_boxes)
    svg_h = max(1250, max_bottom + 90)

    def anchor(path: str, target: str) -> tuple[float, float]:
        x, y, w, h = positions[path]
        tx, ty, tw, th = positions[target]
        sx, sy = x + w / 2, y + h / 2
        ex, ey = tx + tw / 2, ty + th / 2
        if abs(ex - sx) >= abs(ey - sy):
            return (x + (w if ex > sx else 0), sy)
        return (sx, y + (h if ey > sy else 0))

    parts = [
        f'<svg viewBox="0 0 {width} {svg_h}" role="img" aria-label="Rwapor module dependency flowchart">',
        '<defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#85796d"/></marker><pattern id="grid" width="32" height="32" patternUnits="userSpaceOnUse"><path d="M32 0H0V32" fill="none" stroke="#eee8df" stroke-width="1"/></pattern></defs>',
        f'<rect width="{width}" height="{svg_h}" fill="#fbfaf7"/><rect width="{width}" height="{svg_h}" fill="url(#grid)"/>',
    ]

    # Edges are drawn first so node boxes mask crossings, matching the reference.
    for e in visible_edges:
        if e["source"] not in positions or e["target"] not in positions:
            continue
        sx, sy = anchor(e["source"], e["target"])
        ex, ey = anchor(e["target"], e["source"])
        dashed = ' stroke-dasharray="4,4"' if e["kind"] == "source" else ""
        if abs(ex - sx) >= abs(ey - sy):
            mx = (sx + ex) / 2
            path = f"M {sx:.1f},{sy:.1f} C {mx:.1f},{sy:.1f} {mx:.1f},{ey:.1f} {ex:.1f},{ey:.1f}"
        else:
            my = (sy + ey) / 2
            path = f"M {sx:.1f},{sy:.1f} C {sx:.1f},{my:.1f} {ex:.1f},{my:.1f} {ex:.1f},{ey:.1f}"
        parts.append(f'<path d="{path}" fill="none" stroke="#a79b8e" stroke-width="1.25" marker-end="url(#arrow)"{dashed}/>')

    for group, x, y, w, h in group_boxes:
        fill, stroke = GROUP_COLORS[group]
        parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{fill}" fill-opacity="0.32" stroke="{stroke}" stroke-width="1.25"/>')
        parts.append(f'<text x="{x + w/2:.1f}" y="{y + 24}" text-anchor="middle" class="group-title">{esc(group)}</text>')

    for path, (x, y, w, h) in positions.items():
        group = group_for(path)
        fill, stroke = GROUP_COLORS[group]
        parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="5" fill="#f7efe2" stroke="{stroke}" stroke-width="1.1"/>')
        parts.append(f'<text x="{x + w/2:.1f}" y="{y + 27}" text-anchor="middle" class="node-label">{esc(label(path))}</text>')

    parts.append('<text x="35" y="%d" class="note">Solid edges = resolved function calls; dashed edges = literal source() relationships. Weak filename references are omitted.</text>' % (svg_h - 38))
    parts.append('</svg>')
    return "\n".join(parts), len(nodes), len(visible_edges)


def main() -> None:
    inventory = data.module_inventory()
    svg, node_count, edge_count = make_svg(inventory)
    html_doc = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Rwapor module flowchart</title>
<style>
  :root {{ color-scheme: light; }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: #f3f1ed; color: #51483f; font-family: Inter, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif; }}
  main {{ max-width: 2000px; margin: 0 auto; padding: 28px 32px 36px; }}
  header {{ display: flex; justify-content: space-between; align-items: end; gap: 24px; margin-bottom: 18px; }}
  h1 {{ margin: 0; font-size: 25px; font-weight: 500; letter-spacing: -0.02em; }}
  .subtitle {{ margin: 7px 0 0; color: #81766b; font-size: 13px; }}
  .meta {{ color: #958a80; font-size: 12px; text-align: right; white-space: nowrap; }}
  .canvas {{ overflow: auto; background: #fbfaf7; border: 1px solid #d7cec3; border-radius: 12px; box-shadow: 0 8px 24px rgba(85, 70, 54, .07); }}
  svg {{ display: block; width: 100%; min-width: 1100px; height: auto; }}
  .group-title {{ font-size: 16px; fill: #685b50; font-weight: 500; }}
  .node-label {{ font-size: 12px; fill: #5f554d; }}
  .note {{ font-size: 11px; fill: #92867a; }}
  .cards {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-top: 16px; }}
  .card {{ background: #fbfaf7; border: 1px solid #d7cec3; border-radius: 9px; padding: 14px 16px; }}
  .card h2 {{ margin: 0 0 7px; font-size: 13px; font-weight: 600; color: #675b50; }}
  .card p {{ margin: 0; color: #81766b; font-size: 12px; line-height: 1.5; }}
  footer {{ margin-top: 14px; color: #9a8e82; font-size: 11px; }}
  @media (max-width: 800px) {{ main {{ padding: 16px; }} header {{ display: block; }} .meta {{ text-align: left; margin-top: 8px; }} .cards {{ grid-template-columns: 1fr; }} }}
</style>
</head>
<body>
<main>
<header>
  <div><h1>Rwapor module flowchart</h1><p class="subtitle">Source-grounded dependency map for package code, Shiny modules, and processing layers</p></div>
  <div class="meta">{node_count} mapped modules · {edge_count} displayed strong edges<br>Generated from current source inventory</div>
</header>
<section class="canvas">{svg}</section>
<section class="cards">
  <article class="card"><h2>Package core</h2><p>API and metadata discovery feed temporal planning, raster access, and the seasonal analysis engine.</p></article>
  <article class="card"><h2>Analysis path</h2><p>Seasonal, tiled, indicator, validation, crop, and anomaly modules converge around the analysis engine.</p></article>
  <article class="card"><h2>User interface</h2><p>The Shiny application connects AOI, download, dual-map, visualisation, analysis, time-series, and monitoring workflows to package functions.</p></article>
</section>
<footer>Rwapor repository review artifact. The diagram reflects resolvable calls and literal source relationships found in R/ and inst/shiny/; weak filename-only references are intentionally excluded.</footer>
</main>
</body>
</html>
'''
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(html_doc, encoding="utf-8")
    SVG_OUTPUT.write_text(svg, encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "svg_output": str(SVG_OUTPUT), "nodes": node_count, "edges": edge_count, "bytes": OUTPUT.stat().st_size}))


if __name__ == "__main__":
    main()
