# Change Log

_Short, agent-facing operational change summary. Complements but does not
replace `NEWS.md` or `git log` — only major workflow changes, meaningful repo
structure changes, and fixes that affect future sessions belong here._

## 2026-09-23 — Size-aware processing and native-resolution aggregation (1.0.1)

- Branch `perf/large-raster-1.0.1`; design and decisions in
  `docs/superpowers/specs/2026-09-23-large-raster-performance-design.md`.
- New `R/processing_plan.R` (`wapor_plan_processing()`, budget, thresholds,
  I/O plans) and `R/processing_kernel.R` (one window kernel for
  memory/stream/tiled; profile-split native aggregation; coverage). The
  engine and `wapor_run_seasonal_analysis_tiled()` now run on it; the old
  tile helpers in `R/analysis_tiled.R` were removed.
- Defaults changed on purpose: nearest-neighbour resampling for continuous
  variables, `min_coverage = 1`, AOI defaults to the crop mask extent,
  `batch_size = NULL` (planner) in `wapor_map()`/`wapor_ts()`. See NEWS 1.0.1.
- Took over `R/utils.R`, `R/wapor_map.R`, `R/wapor_ts.R` from Codex's
  `seasonal-dashboard-semantics` task by user decision; Codex's board entry
  is untouched, so check this entry before editing those files.
- Tags: the ambiguous local `version-1.0.0` tag was replaced by
  `v1.0.0-final` (a9176dd, the pre-change code). The published `v1.0.0`
  tag (82cd8b5) is unchanged. Nothing pushed.
- Benchmark and live smoke-test scripts live in `inst/bench/`.

## 2026-09-22 — New independent training notebook (`training/water-productivity-training.qmd`)

- Added a standalone Quarto training notebook, deliberately kept outside
  `vignettes/`/pkgdown/R CMD check (`training/` added to `.Rbuildignore`).
  Calls only exported `Rwapor` functions; no package source touched.
