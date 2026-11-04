"""Render inst/spec/README.md from inst/spec/indicators.yaml.

Run from the repository root:

    python scripts/render_indicator_catalogue.py
"""
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
YAML_PATH = ROOT / "inst" / "spec" / "indicators.yaml"
OUT_PATH = ROOT / "inst" / "spec" / "README.md"

CATEGORY_LABELS = {
    "evapotranspiration": "Evapotranspiration",
    "water_supply": "Water supply",
    "irrigation_performance": "Irrigation performance",
    "biomass_yield": "Biomass and yield",
    "water_productivity": "Water productivity",
}


def main() -> None:
    spec = yaml.safe_load(YAML_PATH.read_text(encoding="utf-8"))
    inds = spec["indicators"]
    n = len(inds)
    lines = []
    a = lines.append

    a("# Seasonal analysis indicators")
    a("")
    a("This page is the GitHub-readable view of the same catalogue as")
    a("[indicators.yaml](indicators.yaml). The YAML file remains the machine-readable")
    a("source of truth (synced with `wapor_list_indicator_steps()`). Edit the YAML,")
    a("then run `python scripts/render_indicator_catalogue.py` so this page stays aligned.")
    a("")
    a(f"**Package:** {spec.get('package', 'Rwapor')} {spec.get('version', '')}  ")
    a(f"**Count:** {n} built-in indicators")
    a("")
    a(spec["description"].strip())
    a("")
    a("## Notation")
    a("")
    a("- Subscript `d` is a dekad; subscript `m` is a calendar month.")
    a("- `w_d` is the season weight in [0, 1].")
    a("- `days_d` is the number of days in that dekad (usually 8 to 11).")
    a("- Division by a zero denominator is returned as NA.")
    a("- Green water, blue water, ET_rain, rainfall surplus, and NIR are summed from")
    a("  monthly layers. Do not compute them from seasonal totals.")
    a("")
    a("## Summary")
    a("")
    a("| Code | Indicator | Category | Units out |")
    a("| --- | --- | --- | --- |")
    for x in inds:
        cat = CATEGORY_LABELS.get(x["category"], x["category"])
        a(f"| `{x['id']}` | {x['label']} | {cat} | {x['units_out']} |")
    a("")
    a("## Definitions, equations, and citations")
    a("")

    for i, x in enumerate(inds, 1):
        cat = CATEGORY_LABELS.get(x["category"], x["category"])
        inputs = ", ".join(f"`{v}`" for v in x["inputs"])
        a(f"### {i}. `{x['id']}`")
        a("")
        a(f"**{x['label']}**")
        a("")
        a(f"- Category: {cat}")
        a(f"- Status: {x['status']}")
        a(f"- Equation: `{x['formula']}`")
        a(f"- Units in: `{x['units_in']}`")
        a(f"- Units out: `{x['units_out']}`")
        a(f"- Dekad rule: `{x['dekad_rule']}`")
        a(f"- Inputs: {inputs}")
        a(f"- R function: `{x['r_function']}`")
        a(f"- Python function: `{x['py_function']}`")
        a(f"- Citation: {x['citation']}")
        a("")

    a("## Machine-readable source")
    a("")
    a("```r")
    a('system.file("spec", "indicators.yaml", package = "Rwapor")')
    a("```")
    a("")

    text = "\n".join(lines)
    OUT_PATH.write_text(text, encoding="utf-8", newline="\n")
    print(f"Wrote {OUT_PATH.relative_to(ROOT)} ({n} indicators)")


if __name__ == "__main__":
    main()
