# Rwapor project agents and skills

This directory equips Claude Code with a roster of domain-expert
subagents and supporting skills scoped specifically to the Rwapor
package's goal: harden the analysis engine and pipeline (per
`IMPROVEMENT_PLAN.md`), then reach a clean **CRAN submission**.

It was assembled by reading `IMPROVEMENT_PLAN.md`, `NEWS.md`,
`docs/REPOSITORY_STRUCTURE.md`, the current `R/` and `tests/testthat/`
trees, `DESCRIPTION`, and the pre-existing (externally synced)
`rwapor-developer` skill — not written from generic templates. Several
findings from that review are recorded directly in the relevant
agent/skill files (e.g. missing CI workflows, missing
`cran-comments.md`, a Suggests-package guarding gap, a stale
architecture reference doc) as concrete starting punch-lists, not just
process description.

## Agents (`.claude/agents/`)

Each agent owns a distinct expertise boundary and explicitly defers
outside it — this keeps any one agent's answers grounded instead of
guessing across domains:

| Agent | Owns | Defers to |
|---|---|---|
| `wapor-data-expert` | WaPOR v3/AgERA5 catalog, variable codes, product levels, units | agronomy for formulas, geospatial for raster mechanics |
| `agronomy-expert` | FAO-56 Kc/Peff/adequacy/CWP/BWP/GBWP/NBWP formulas, crop parameters | geospatial for pixel/CRS mechanics, wapor-data for variable semantics |
| `geospatial-engineer` | terra/sf mechanics, latitude-aware area weighting, alignment/resampling, tiled engine | bigdata for scale, api-cog for remote I/O |
| `bigdata-engineer` | DuckDB monitoring, disk/TTL caching, memory scaling, parallel batching | geospatial for raster math, r-package-cran for dependency policy |
| `api-cog-streaming-engineer` | httr2 client, COG read/write, `/vsicurl/` streaming, GDAL/PROJ config | bigdata for cache design, geospatial for tile consumption |
| `r-package-cran-expert` | DESCRIPTION/NAMESPACE, testthat health, `R CMD check --as-cran`, CI, CRAN policy, release gate | pulls in all five above for domain correctness first |

`r-package-cran-expert` is the release gate: it certifies "CRAN ready:
yes/no" but relies on the other five for whether the *science* and
*engineering* underneath are actually correct.

## Skills (`.claude/skills/`)

Skills carry the deep, reusable procedural content agents load on
demand, so agent files stay short and skills stay the single source of
truth:

| Skill | Loaded by | Content |
|---|---|---|
| `cran-release-readiness` | r-package-cran-expert (all agents before release-adjacent edits) | Full CRAN submission playbook: local checks → multi-platform checks → CI → `cran-comments.md` → submission/resubmission |
| `wapor-etlook-methodology` | wapor-data-expert, agronomy-expert | WaPOR/ET-Look/PyWaPOR/FAO-56 reference sources and the "verify current source, don't recall" discipline |
| `geospatial-raster-scaling` | geospatial-engineer, bigdata-engineer | Latitude-aware area weighting, reference-layer alignment rules, tiled/windowed engine pattern and verification |
| `cog-api-streaming` | api-cog-streaming-engineer | httr2 client conventions, COG write pattern with GDAL-version fallback, `/vsicurl/` range-read streaming, CRAN-safe network code |
| `r-package-quality-gate` | all agents, before calling any change done | Tiered command sequence (per-change → per-PR → per-release), mapped to which test file to run for which `R/` area |

This complements, not replaces, the existing (externally synced)
`rwapor-developer` skill and the repo's `skills/fable-skill`
engineering discipline (ground truth over memory, verify before
declaring done, self-review before finishing). If `rwapor-developer`
is active in a session, respect its DEV BRIEF convention when editing
`R/` or `inst/shiny/` code; the agents here add domain depth on top of
it, not a competing workflow. Note: that skill's `references/architecture.md`
predates several current files (`analysis_engine.R`, `analysis_tiled.R`,
`analysis_registry.R`, `anomaly.R`, `diagnose.R`, `wapor_metadata_cache.R`,
`wapor_monitoring.R`, `wapor_res_key.R`) — treat it as historical
context, not current ground truth, until it's refreshed.

## How to use this roster

Delegate to a named agent via the `Agent` tool with `subagent_type` set
to the agent's `name` (e.g. `geospatial-engineer`) when a task falls
squarely in its domain, or let the orchestrating session read the
`description` frontmatter to route automatically. For a release push,
the expected flow is: domain agents fix/verify their area →
`r-package-cran-expert` runs the release checklist from
`cran-release-readiness` → sign-off.
