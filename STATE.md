# Rwapor Production Hardening — STATE
Session: 2026-09-15 (session 2, CLOSED)
Tier: FULL | Domain: CODE
Agent: Claude Code (claude-sonnet-5)

## Session 1 Outcome: 13/18 items completed (see agent-workflow/task-status.md)

## Session 2 Outcome: all 3 handoff priority items complete

- [x] B2/P2/D2  wapor_save_raster_blobs rewrite (batch vsicurl + blob + file-backed COG)
- [x] S2        Dashboard: numbered step accordion wizard (5 steps)
- [x] S4        Dashboard: synchronized dual-map (leaflet.extras2 sync)

## Summary of changes this session

1. **R/wapor_monitoring.R** — `wapor_save_raster_blobs()` rewritten:
   pending dates resolved before any network open; layers for one variable
   opened as a single batched `/vsicurl/` multi-band stack; each finished
   layer writes both the existing in-memory blob and a file-backed COG under
   a new `.wapor_monitoring_raster_store_dir()` helper; `monitoring_rasters`
   writes now populate `raster_path`, `gdal_version`, `terra_version`,
   `nodata`, `band_count`.

2. **inst/shiny/mod_download.R**, **inst/shiny/app.R** — sidebar restructured
   into a 5-step numbered accordion wizard: Project, Variables, Period,
   L3 Region, Run. New `.wizard-step-num` CSS badge class. Sticky footer
   button now opens the Run step instead of duplicating the trigger logic.

3. **inst/shiny/mod_dual_map.R** (new), **inst/shiny/app.R** — synchronized
   side-by-side dual-map "Dual Compare" tab using
   `leaflet.extras2::addLeafletsync()` / `unsync()`, with a graceful
   install-instructions fallback if `leaflet.extras2` is missing.

## Verification (session 2, cumulative)

- `parse()` clean on every touched file.
- `devtools::load_all(".")` loads cleanly throughout.
- Standalone smoke test for the blob rewrite: COG file exists on disk,
  `raster_path` round-trips with correct provenance columns — PASS.
- `shiny::shinyAppFile("app.R")` builds the full UI/server object with the
  new wizard accordion and the new Dual Compare tab, no errors.
- `devtools::test()` full suite (after blob rewrite): **FAIL 0 | WARN 1
  (pre-existing, unrelated) | SKIP 6 (live API) | PASS 764**.
- `devtools::test(filter='dashboard-validation|analysis-shiny')` (after S2
  and S4): **FAIL 0 | WARN 0 | SKIP 0 | PASS 96**.
- Installed missing local packages needed for smoke testing:
  shinyFiles, shinyvalidate, shinyAce, shinycssloaders, leaflet.extras2.

## Next Session — Start Here

Priority order (from IMPROVEMENT_PLAN.md, all currently open):
1. Phase 1.5 — Explicit L3 Selection / Mosaic-All Coverage Policy: wire the
   already-landed core R implementation (`feat/l3-mosaic-tiled-core`) into
   the Shiny L3 selection UI (`inst/shiny/mod_download.R` Step 4,
   `inst/shiny/mod_analysis.R`). Currently the core resolver
   (`wapor_resolve_l3_selection`, `wapor_shiny_l3_choices`,
   `wapor_shiny_l3_selection` in R/wapor_cog.R) exists but the dashboard
   does not yet present the "Mosaic all intersecting L3 regions" option.
2. Phase 1.6 — Explicit Alignment Reference (`reference_layer` parameter).
3. Phase 2.2 — COG Write Support in `wapor_map`/`wapor_run_seasonal_analysis`
   (note: `wapor_write_cog()` already exists in R/wapor_cog.R and is now
   used by the monitoring blob store — this item is about exposing a
   `cog = FALSE` parameter on the public download/analysis entry points).
4. Then 2.3, 3.1, 3.3, 3.4, 3.5, 4.1, 4.2, 5.1, 5.2, 5.3, 6.1, 6.2 as
   bandwidth allows — see `agent-workflow/task-status.md` for full list.

## Key Decisions (carry forward)

- Use requireNamespace(pkg, quietly=TRUE) with stop() fallback in app.R
- schema_version: INTEGER stored in monitoring_metadata table
- BIGTIFF fix: lookup table for bytes per datatype string
- All test guards: skip_if_wapor_offline() on every network-calling test file
- Blob store: keep the in-memory blob column as the primary read path for
  backward compatibility; raster_path is additive provenance, not a
  replacement — do not remove raster_blob reads until all Shiny consumers
  are migrated to reading from raster_path.
- Raster store directory convention: `<dbdir>_raster_store/` sibling to the
  DuckDB file; `<variable>_<date_key>.tif` naming.
- Wizard accordion pattern: use `value = "N"` on `accordion_panel()` and
  `bslib::accordion_panel_open(id, values = "N", session = session)` to
  jump between steps programmatically; keep exactly one server-side trigger
  observer per real action, with shortcut buttons only opening the relevant
  step rather than duplicating the trigger logic.
- Optional Suggests packages used by a single dashboard feature (e.g.
  leaflet.extras2 for dual-map sync) should be capability-guarded at the
  module level (UI fallback + `invisible(NULL)` early return in the server),
  not added to the hard `.RWAPOR_SHINY_PKGS` dependency list, so the rest of
  the dashboard still works if that one optional package is absent.

## Modified / New Files (uncommitted as of this update)

R/analysis_tiled.R, R/gdal_config.R, R/wapor_cog.R, R/wapor_map.R,
R/wapor_monitoring.R, R/wapor_ts.R, NAMESPACE,
agent-workflow/change-log.md, agent-workflow/session-brief.md,
agent-workflow/task-status.md,
inst/shiny/app.R, inst/shiny/mod_download.R, inst/shiny/mod_monitoring.R,
inst/shiny/utils_shiny.R, inst/shiny/mod_dual_map.R (new),
tests/testthat/helper-skip.R, tests/testthat/test-coverage-partial.R,
tests/testthat/test-l3-api.R, tests/testthat/test-l3-mosaic-all.R,
tests/testthat/test-plan_wapor_time_slices.R, tests/testthat/test-seasonal_download.R,
tests/testthat/test-wapor_metadata_cache.R
