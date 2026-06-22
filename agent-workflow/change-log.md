# Agent Workflow Change Log

## 2026-06-22

- Added internal `wapor_masked_std()` using native `terra` raster operations to calculate weighted standard deviations of raster time series based on season weights.
- Added `wapor_calc_seasonal_std()` and `wapor_calc_monthly_weighted_std_rasters()` for calculating seasonal and monthly standard deviations of any variables (AETI, RET, PCP, NPP, T, E, etc.).
- Integrated the standard deviation indicators (`agg_aeti_std`, `agg_ret_std`, `agg_pcp_std`, `agg_biomass_std`) into the analysis pipeline `wapor_analysis_pipeline()` and `.compute_seasonal_aggregations()`.
- Updated the pipeline output saving function to write standard deviation rasters (`_seasonal_aeti_std.tif`, `_seasonal_ret_std.tif`, `_seasonal_biomass_std.tif`, `_seasonal_pcp_std.tif`) to disk.
- Added unit tests in `tests/testthat/test-variability-indicators.R` and successfully ran the full test suite (`FAIL 0 | WARN 0 | SKIP 5 | PASS 546`).

## 2026-06-08

- Narrowed the public download `unit_conversion` interface in `wapor_map()` and `wapor_ts()` to two safe modes: `"unit_conversion"` and `"none"`.
- Kept dynamic default behavior so dekadal daily-rate products save/extract as dekadal totals while monthly products remain monthly totals.
- Updated the Shiny Download tab to expose only the two safe unit-conversion choices and to generate matching script code.
- Added regression coverage for monthly preservation in mixed monthly/dekadal workflows and for rejection of the old explicit target-unit values.
- Regenerated package documentation and reran `devtools::test()` successfully (`FAIL 0 | WARN 0 | SKIP 5 | PASS 521`).

## 2026-05-13

- Added `.wapor_dashboard_required_pkgs()` and extended `run_wapor()` dependency precheck to include async runtime packages (`future`, `promises`).
- Hardened `wapor_validate_analysis_config()` period handling to safely parse invalid dates and report validation errors without throwing.
- Replaced silent source calls in `inst/shiny/mod_analysis.R` with explicit guarded loaders and actionable error messages.
- Added guarded module sourcing plus runtime state restoration (`future::plan()` and options) in `inst/shiny/app.R` for cleaner app shutdown behavior.
- Added regression tests in `tests/testthat/test-dashboard-validation.R`.
- Replaced full `par(no.readonly=TRUE)` save/restore in Analysis preview plots with selective `mar`/`mgp` restore to avoid `pin` errors on resized devices.
- Added regression test in `tests/testthat/test-analysis-shiny.R` to prevent reintroduction of full `par` restore patterns in `mod_analysis.R`.
- Re-ran `devtools::test()` and `devtools::check(document = FALSE, manual = FALSE, cran = FALSE)` with zero failures.

## 2026-05-14

- Reorganized the repository into a cleaner production layout by moving development-only assets under `dev-archive/2026-05-production-cleanup/`.
- Moved ad hoc scripts from `scripts/` to `dev-tools/scripts/` to keep package runtime paths focused (`R/`, `inst/`, `man/`, `tests/testthat/`, `vignettes/`).
- Updated debugging references and graph indexing exclusions to the new script/archive paths.
- Updated the FAO crop-data refresh script to resolve repo-root output paths even after relocation.
- Added repository structure documentation for agents and contributors at `docs/REPOSITORY_STRUCTURE.md`.

## 2026-05-12

- Fixed the Analysis plot previews in `inst/shiny/mod_analysis.R` and `inst/shiny/mod_analysis_ui_body.R` so small embedded devices no longer trip `figure margins too large` / `invalid graphics state`.
- Normalized the Analysis `peff` indicator alias to canonical `agg_peff` across script generation, the seasonal-analysis engine, and save helpers.
- Added a regression test covering indicator normalization and revalidated `tests/testthat/test-analysis-shiny.R`.
- Confirmed the current workspace code completes the real `C:/Users/almut/Desktop/Kyrgystan` batch analysis when run from source.
- Tested the `Kyrgystan` indicators one by one and fixed `beneficial_fraction` so it no longer depends on explicitly selecting `agg_t`.
- Added the structured analysis export helper, updated generated scripts to use it, and validated the new folder layout plus regression coverage.
- Improved folder selection across Download and Analysis tabs: path-existence badge, Create Folder button, basename-only favorites dropdown, auto-reset after favorite selection.
- Augmented `get_shinyfiles_roots()` in `utils_shiny.R` to include Desktop / Downloads / Documents shortcuts.
- Fixed duplicate `observeEvent(input$an_crop_mask)` in `mod_analysis.R`; merged L3 auto-detection into the single remaining observer.
- Fixed auto-scan observer to fire only on data-source switch, not on every folder keystroke.
- Fixed Windows backslash paths in download code-preview (using `normalizePath(..., winslash="/")`).
- Added `folder-status-badge` CSS to `premium_style.css`.
- Replaced `.jules/bolt.md` with a thin Jules adapter that starts from `agent-workflow/START-HERE.md`, uses `task-status.md` as the pending-work queue, and routes durable learnings back into `agent-workflow/project-memory.md`.

## 2026-05-11

- Added the shared `agent-workflow/` coordination layer.
- Added root `AGENTS.md` as the cross-model entrypoint.
- Migrated durable project memory into `agent-workflow/project-memory.md`.
- Started repointing repo-local adapters, skills, and hooks away from parallel memory paths.
- Validated `agent_preflight.ps1`, `agent_digest.ps1`, and `agent_closeout.ps1` from the repo root.
- Added the Shiny batch-analysis design spec at `docs/superpowers/specs/2026-05-11-shiny-batch-analysis-design.md`.
- Added the Shiny batch-analysis implementation plan at `dev-archive/2026-05-production-cleanup/improvements/P4_shiny_batch_analysis.md`.
- Logged `ISS-20260511-002` for the multi-season local-analysis session disconnect and script-preview drift.
- Implemented the Shiny batch-analysis patch and added regression tests for batch parsing, batch scripts, and named-list period handling.
- Fixed generated script escaping for Windows paths after a follow-up `\U` parse error report.
