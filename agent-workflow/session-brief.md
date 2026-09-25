# Session Brief

_Very short handoff, optimized for token efficiency. Default first read after
`START-HERE.md`. See `templates/session-brief.md` for the entry format._

## Current Session — 2026-09-23 to 25 — WaPOR training notebook, participant package, lessons for Rwapor

**What happened**: Built and tested `training/water-productivity-training.qmd`
with real data (citrus JVA polygons + 177 sampled farms + de-identified survey;
Jendouba cereal mask), rewritten as a manual (concepts, SVG sketches, checkpoints,
no em dashes, L3 20 m only, Esri basemaps, terra maps at full resolution). Made it
offline-ready (per-date WaPOR downloads in `training/wapor_data/`, local = API).
Added participant package: `check_setup.R`, `WaPOR_Training.Rproj`,
`Note_to_Participants.docx`, self-contained HTML and PDF. Fixed seasonal green/blue
water in the package (monthly split, 1.0.2, test added, uncommitted). Found and
logged package problems ISS-20260923-003/-004, ISS-20260924-006,
ISS-20260925-007/-008/-009. Created the user-level skill `wapor-training-builder`.

**Verification**: final full render exit 0, 42 checkpoints (41 PASS, 1 intended
CHECK on survey yield F001); offline run with a dead proxy works; dependency scan
confirms the note's install commands cover every package used.

**Open / next**: review the improvement plan and tasks ti-01 to ti-16 (REVIEW
FIRST) in `docs/superpowers/specs/2026-09-24-training-driven-improvements-plan.md`
(lessons register L1 to L21 at the end). Nothing committed: 1.0.2 must be pushed
before the participant note is sent (GitHub still has 1.0.1). Keep 15 to 20 GB
free for full L3 renders.

## Previous Session — 2026-09-23 — Large-raster performance review and 1.0.1 size-aware processing

**What happened**: User asked for a bottleneck review of large rasters and long
20/100/300 m time series, then a grilled improvement plan (19 decisions plus
accuracy decisions A–D), then implementation in one change on branch
`perf/large-raster-1.0.1`. Built a planner (`wapor_plan_processing()`) and a
single window kernel used by memory, stream and tiled modes; seasonal and
monthly totals are now summed at native resolution and resampled once;
nearest-neighbour is the default (raw server values kept); pixels with missing
dekads are NA unless `min_coverage` allows. Found and fixed, with live
verification: tiled engine all-NA bug (ISS-20260923-001), remote engine unable
to match `YYYY-MM-D1` file names so `data_source = "api"` never worked in 1.0.0
(ISS-20260923-003), and a GDAL capability probe that always reported curl
missing (ISS-20260923-004). DuckDB raster blobs in monitoring logged as
ISS-20260923-002 (not fixed, by decision).

**Verification**: full test suite 1332 expectations, 0 failures (6 live-API
skips); `devtools::check()` 0 errors, 0 warnings, 2 pre-existing notes
(time check, `_smoke_check.R`); `inst/bench/remote_smoke_test.R` 5/5 live
checks pass (tiled equals memory, max diff 0). Benchmark (1500 x 1500 cells,
18 dekads, 512 MB budget) before the final memory fixes: 1.0.0 peak 5.8 GB
above baseline vs 1.0.1 tiled 1.6 GB, small job 5% faster. After the fixes,
per-stage profiling of the same job in auto/tiled mode stayed about 100 MB
above baseline. A final full benchmark rerun is blocked: the C: drive is full
(about 2 GB free), which made later runs fail with bad_alloc / unwritable
temp files. Rerun `inst/bench/large_raster_benchmark.R` once space is freed.

**Next**: user review of the branch (not pushed); decide whether to push, and
whether to tag 1.0.1. Codex's `seasonal-dashboard-semantics` task shares
`R/wapor_map.R`/`R/wapor_ts.R`/`R/utils.R` — Codex must rebase on this branch.

## Previous Session — 2026-09-22 — GitHub repo cleanup, README overhaul, pkgdown site, wheat vignette

