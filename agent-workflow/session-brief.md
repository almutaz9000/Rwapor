# Session Brief

_Very short handoff, optimized for token efficiency. Default first read after
`START-HERE.md`. See `templates/session-brief.md` for the entry format._

## Current Session — 2026-09-21 — WaPOR map progress bottleneck

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