- Two live, step-by-step worked examples (Citrus: polygon used as both
  mask+AOI, season 2024-03-01→2025-02-28, no built-in FAO Kc profile so
  built from scratch via FAO-56 Table 6.2 + this repo's
  `fao_growth_stages.csv`; Wheat: separate cereal mask raster + AOI
  boundary, season 2023-11-01→2024-05-31, reuses the built-in "Winter
  Wheat" profile), each running the full indicator chain with a plot or
  summary and an equation explanation at every step, plus `leaflet`
  input/output exploration.
- While ground-truthing the indicator codes and result fields against
  `R/analysis_engine.R`/`R/analysis_registry.R`/`NAMESPACE`, found three
  real bugs/gaps in the existing `vignettes/wheat-water-productivity.Rmd`
  and one usability gap in `wapor_run_seasonal_analysis()`'s `aoi_region`
  handling — logged as `ISS-20260922-001` in `issues-log.md`, not fixed
  (out of scope for this session; vignette/package source left untouched).

## 2026-09-22 — Repo cleanup, README overhaul, pkgdown site, wheat vignette

- Deleted 184 of 233 remote branches (auto-agent `bolt-*`/`jules-*`/`copilot/*`
  plus already-merged named branches); converted the 14 `version-0.x`
  milestone branches to tags first, so history is preserved. GitHub's
  default branch is `version-0.9.9`, not `main` (README CI badge mismatch
  still open, unresolved).
- Untracked 31 duplicate per-AI-tool adapter files (`.cursor/`, `.windsurf/`,
  `GEMINI.md`, `QWEN.md`, `.rules`, etc.) via `.gitignore`; kept only
  `AGENTS.md`/`CLAUDE.md` tracked as canonical pointers to
  `agent-workflow/START-HERE.md`.
- Rewrote `README.md` Installation into a full Windows/macOS/Linux beginner
  guide; corrected the Data Catalog table's WaPOR Level 1 resolutions
  against `inst/metadata/wapor_L1.json` (imagery vars 300m, `L1-PCP-D` 5km,
  `L1-RET-D` 30km — previously all shown as 250m/300m uniformly).
- Added `vignettes/wheat-water-productivity.Rmd` and
  `tests/testthat/test-analysis-engine-seasonal-masks.R`: documents and
  regression-tests the multi-season `config$folder/seasonal_masks/`
  per-season crop-mask/season-raster override in
  `wapor_run_seasonal_analysis()` (previously untested).
- Published the pkgdown site for the first time
  (`.github/workflows/pkgdown.yaml`, `_pkgdown.yml`, GitHub Pages enabled):
  https://almutaz9000.github.io/Rwapor/.

## 2026-09-21 — WaPOR map progress visibility

- Added per-chunk remote-open/crop/write progress to `wapor_map()` and
  batch-level Shiny download detail updates; verified with focused tests and a
  live 12-layer JVA output run.

## 2026-09-17 — Remote COG streaming hardening

- Added complete-operation retry coverage for remote raster crop, zonal
  extraction, global reduction, tiled window reads, and output writes instead
  of retrying only lazy `terra::rast()` opens.
- Non-seasonal `wapor_map()` and `wapor_ts()` now reject incomplete batches by
  default; explicit partial mode records failed layers and warns.
- COG datatype probing now reads a bounded leading window. Fallback output is
  documented accurately as tiled compressed GeoTIFF when the COG driver is
  unavailable.
- Verification: R parse checks, direct retry-helper execution, and
  `git diff --check` passed. terra-dependent tests remain blocked because the
  current environment lacks `terra`, `devtools`, and `testthat`.

## 2026-09-17 (continued)

- Control Room dashboard: added automated claim-vs-code verification (grep
  each task's listed files for identifier tokens extracted from its
  title/notes) and a stale-active-claim alert (active status + no
  claimed_utc, or claimed_utc past 24h). New "Claim verification" tab.
  Files: `agent-workflow/dashboard/data.py`, `app.py`, `test_data.py`
  (13 new tests, 17/17 passing).
- Control Room dashboard: replaced the Mermaid/CDN module-connection diagram
  (blocked on networks that block cdn.jsdelivr.net, rendered as an empty
  box) with a self-contained SVG layered flowchart -- no external JS fetch.
  Also replaced the weak filename-substring "reference" edges with real
  function-call resolution (`_function_definition_index()` + call-site
  regex): 92 resolved `call` edges vs the prior 22 weak edges. 21/21 tests
  passing, live `streamlit run` smoke-tested HTTP 200.
- Logged task **7.6** (memoise `wapor_plan_time_slices()` and
  `wapor_temporal_codes()`, distinct from existing 7.3) for future-session
  review after a user request during an `interval_helpers.R` /
  `plan_wapor_time_slices.R` walkthrough. Not implemented this session --
  see `agents-board.json` and `task-status.md` for the full rationale.

- Fixed `agent-workflow/dashboard/app.py`: `load_board()` decoded
  `agents-board.json` as plain `utf-8`, but `board_claim.ps1` always writes
  a UTF-8 BOM on Windows PowerShell -- the dashboard had been crashing on
  every board update since the tool was created. Fixed with `utf-8-sig`.
  Verified by relaunching (HTTP 200, no traceback) and a direct data check.
  See `ISS-20260917-001`.
- Critical re-review of the task tracker against actual code: 7 of ~20
  "pending" tasks (2.2, 3.1, 1.6, 3.4, 5.1, 5.2, 6.1, 6.2) were already
  substantially or fully implemented but never marked as such. Corrected
  `IMPROVEMENT_PLAN.md`, `agents-board.json`, `task-status.md`. See
  `ISS-20260917-002`.
- Full `R CMD check --as-cran`: 0 errors, 0 warnings, 2 NOTEs (one harmless
  "unable to verify current time"; one for `STATE.md` at top level, fixed
  by adding it to `.Rbuildignore`). Package version is `1.0.0` (development)
  per `DESCRIPTION`/`NEWS.md`, not `0.9.9` -- the `version-0.9.9` branch
  name is stale relative to that.

## 2026-09-17

- IMPROVEMENT_PLAN.md Phase 7.1: deduplicated the RET/PCP level-fallback
  rule (was implemented 3x independently across `R/api_client.R` and
  `R/metadata.R`) into one `.wapor_resolve_level_fallback()` helper. Full
  suite 0 fail / 1019 passed. Also corrected a 2026-09-16 overclaim: the
  7.0 level->URL mapping dedup was reported as 3/3 call sites but only did
  2/3; `metadata.R`'s `.fetch_metadata_api_variable()` still had its own
  hardcoded URL switch(), caught via self-review and now genuinely fixed.

## 2026-09-16

- Metadata/API module architecture review (IMPROVEMENT_PLAN.md Phase 7):
  fixed a duplicate `%||%` with conflicting semantics (`R/utils.R` vs
  `R/wapor_metadata_cache.R`, load-order dependent) and consolidated the
  level->workspace-URL mapping (hardcoded independently in 3 files) into
  `.wapor_level_workspace_url()`. See `ISS-20260916-002`. Deferred
  follow-ups (RET/PCP fallback dedup, spatial-resolution re-parsing,
  uncached catalogue loader, optional file split) logged as Phase 7.1-7.4.
  Full suite 0 fail / 1019 passed.

- Added `agent-workflow/agents-board.json` (shared task/model ledger),
  `scripts/board_claim.ps1` (claim/update helper), and
  `agent-workflow/dashboard/` (Streamlit live status dashboard, launched via
  `scripts/run_dashboard.ps1`). `START-HERE.md` now has a "Cross-model
  coordination" protocol requiring every model to claim/release tasks in
  `agents-board.json` so Claude/Codex/Gemini/Hermes/Antigravity/etc. don't
  duplicate each other's work. `.gitignore` updated for the dashboard's local
  Python artifacts (`agents-board.json`/`app.py`/`requirements.txt` stay
  tracked).

- Metadata cleanup: `inst/metadata/fetch_metadata.R` is now a thin wrapper
  around `wapor_update_metadata()`. Removed duplicate parsers, added numeric
  spatial-resolution and product-type fields plus a metadata manifest, routed
  Shiny variable discovery through the cache-backed service, and resolved the
  L3 region-aware temporal availability issue. AgERA5 JSON was deliberately
  deferred because the live C3S schema uses unsuffixed base product codes.
  Verified with 0-failure metadata, planner, Shiny, and full test runs.

## 2026-09-15 (session 2)

- B2/P2/D2 wapor_save_raster_blobs rewrite: batched vsicurl opens per
  variable, file-backed COG + in-memory blob dual write, provenance columns
  populated. S2: mod_download.R sidebar rebuilt as a 5-step numbered
  accordion wizard. S4: new mod_dual_map.R adds a synchronized dual-map
  "Dual Compare" tab via leaflet.extras2::addLeafletsync(). All three
  verified with parse checks, devtools::load_all(), a DB/COG smoke test,
  a full shinyAppFile() build, and devtools::test() (764 passed full suite;
  96 passed shiny-specific after UI changes).

## 2026-09-15 (session 1)

- Production hardening pass (13/18 items). Completed: B1 Shiny dep guard,
  B3 DuckDB schema_version + migration, B4 BIGTIFF dtype-bytes fix, B5 all 9
  network-test skip guards, P1 unconditional GDAL onLoad, P3 tile-size helper,
  P4 on_batch_done callback, D1 raster_grid_registry + validator, D3 upsert,
  D4 season_id PRIMARY KEY, S1 grouped var choices, S3 config save/load,
  S5 stress threshold inputs. Deferred: B2/P2/D2 blob write rewrite, S2
  accordion wizard, S4 dual-map sync.

## 2026-09-03

- Created the `agent-workflow/` hub (`START-HERE.md`, `project-memory.md`,
  `task-status.md`, `issues-log.md`, `session-brief.md`, `change-log.md`,
  `templates/`, `scripts/agent_preflight.ps1`,
  `scripts/agent_closeout.ps1`, `scripts/agent_digest.ps1`). This folder was
  the mandated entry point in every adapter file but did not previously
  exist — see `docs/superpowers/specs/2026-05-11-agent-workflow-design.md`.
- Fixed WaPOR seasonal download robustness: SHA-256 disk-cache key (was a
  collision-prone checksum), retry-with-backoff in the seasonal raster
  loader, plan-vs-loaded reconciliation (`missing_periods`), and
  exponential-backoff/`Retry-After`-aware API retries. Added `digest` to
  `Imports`. See NEWS.md (Rwapor 0.9.9, "Download Robustness") and
  `issues-log.md` ISS-20260903-001.
- Added an `agent-workflow/START-HERE.md` pointer header to the generic
  fable-skill-managed files that lacked one (`GEMINI.md`, `QWEN.md`,
  `WARP.md`, `.rules`, `.goosehints`, `CONVENTIONS.md`, `replit.md`,
  `.junie/guidelines.md`, `.openhands/microagents/repo.md`) and added a
  sibling `rwapor-agent-workflow` rule file for the rules-directory tools
  (`.cursor`, `.continue`, `.windsurf`, `.clinerules`, `.roo`, `.trae`,
  `.kilocode`, `.kiro`, `.augment`) without touching their managed
  fable-skill files.