**What happened**: User asked for a professional repo/README audit and
cleanup, then several follow-ups. (1) Classified all 233 remote branches;
deleted 184 (165 auto-agent `bolt-*`/`jules-*`/`copilot/*` + 6 already-merged
named branches), converted the 14 `version-0.x` milestone branches to tags
first. Discovered GitHub's actual default branch is `version-0.9.9`, not
`main` (blocks deleting it; README's CI badge points at `main` — flagged,
not changed). Left 46 named unmerged branches for manual review. (2)
Untracked 31 duplicate per-AI-tool adapter files/dirs (`.cursor/`,
`.windsurf/`, `GEMINI.md`, `QWEN.md`, etc. — all still on disk, gitignored);
kept only `AGENTS.md` + `CLAUDE.md` tracked (also fixed `CLAUDE.md` itself
being silently untracked). (3) Rewrote `README.md` Installation into a full
Windows/macOS/Linux beginner walkthrough; fixed WaPOR L1 resolution claims
against `inst/metadata/wapor_L1.json` (L1 imagery vars 300m not 250m;
`L1-PCP-D` is actually 5km and `L1-RET-D` is actually 30km, not 300m —
verified from metadata, not assumed); fixed the citation bibtex key
(`rwapor2024` -> `Rwapor`). (4) Added
`vignettes/wheat-water-productivity.Rmd`: a worked example (wheat mask,
single/multi-season, CWP/BWP) with every config option's alternatives
documented as inline comments (all verified against
`R/analysis_engine.R`/`R/analysis_registry.R` source, e.g. `data_source`'s
other value is `"api"`, full indicator code list from
`.wapor_builtin_indicator_steps()`). Discovered and documented (with live
verification, not just reading code) a previously-untested multi-season
"Smart-Linking" feature: `config$folder/seasonal_masks/<SeasonName>_mask.tif`
(and `_start.tif`/`_end.tif`) let each season in a multi-season
`config$period` list use its own crop mask / per-pixel season dates,
overriding even a global `use_crop_mask`/`use_season_rasters = FALSE`. (5)
Set up an actual pkgdown site (previously never published — all vignette
links were dead 404s): `.github/workflows/pkgdown.yaml`, `_pkgdown.yml`,
enabled GitHub Pages via API. Hit and fixed 3 real CI failures (pkgdown
defaulting into the already-tracked `docs/` folder; `build_site_github_pages()`'s
own `dest_dir` arg overriding `_pkgdown.yml`; a tidyselect misparse on the
`global-tiled` vignette slug in a custom `articles:` nav — dropped the
custom nav rather than chase the root cause). Site is live and verified:
https://almutaz9000.github.io/Rwapor/. (6) Built a new, independent Quarto
training notebook (`training/water-productivity-training.qmd`, kept out of
`vignettes/`/pkgdown/R CMD check via `.Rbuildignore`) with two live
step-by-step worked examples (Citrus: polygon used as both mask+AOI, no
built-in FAO Kc profile so built from scratch via FAO-56 Table 6.2 +
`fao_growth_stages.csv`; Wheat: separate cereal mask raster + AOI, reuses
the built-in "Winter Wheat" profile), each running the full indicator
chain with a plot/summary and equation explanation per step, plus
`leaflet` input/output exploration. While ground-truthing indicator codes
and result-list field names against `R/analysis_engine.R`/`NAMESPACE`,
found and logged (not fixed) `ISS-20260922-001`: the existing
`wheat-water-productivity.Rmd` vignette uses the inert code `"peff"`
instead of the real `"agg_peff"`, references a non-existent
`results$summary_table` field, and cites a non-existent
`wapor_compare_seasons()` function.

**Concurrent-session note**: Codex was active throughout on a separate task
(`seasonal-dashboard-semantics`) and switched the shared working directory's
checked-out branch to a new `version-1.0.0` mid-session without warning.
Every commit this session landed there first; each was verified to have no
file overlap with Codex's active files, then cherry-picked onto `main` via
an isolated `git worktree` (never touching the shared checkout) and pushed.
If you're resuming this repo and the checked-out branch isn't what you
expect, check `git branch --show-current` before trusting `git commit`'s
target — don't assume it matches what you last set.

**Verification**: all branch/tag operations confirmed via `git ls-remote`
before/after; 2 live `devtools::load_all()` test runs for the Smart-Linking
mask/season-raster behavior, formalized as
`tests/testthat/test-analysis-engine-seasonal-masks.R` (7/7 assertions
pass, run directly via `testthat::test_file()`); pkgdown site spot-checked
live post-deploy (homepage, reference index, all 6 vignette article pages
including wheat, all HTTP 200). Final `origin/main` tip: `ea02ef0`.

