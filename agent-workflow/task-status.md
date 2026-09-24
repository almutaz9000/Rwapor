# Task Status

_Live execution state. See `templates/task-entry.md` for the entry format._

## Active

- **Large-raster performance and size-aware processing (1.0.1)** — Owner:
  Claude. Branch `perf/large-raster-1.0.1`. Design and all 19 grilled
  decisions (plus A–D on accuracy): `docs/superpowers/specs/2026-09-23-large-raster-performance-design.md`.
  Planner (`wapor_plan_processing()`, `processing = "auto"`), shared window
  kernel for memory/stream/tiled, native-resolution aggregation, coverage,
  exact block-wise P95/Theil, closed-form trend, `wapor_map`/`wapor_ts`
  batching and chunk sizing, dashboard mode selector. Took over
  `R/utils.R`, `R/wapor_map.R`, `R/wapor_ts.R` from the Codex task below by
  user decision (Codex's board entry left untouched). Resolves
  ISS-20260923-001/-003/-004; ISS-20260923-002 (DuckDB blobs) left open.

- **Seasonal summary semantics in the dashboard** — Add the shared
  variable-aware `sum`/`mean`/`std`/`min`/`max`/`median` contract to both
  Shiny paths and reject invalid state/rate sums. Status: Active. Owner:
  Codex. Design: `docs/superpowers/specs/2026-09-22-dashboard-seasonal-summary-design.md`.

- **8.1 — Remote COG streaming hardening** — DONE (Codex, 2026-09-21).
  A live 12-file `/vsicurl/` open completed in 2.81 seconds; the actual
  issue was the formerly silent crop-and-write phase. `wapor_map()` now logs
  chunk opening, crop transition, and every layer write; the Shiny download
  panel refreshes its detail after each batch. Verified parse, Shiny app
  construction, 138 focused assertions, and a 12-layer live run with all
  output files present. A 72-layer temporary probe emitted chunk 1 and 2
  progress but did not produce a completion line in this tool session.

- None open as of 2026-09-15.

## Pending — Next Session (Production Hardening continuation)

### Medium priority (from IMPROVEMENT_PLAN.md open items)

- **1.5 — Explicit L3 Selection / Mosaic-All Coverage Policy** (Phase 1 CRITICAL)
  Core resolver for all AOI-intersecting L3 codes; explicit policy (single code
  or `mosaic_all`); COG mosaic + coverage manifest; Shiny L3 selection UI.
  Files: `R/wapor_map.R`, `R/wapor_ts.R`, `R/seasonal_download.R`,
  `inst/shiny/mod_download.R`, `inst/shiny/mod_analysis.R`.

- **1.6 — Explicit Alignment Reference (Mask vs AETI vs Custom)** — DONE, verified 2026-09-18. `reference_layer` param fully implemented (analysis_engine.R:106-110, exact spec match); `resampling_method` per-layer map is implemented at analysis_engine.R:111-119 with `get_resampling_method()` closure and defaults for aeti/crop_mask/ret/pcp/npp/season_start/season_end. Only remaining gap: overlap validation error (not checked). Core deliverable done. Files: `R/analysis.R`, `R/analysis_engine.R`.

- **2.3 — Memory Benchmark Suite**
  Parameterized test grid 1k->10k peak-memory gate; tiled engine flat-memory
  verification. File: `tests/testthat/test-memory-scaling.R` (new).

- **3.3 — Publication Map Helpers** (`R/viz.R` new)
  `wapor_plot_map`, `wapor_plot_comparison`, `wapor_plot_timeseries`,
  `wapor_plot_kc_curve`, `wapor_plot_anomaly`. Verified 2026-09-18: file exists and all five functions exported in NAMESPACE. Still open per spec: indicator-specific colorblind palettes (RdYlGn for adequacy, viridis for CWP), scale bar, north arrow. Current implementation uses single blue-to-red gradient.

- **3.4 — Anomaly & Trend Module** — DONE, verified 2026-09-18. All 4 functions done and exported in `R/anomaly.R` (`wapor_calc_zscore`, `wapor_calc_spatial_hotspots`, `wapor_calc_anomaly_baseline`, `linear_trend` at anomaly.R:111). `linear_trend` is in NAMESPACE:7. Test file `tests/testthat/test-anomaly-trend.R` exists and tests `linear_trend`. Core deliverable complete.

- **3.5 — Preflight Validation Module** — DONE, verified 2026-09-18. `wapor_preflight_check()` at analysis_validation.R:250 and `wapor_validate_data_coverage()` at analysis_validation.R:179 are both exported in NAMESPACE. Deliverable complete, just in a different file than the tracker expected (analysis_validation.R instead of preflight.R).

- **4.1 — Dashboard: Indicator Selection from Registry**
  Read indicator checkbox list from `INDICATOR_STEPS`; auto-generate UI.
  Files: `inst/shiny/app.R`, `inst/shiny/mod_analysis.R`. Verified 2026-09-17:
  the backend registry (`wapor_list_indicator_steps` etc.) is exported but
  genuinely not consumed by the Shiny UI yet — still open.

- **4.2 — DuckDB Monitoring: Area-Weighted Stats**
  Per-farm area (ha) in `farm_timeseries`; area-weighted stress means;
  migration script. File: `R/wapor_monitoring.R`. Verified 2026-09-17: an
  `area_ha DOUBLE` column exists in the schema DDL but is never populated
  or used in any query — schema scaffolding only, feature still open.

- **5.1 — Expand Unit Tests (Pure Math Layer)** — PARTIALLY DONE, verified
  2026-09-17. `tests/testthat/test-indicators-math.R` exists (65 lines,
  ~10 functions covered). Still open: systematic edge-case coverage,
  waporbox Python reference comparison (verified absent).

- **5.2 — Integration Test: Full Seasonal Pipeline** — PARTIALLY DONE,
  verified 2026-09-17. `tests/testthat/test-analysis-engine.R` exists
  (314 lines, 3 `test_that` blocks covering local-raster/crop-mask/registry
  paths). Not confirmed: 100x100 grid, multi-season batch, local-vs-API
  parity — needs a closer read.

- **5.3 — CI: lintr + styler checks** — DONE, verified 2026-09-18. lint job exists at `.github/workflows/R-CMD-check.yaml:64-80` running `lintr::lint_package()` and `styler::style_pkg(dry="on")`. Deliverable complete.

- **6.1 — Vignettes** — DIFFERENT SHAPE THAN SPEC'D, verified 2026-09-17.
  4 vignettes exist (`advanced-analysis`, `data-catalog`, `getting-started`,
  `shiny-dashboard`) but none of the 5 originally-specified ones
  (`admin-timeseries`, `crop-mask-seasonal`, `mixed-resolution`,
  `season-comparison`, `global-tiled`). Needs a maintainer decision.
- **6.2 — README First-Time Install Guide** — MOSTLY DONE, verified
  2026-09-17. System deps and the exact spec'd verify step are present.
  Still open: `remotes::install_github()` note for terra/latest GDAL.

### Medium/low priority (from IMPROVEMENT_PLAN.md Phase 7 -- metadata/API architecture)

- **7.2 — `wapor_res_key()` reuse `spatial_resolution_m`** instead of
  re-parsing the resolution string inline. File: `R/wapor_res_key.R`.
- **7.3 — Memoise `.load_metadata_catalog()`**. `wapor_temporal_codes()`
  bypasses memoisation and re-reads/re-parses JSON from disk every call.
  Files: `R/wapor_metadata_cache.R`, `R/plan_wapor_time_slices.R`.
- **7.6 — Memoise `wapor_plan_time_slices()` and `wapor_temporal_codes()`**
  (distinct from 7.3). Both are pure/deterministic for identical args but
  are the outliers not wrapped in `memoise::memoise()`, unlike the package's
  3 existing examples (`wapor_generate_urls`, `wapor_variable_metadata`,
  `.load_metadata_catalog_cached`). Benchmarked 2026-09-17: not a CPU
  bottleneck alone (~0.1-0.2s even for a 9-year daily D plan) but repeated
  identical calls in `wapor_run_monitoring()`'s per-variable loop and
  repeated seasonal-extraction script re-runs redo the same interval
  decomposition. Fix pattern already established in `R/api_client.R:367`.
  File: `R/plan_wapor_time_slices.R`. Logged for future-session review, not
  implemented.
- **7.4 — (Deferred) Split `metadata.R`/`wapor_metadata_cache.R` by
  responsibility**, consistent `wapor_<domain>_<role>.R` naming. Explicitly
  deferred pending a maintainer decision -- package is on `version-0.9.9`.

### Still open (from earlier sessions)

- **Raster integrity validation** (checksum/hash of downloaded rasters).
  Lower priority. Owner: unassigned.
- **Mirror `.agent/skills/*` into `.claude/skills/`** so Claude Code skill
  loader discovers them. Flagged 2026-09-03, not yet actioned.

## Blocked

- None.

## Recently Completed

### 2026-09-24 — Claude→Codex delegation setup

- Claude plans (`templates/codex-plan.md`), Codex implements (`scripts/codex_task.ps1`),
  Claude verifies. Slim `AGENTS.override.md` for Codex, Codex skills in `.agents/skills/`,
  Claude skills `codex-delegate` and `codex-skill-author`. Details: `change-log.md` 2026-09-24.

### 2026-09-17 — RET/PCP level-fallback dedup (Phase 7.1)

- **7.1** — "RET and PCP resolve to L1 at L2/L3" was implemented 3x
  independently (2x `wapor_generate_urls_internal()` in `R/api_client.R`,
  1x `get_variable_metadata_internal()` in `R/metadata.R`). Consolidated
  into one `.wapor_resolve_level_fallback(variable)` helper in
  `R/api_client.R`, called from all 3 sites. Verified: full suite
  `0 fail / 1019 passed`; direct check of `L1-RET-D`, `L2-RET-D`,
  `L2-PCP-D`, `L3-RET-D`, `L3-PCP-D`, `L3-AETI-D`, `AGERA5-ET0-E` all
  resolve identically to pre-refactor behavior; `devtools::document()`
  produced no new NAMESPACE/man diffs.

### 2026-09-16 (continued) — Metadata/API module dedup (Phase 7.0)

- **7.0** — Fixed a duplicate `%||%` with conflicting semantics
  (`R/utils.R` vs `R/wapor_metadata_cache.R`; no `Collate:` field means
  alphabetical load order decided which one silently won for ~40 call
  sites) and consolidated the level->workspace-URL mapping (previously
  hardcoded independently in `R/api_client.R`, `R/wapor_metadata_cache.R`,
  `R/metadata.R`) into one `.wapor_level_workspace_url()` helper in
  `R/api_client.R`. See `IMPROVEMENT_PLAN.md` Phase 7 and
  `ISS-20260916-002`. Verified: `devtools::load_all()` clean,
  `devtools::document()` produced no unexpected diffs, full suite
  `0 fail / 1019 passed` (the intermediate `%||%` deletion caused a
  transient `1 fail / 1018 passed` in `test-wapor_metadata_cache.R:104`
  before the length-aware semantics were restored in `R/utils.R`).

### 2026-09-16 — Cross-model coordination board + live dashboard

- Added `agent-workflow/agents-board.json`: the shared, machine-readable
  ledger of tasks/issues/sessions with a `model` field (claude, codex,
  gemini, hermes, antigravity, warp, ...) so any model sees who is working on
  what before starting. `START-HERE.md` now requires claiming/releasing tasks
  in it via `agent-workflow/scripts/board_claim.ps1`; `agent_preflight.ps1`
  surfaces other models' active claims at session start.
- Added `agent-workflow/dashboard/` — a Streamlit app
  (`agent-workflow/scripts/run_dashboard.ps1` to launch) that reads
  `agents-board.json` live: active/pending/blocked/done tasks by model, open
  issues, decisions needing the maintainer, and a mermaid module map of
  `R/`/`inst/shiny/`. Separate from `inst/shiny/app.R` (the package's own
  Shiny dashboard) — this is a maintainer-only monitoring tool, ships nothing
  to package users.
- Verified: `python -m json.tool` on `agents-board.json` (valid), `py_compile`
  on `app.py` (clean), `streamlit run` served HTTP 200 on a local port, then
  stopped.

### 2026-09-15 (session 2c) — S4 synchronized dual-map

- **S4** — New `inst/shiny/mod_dual_map.R` module: two independent leaflet
  maps (`map_left`, `map_right`), each with its own raster/band/palette
  selector reading from the shared project folder, kept in view-sync
  (pan/zoom) via `leaflet.extras2::addLeafletsync()` when the "Lock pan &
  zoom" checkbox is on, and `leaflet.extras2::unsync()` when off. Distinct
  from the existing "Dual Compare" overlay mode in `mod_visualisation.R`
  (which draws two rasters on ONE map) — this is two separate,
  independently full-screenable map panes.
  - Capability-guarded: `.wapor_dual_map_available()` checks for
    `leaflet.extras2::addLeafletsync` and the UI falls back to an
    actionable install-instructions alert if the package is missing,
    matching the existing `.check_shiny_deps()` pattern for optional
    Suggests packages (`leaflet.extras2` was already a Suggests dependency).
  - Wired as a new "Dual Compare" nav tab in `app.R`, sourced alongside the
    other modules and passed the shared `dl_out$folder` / `dl_out$region`.
  - Verified: `install.packages("leaflet.extras2")` (was missing locally,
    confirmed API: `addLeafletsync(map, ids, synclist, options)`,
    `unsync(map)`); `parse()` OK on both files; `devtools::load_all()` OK;
    `shiny::shinyAppFile("app.R")` builds the full UI/server object
    including the new tab with no errors; `devtools::test()` for
    `dashboard-validation` and `analysis-shiny` — 0 failures, 96 passed.

### 2026-09-15 (session 2b) — S2 numbered step accordion wizard

- **S2** — `inst/shiny/mod_download.R` sidebar restructured from a 2-panel
  ("Data Selection" / "Output Settings") accordion into a 5-step numbered
  wizard accordion: (1) Project (folder + AOI), (2) Variables, (3) Period,
  (4) L3 Region, (5) Run (file options, unit conversion, download button).
  Each panel title carries a circular numbered badge (new `.wizard-step-num`
  CSS class in `inst/shiny/app.R`). The sticky footer "Download Data" button
  is now a convenience shortcut that opens the Run step
  (`bslib::accordion_panel_open(..., values = "5")`); the actual download
  trigger stays a single `input$download_btn` observer in the Run panel, and
  both buttons share one `iv$is_valid()` enable/disable condition.
  No server-side reactive logic changed — only DOM organization moved.
  Verified: `parse()` on both files OK; `devtools::load_all()` OK;
  `shiny::shinyAppFile("app.R")` builds the full UI/server object with no
  errors (only routine package-masking warnings); `devtools::test()` for
  `dashboard-validation` and `analysis-shiny` — 0 failures, 96 passed.

### 2026-09-15 (session 2) — B2/P2/D2 blob store rewrite

- **B2/P2/D2** — `wapor_save_raster_blobs()` in `R/wapor_monitoring.R`
  rewritten as one coherent change:
  - Pending dates are resolved from URL metadata before opening any remote
    dataset, so already-saved dates never trigger a network open.
  - Remaining layers for one variable are opened as a single batched
    `/vsicurl/` multi-band `terra::rast()` call instead of one dataset handle
    per layer (falls back to per-layer open only if the batch open errors).
  - Each finished layer is written both as the existing in-memory compressed
    GeoTIFF blob (read path unchanged, backward compatible) and as a
    file-backed COG via `wapor_write_cog()` under a new
    `.wapor_monitoring_raster_store_dir()` helper (sibling `_raster_store/`
    directory next to the DuckDB file, or a tempdir fallback for in-memory
    connections).
  - `monitoring_rasters` INSERT/UPDATE now also carries `raster_path`,
    `gdal_version`, `terra_version`, `nodata`, and `band_count` (schema
    columns already existed from the prior session; write path now
    populates them).
  - Verified: `devtools::test()` full suite — 0 failures, 1 pre-existing
    unrelated warning, 6 skipped (live API), 764 passed. Standalone smoke
    test confirmed `raster_path` round-trips to an existing COG file on
    disk with correct provenance columns.

### 2026-09-15 (session 1) — Production Hardening Pass

- **B1** — `app.R`: replaced bare `library()` calls with `.check_shiny_deps()`
  guard + `library()` after check.
- **B3** — DuckDB `schema_version` added to `monitoring_metadata` table +
  `.wapor_monitoring_migrate()` migration helper.
- **B4** — `wapor_write_cog`: BIGTIFF threshold now uses `.dtype_bytes` lookup
  table for correct byte-width per datatype.
- **B5** — All 9 network-dependent test files have `skip_if_wapor_offline()`
  guard added.
- **P1** — `.onLoad` now calls `wapor_configure_gdal()` unconditionally (was
  env-gated behind `RWAPOR_AUTO_CONFIG="true"`).
- **P3** — `wapor_suggest_tile_size()` helper added and exported in NAMESPACE.
- **P4** — `on_batch_done` callback wired into `wapor_ts` and `wapor_map`.
- **D1** — `raster_grid_registry` DuckDB table + `.wapor_validate_raster_grid()`
  helper.
- **D3** — INSERT OR REPLACE upsert via temp table in `farm_timeseries` writer.
- **D4** — `season_id` column added to `farm_timeseries` + PRIMARY KEY updated.
- **S1** — `wapor_grouped_var_choices()` added; `mod_download` uses it.
- **S3** — `wapor_save_analysis_config()` / `wapor_load_analysis_config()` added
  in `utils_shiny.R`.
- **S5** — User-adjustable stress threshold `numericInput`s added to dashboard
  UI and server wired.

### 2026-09-03

- WaPOR seasonal download robustness pass: SHA-256 disk-cache key, retry with
  backoff, `missing_periods` reconciliation, `Retry-After`-aware API retries.
- Created `agent-workflow/` hub (was referenced everywhere but did not exist).
- Added pointer headers to all fable-skill-managed adapter files.
