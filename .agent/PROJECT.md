---
project: Rwapor
type: R Package
updated: 2026-03-27
---

# Rwapor — Agent Project Snapshot

> Single-read context for agents. Read this instead of scanning CLAUDE.md + .agent/skills/ + git status.
> Keep this file up to date when branch, status, or skills change.

## Identity
- **Package**: Rwapor v0.1.0 — FAO WaPOR data download + seasonal analysis
- **Branch**: `version-0.9.1`
- **Entry point**: `run_wapor()` → Shiny dashboard
- **Rscript**: `/c/Program Files/R/R-4.5.2/bin/Rscript.exe`
- **Tests**: 342 PASS, 5 SKIP (live API, need `RWAPOR_RUN_LIVE_TESTS=true`)

## File Status
| Status | Files |
|---|---|
| In-development | `inst/shiny/mod_analysis.R`, `inst/shiny/mod_aoi.R`, `inst/shiny/mod_download.R` |
| Stable | All `R/*.R` core files |
| Large file | `mod_analysis.R` (~2400 lines) — use `## ---` section markers to navigate |

## Core Rules (non-negotiable)
1. `terra` only — never `raster`
2. Never edit `NAMESPACE` manually — Roxygen2-managed
3. Patch blocks only — targeted edits unless full rewrite requested
4. Run `devtools::test()` before finalizing any task
5. Grep before rename: `R/`, `tests/`, `man/`, `vignettes/`, `NAMESPACE`
6. Shiny: `NS(id)` for UI · `moduleServer(id,...)` for server · `shinyvalidate` for inputs

## Hooks (automated — do not skip or work around)
| Hook | Trigger | Action Required |
|---|---|---|
| `PostToolUseFailure(Bash)` | Any Bash command fails | Log to `.agent/skills/rwapor-developer/references/bug-log.md`: symptom, file, function, status |
| `Stop` | Session ends | (1) Code edited? → log to `prompt-history.md`. (2) Approach confirmed/rejected? → update `project-memory/references/rwapor.md` |

## Agent Team

All agents live in `~/.claude/agents/`. No project-level overrides needed.

```
wapor-agent (lead)
  ├─ wapor-r-subagent    → R/terra/Shiny    → can spawn: parallel R workers, wapor-viz, wapor-gee
  ├─ wapor-gee-subagent  → GEE/export       → can spawn: parallel tile workers, wapor-dl, wapor-viz
  ├─ wapor-dl-subagent   → DL/classify      → can spawn: parallel model workers, wapor-viz, wapor-gee
  └─ wapor-viz-subagent  → maps/plots       → can spawn: parallel figure workers, wapor-r (for data prep)
```

**Spawn threshold**: 3+ independent subtasks → spawn parallel workers.
**Escalation**: any worker can escalate back to `wapor-agent` if blocked.
**Context passing**: always pass the Active Project Context block into spawned agent prompts.

## Skills Inventory
Load with `read`. Load in parallel when possible (multiple `read` calls in one turn).

| Skill | Path | Load When |
|---|---|---|
| **Lead dev** | `.agent/skills/rwapor-developer/SKILL.md` | **Always** for any code task |
| Architecture | `.agent/skills/rwapor-developer/references/architecture.md` | Any code change |
| Bug log | `.agent/skills/rwapor-developer/references/bug-log.md` | Bug fix |
| Feature log | `.agent/skills/rwapor-developer/references/feature-log.md` | New feature |
| UI decisions | `.agent/skills/rwapor-developer/references/ui-decisions.md` | Shiny UI/UX |
| Prompt history | `.agent/skills/rwapor-developer/references/prompt-history.md` | Lost context / new session |
| R package | `.agent/skills/r-package-expert/SKILL.md` | devtools, NAMESPACE, roxygen2 |
| Shiny | `.agent/skills/shiny-developer/SKILL.md` | `inst/shiny/` module work |
| WaPOR API | `.agent/skills/wapor-api-reference/SKILL.md` | `api_client.R`, `metadata.R`, variable codes |
| Viz | `.agent/skills/viz-reference/SKILL.md` | Maps, plots, Leaflet, tmap, ggplot2 |
| Memory | `.agent/skills/project-memory/references/rwapor.md` | Recall past decisions |

## Skill Load Rules by Task Type
| Task | Load These Skills |
|---|---|
| Bug fix | rwapor-developer + bug-log |
| New feature | rwapor-developer + feature-log |
| Shiny UI/UX | rwapor-developer + shiny-developer + ui-decisions |
| R package infra | r-package-expert |
| API / metadata | wapor-api-reference |
| Visualization | viz-reference |
| Lost context | prompt-history + architecture |
| General code | rwapor-developer + architecture |

## devtools Commands
```bash
"/c/Program Files/R/R-4.5.2/bin/Rscript.exe" -e "devtools::document()"
"/c/Program Files/R/R-4.5.2/bin/Rscript.exe" -e "devtools::test()"
"/c/Program Files/R/R-4.5.2/bin/Rscript.exe" -e "devtools::check()"
"/c/Program Files/R/R-4.5.2/bin/Rscript.exe" -e "devtools::load_all()"
```