**Next**: the 46 named unmerged branches left for manual triage (two flagged
as recent/worth a look: `feat/publication-viz`, `docs/r4-github-hygiene`);
the local-only `version-0.9-UNFAO-CG35038B0.8` branch (never pushed) was
untouched; the README CI badge vs. actual default-branch (`version-0.9.9`)
mismatch is unresolved — maintainer decision needed on whether to switch
GitHub's default branch to `main` or update the badge/workflow triggers to
match `version-0.9.9`. Separately: `training/water-productivity-training.qmd`
was not rendered end-to-end this session (the user's real Citrus/Wheat
input files don't exist in this environment — the notebook uses clearly
marked placeholder paths for them); every R chunk was manually traced
against package source and cross-checked with `NAMESPACE`, but it still
needs a real render against real data before being handed to trainees.
`ISS-20260922-001` (vignette bugs found while building it) is unresolved.

## Prior Session — 2026-09-21 — WaPOR map progress bottleneck

**What happened**: User-reported L3-AETI-M retrieval was not a stalled remote
open: a live 12-layer JVA stack opened in 2.81 seconds and the complete
crop/write run took 13.4 seconds. The map implementation was silent during
that work, making the first 72-layer batch appear frozen. `wapor_map()` now
reports chunk opening, crop transition, and every write; Shiny refreshes its
download detail after each finished batch.

**Verification**: Parse passed; Shiny app construction passed; focused tests
passed (GDAL config 33, map 97 with 5 expected CRAN skips, streaming 8); the
live 12-layer map wrote 12/12 temporary output files. A 72-layer temporary
probe emitted chunks 1–2 status but did not provide a completion line in this
tool session, so it remains unverified as a complete run.

## Current Session — 2026-09-17 — Remote COG streaming hardening

**What happened**: Added complete-operation retry boundaries for remote raster
pixel I/O, default refusal of incomplete non-seasonal map/time-series results,
explicit partial-result metadata, bounded COG datatype sampling, and accurate
fallback writer documentation. Detailed plan is
`docs/plans/2026-09-17-rwapor-cog-streaming-hardening.md`; issue is
`ISS-20260917-003` / task 8.1.

**Verification**: all scoped R files parse, direct retry-helper execution
passes, and `git diff --check` passes. Full R tests and local `/vsicurl/` fixture
are not runnable here because `terra`, `devtools`, and `testthat` are absent.
Do not claim live WaPOR verification. Remaining: install/use a supported
terra/GDAL environment, add a local capability probe, and remove duplicate
remote reads in the tiled source path.

## Current Session — 2026-09-17 (continued) — Control Room dashboard fixes + logged optimization

**What happened**: (1) Fixed the Control Room's module-connection diagram —
it rendered as an empty box because Mermaid loaded its JS from
cdn.jsdelivr.net inside an iframe, blocked on this network; replaced with a
self-contained SVG layered flowchart, and upgraded the underlying edge data
from weak filename-substring matching (22 edges) to real resolved function
calls (92 `call` edges via a new `_function_definition_index()`). (2) Added
automated claim-vs-code verification and a stale-active-claim alert to the
dashboard (new "Claim verification" tab). (3) Walked through
`interval_helpers.R` / `plan_wapor_time_slices.R` with the user and logged
task **7.6** (memoise `wapor_plan_time_slices()` + `wapor_temporal_codes()`,
distinct from the existing 7.3 which only covers `.load_metadata_catalog()`)
for a future session to pick up — explicitly not implemented this session,
user asked to log it for later review only.

**Verification**: dashboard — 21/21 pytest passing, `py_compile` clean, live
`streamlit run` on a test port HTTP 200 + healthy `/_stcore/health`, real
board data checked (43 tasks, 92 call edges). 7.6 — not implemented, no
verification needed yet; benchmarked the *current* unmemoised behavior only
(~0.1-0.2s for a 9-year daily-only D plan via local `Rscript.exe` R-4.4.1).

**Next**: pick up task 7.6 from `agents-board.json`/`task-status.md` when
ready — rename `wapor_plan_time_slices`/`wapor_temporal_codes` bodies to
`_internal` suffix, wrap with `memoise::memoise()` following the
`R/api_client.R:367` pattern, add a cache-hit regression test, run the full
`test-plan_wapor_time_slices.R` suite (20 tests). Also still open: genuine
remaining gaps per the 2026-09-17 critical re-review (see below).

## Prior Session — 2026-09-17 (continued) — Dashboard fix + critical re-review

**What happened**: User asked to (1) verify the Streamlit "Rwapor Control
Room" dashboard works and reflects task updates, and (2) do another critical
review of remaining tasks and overall package health, not trusting prior
"done" claims at face value. Found the dashboard had been crashing on every
`board_claim.ps1` update since it was built (UTF-8 BOM vs plain-utf-8
decode) -- fixed and re-verified live. Then cross-checked every "pending"
task against the actual codebase (grep for named deliverables) rather than
the tracker: 7 tasks (2.2, 3.1, 1.6, 3.4, 5.1, 5.2, 6.1, 6.2) turned out to
be substantially or fully implemented already. Corrected `IMPROVEMENT_PLAN.md`,
`agents-board.json`, `task-status.md`. Ran full `R CMD check --as-cran`:
0 errors, 0 warnings, 2 harmless/fixed NOTEs. Discovered the package is
already `Version: 1.0.0` (development) per `DESCRIPTION`/`NEWS.md` -- the
`version-0.9.9` branch name is stale.

**Verification**: dashboard relaunched on a test port (HTTP 200, no
traceback, correct task data), then stopped. Full `devtools::check()` --
0 errors/0 warnings/2 NOTEs (one fixed via `.Rbuildignore`, one is a
harmless environment quirk). Every "mostly/fully done" claim above is
grep/read-verified, not inferred -- see `issues-log.md` ISS-20260917-001/002
for exact evidence and file:line references.

**Next**: genuine remaining gaps per the corrected tracker: `resampling_method`
(1.6), `linear_trend` (3.4), Python-parity tests (5.1), lintr/styler CI
(5.3), vignette-naming decision (6.1), indicator-registry Shiny wiring
(4.1), area-weighted DuckDB stats (4.2 -- schema exists, feature doesn't),
Phase 7.2/7.3 (metadata module efficiency). See `task-status.md`.

## Last Session — 2026-09-17 — Phase 7.1: RET/PCP fallback dedup

**What happened**: Continued the Phase 7 metadata/API architecture review
from the prior session. Implemented 7.1: the "RET/PCP resolve to L1 at
L2/L3" rule was triplicated (2x `R/api_client.R`, 1x `R/metadata.R`);
consolidated into one `.wapor_resolve_level_fallback()` helper in
`R/api_client.R`, called from all 3 sites. While doing so, self-review of
the diff caught that the *prior* session's 7.0 write-up had overclaimed:
it said the level->URL mapping was routed through 3/3 call sites, but
`metadata.R`'s `.fetch_metadata_api_variable()` still had its own
hardcoded `switch()`. Fixed that too (now genuinely 3/3) and corrected the
7.0 records in `IMPROVEMENT_PLAN.md`, `issues-log.md`, `agents-board.json`.

**Verification**: `devtools::load_all()` clean; direct check confirmed
`L1-RET-D`, `L2-RET-D`, `L2-PCP-D`, `L3-RET-D`, `L3-PCP-D`, `L3-AETI-D`,
`AGERA5-ET0-E` all resolve identically to pre-refactor behavior; full
suite `0 fail / 1019 passed`; `devtools::document()` produced no new
NAMESPACE/man diffs.

**Next**: Phase 7.2 (wapor_res_key() reuse spatial_resolution_m), 7.3
(memoise .load_metadata_catalog()); 7.4 remains explicitly deferred. See
`task-status.md` / `IMPROVEMENT_PLAN.md`.

## Last Session — 2026-09-16 (continued) — Metadata/API module architecture review (Phase 7)

**What happened**: User asked for a senior-level architecture review of
`api_client.R`, `wapor_res_key.R`, `metadata.R`, `wapor_metadata_cache.R`,
`plan_wapor_time_slices.R` for redundancy/duplication/efficiency. Found and
fixed a real correctness bug (duplicate `%||%` with conflicting semantics,
load-order dependent) plus a triplicated level->URL mapping; both fixed
in-place with a single shared internal helper each, no new files, no export
changes. Wrote `IMPROVEMENT_PLAN.md` Phase 7 documenting 4 deferred
follow-ups (7.1-7.4) for a future session, scoped per user's explicit
choice to keep this pass minimal/in-place given proximity to the
`version-0.9.9` release.

**Verification**: `devtools::load_all()` clean, `devtools::document()`
produced no unexpected NAMESPACE/man diffs, full suite `0 fail / 1019
passed`. Caught and fixed a transient `1 fail` mid-refactor (see
`ISS-20260916-002` for the root cause -- jsonlite NULL round-tripping).

**Next**: Phase 7.1-7.4 (see task-status.md / IMPROVEMENT_PLAN.md), then
continue with Phase 1.5 onward as before.

## Earlier — 2026-09-16 — Metadata cleanup and unified discovery

**What happened**: Replaced the duplicate metadata fetch implementation with a
package-backed wrapper, removed dead parsers, added spatial-resolution and
product-type metadata plus a manifest, refactored Shiny variable discovery,
and fixed package Author/Maintainer metadata.

**Verification**: Metadata, planner, and full test suites pass with 0 failures;
latest full suite completed with 254 passing assertions. R CMD check completes
with 0 errors, with remaining warnings for repository portability, stale
unrelated documentation, and vignettes.

**AgERA5 decision**: The live C3S catalogue uses base product codes without
temporal suffixes, so `inst/metadata/agera5.json` was not added. AgERA5 remains
served through the curated registry to avoid inventing temporal availability.



## Last Session — 2026-09-15 (session 2)

**What happened**: Implemented all three deferred production-hardening items
from the session 1 handoff: B2/P2/D2 blob-store rewrite, S2 accordion
wizard, S4 synchronized dual-map.

**Key results**:
- B2/P2/D2: `wapor_save_raster_blobs()` now batches vsicurl opens per
  variable, filters already-saved dates before any network call, and writes
  both the in-memory blob and a file-backed COG with full provenance
  columns (`raster_path`, `gdal_version`, `terra_version`, `nodata`,
  `band_count`).
- S2: `inst/shiny/mod_download.R` sidebar is now a 5-step numbered accordion
  wizard (Project, Variables, Period, L3 Region, Run) with a numbered-badge
  CSS class; the sticky footer button now jumps to the Run step instead of
  duplicating the download trigger.
- S4: new `inst/shiny/mod_dual_map.R` module adds a "Dual Compare" tab with
  two independent, view-synchronized leaflet maps
  (`leaflet.extras2::addLeafletsync()`/`unsync()`), capability-guarded with
  an install-instructions fallback.
- Verified throughout: parse checks, `devtools::load_all()`, a standalone
  DB/COG smoke test, `shiny::shinyAppFile("app.R")` building the full UI,
  and `devtools::test()` — full suite 0 failures / 764 passed after the
  blob rewrite, and 0 failures / 96 passed on shiny-specific tests after
  the UI changes.

**Not done / deferred**: none of the three handoff items remain; next work
is IMPROVEMENT_PLAN.md Phase 1.5 (Shiny L3 mosaic-all UI wiring) onward.

**Next**: Phase 1.5 Shiny L3 selection UI, then 1.6, 2.2, 2.3, 3.x. See
`task-status.md` and `STATE.md` for the full ranked list.

## Earlier Session — 2026-09-15 (session 1)

**What happened**: Production hardening pass targeting correctness, robustness,
and DuckDB schema stability. 13 of 18 planned items completed.

**Key results**:
- `app.R` Shiny dependency guard replaces bare `library()` for 17 packages.
- DuckDB `monitoring_metadata` now carries `schema_version` with migration helper.
- `wapor_write_cog` BIGTIFF threshold fixed (dtype byte-width lookup).
- All 9 network-dependent test files now guarded with `skip_if_wapor_offline()`.
- `.onLoad` GDAL config fires unconditionally (was env-gated).
- `wapor_suggest_tile_size()` exported; `on_batch_done` callback added to
  `wapor_ts` and `wapor_map`.
- DuckDB: `raster_grid_registry` + validator; upsert + `season_id` PRIMARY KEY
  in `farm_timeseries`.
- Dashboard: grouped variable choices, analysis config save/load, stress
  threshold inputs wired.

**Deferred (needs next session)**:
- B2/P2/D2: `wapor_save_raster_blobs` rewrite (batch vsicurl + blob bytes +
  file-backed COG path). Schema columns already added; write path not done.
- S2: Numbered step accordion wizard (complex Shiny UI refactor).
- S4: Synchronized dual-map (leaflet.extras2 sync).

**Not done / explicitly deferred**: 1.5 L3 mosaic-all Shiny wiring (core R
implementation landed in `feat/l3-mosaic-tiled-core`, UI not yet wired).
IMPROVEMENT_PLAN.md phases 2-6 remain open.

**Next**: Start with B2/P2/D2 (blob rewrite) as the highest-priority deferred
item, then S2 accordion wizard. See `task-status.md` for full ranked list.

## Earlier Session — 2026-09-03

**What happened**: Audited WaPOR seasonal "smart download" robustness and the
cross-agent skill/instruction wiring. Fixed download-side bugs, created the
`agent-workflow/` hub.

**Key results**:
- Raster-selection planning in `wapor_plan_time_slices()` correct (20 tests pass).
- Fixed: SHA-256 disk-cache key, retry/backoff, `missing_periods`, `Retry-After`.
- Populated `agent-workflow/` hub (was referenced everywhere but missing).
- Added pointer headers to all fable-skill-managed adapter files.

**Not done**: mirroring `.agent/skills/*` into `.claude/skills/` for Claude Code.

**Next**: see `task-status.md` Pending Follow-Ups.
