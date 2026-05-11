# Issues Log

_Last updated: 2026-05-11_

## Open Issues

- [ ] Analysis-tab plot previews can fail with `figure margins too large` and leave the graphics device in an invalid state.
  - ID: ISS-20260511-007
  - First noted: 2026-05-11
  - Symptoms: opening the Analysis tab with a crop mask or Kc preview available can raise `graphics::plot.new: figure margins too large`, followed by `invalid graphics state` on resize/replay for `an_crop_mask_plot` and `an_kc_plot`.
  - Root cause: `inst/shiny/mod_analysis.R` rendered both previews into `300px` plot devices inside card/tab containers; the available device area could become too small once container chrome, margins, and legend space were applied, and the failed draw then poisoned later saved-plot replay.
  - Fix applied: increased the Analysis preview plot heights in `inst/shiny/mod_analysis_ui_body.R`, reset `par()` safely around both renderers, removed the crop-mask auto legend, and tightened the Kc legend sizing/inset to reduce device pressure.
  - Files changed: `inst/shiny/mod_analysis.R`, `inst/shiny/mod_analysis_ui_body.R`
  - Automated verification: parsed both touched files successfully with `Rscript` on 2026-05-11.
  - Remaining validation: manually open the Analysis tab with crop-mask and Kc previews visible, resize the window, and confirm both plots render without warnings.

- [ ] Generated/handwritten analysis scripts can pass `peff` while the engine only recognizes `agg_peff`.
  - ID: ISS-20260511-008
  - First noted: 2026-05-11
  - Symptoms: analysis scripts derived from the Shiny indicator UI can include `peff`, while engine checks and save helpers key off `agg_peff`; this creates version-sensitive failures and inconsistent behavior between Shiny, scripts, and installed-package runs.
  - Root cause: the Analysis sidebar uses `peff` as the derived-indicator choice value, but the analysis engine and related helpers were written against the internal canonical name `agg_peff`.
  - Fix applied: added `wapor_normalize_analysis_indicators()` and applied it in script generation, the seasonal-analysis engine, and raster-save helper so `peff` is normalized to `agg_peff`.
  - Files changed: `R/analysis_utils.R`, `R/analysis_engine.R`, `tests/testthat/test-analysis-shiny.R`
  - Automated verification: `testthat::test_file('tests/testthat/test-analysis-shiny.R')` passed on 2026-05-11, including a new normalization regression test; the patched workspace code also completed the real `C:/Users/almut/Desktop/Kyrgystan` batch analysis with `peff` in the indicator list.
  - Remaining validation: reinstall or load the updated package before rerunning standalone scripts that use `library(Rwapor)`.

- [ ] `beneficial_fraction` can return no result when selected without `agg_t`.
  - ID: ISS-20260512-009
  - First noted: 2026-05-12
  - Symptoms: running the real `C:/Users/almut/Desktop/Kyrgystan` batch analysis one indicator at a time showed `beneficial_fraction` was the only failing indicator; the run completed but the expected `beneficial_fraction` raster was missing from each season result.
  - Root cause: `R/analysis_engine.R` loaded the transpiration stack for `beneficial_fraction`, but only aggregated `seasonal_t` when `agg_t` was explicitly selected, leaving the derived fraction with no transpiration input.
  - Fix applied: widened the `seasonal_t` aggregation guard so it runs for either `agg_t` or `beneficial_fraction`, and added a regression test that exercises `beneficial_fraction` without `agg_t`.
  - Files changed: `R/analysis_engine.R`, `tests/testthat/test-analysis-shiny.R`
  - Automated verification: `testthat::test_file('tests/testthat/test-analysis-shiny.R')` passed on 2026-05-12; the patched workspace code now returns `beneficial_fraction` for both `Winter 2024` and `Winter 2025` in the real `Kyrgystan` dataset.
  - Remaining validation: reinstall or load the updated package code before rerunning standalone scripts that use `library(Rwapor)`.

- [ ] Batch-mode local analysis can destabilize the Shiny session and disconnect the R console session.
  - ID: ISS-20260511-002
  - First noted: 2026-05-11
  - Symptoms: when running multi-season analysis against local downloaded rasters, the Shiny app remains open but the session disconnects and analysis stops; the generated script also does not reliably reflect the configured batch workflow.
  - Likely root cause: `inst/shiny/mod_analysis.R` still mixes single-period and batch-period assumptions in validation, local data coverage checks, and run setup, while script preview is split between a generator path and a generic fallback.
  - Fix applied: normalized Shiny analysis config assembly, added batch parsing and season-aware local checks, unified script preview/export generation, and updated the engine to treat named period lists consistently.
  - Files changed: `inst/shiny/mod_analysis.R`, `R/analysis_utils.R`, `R/analysis_engine.R`, `inst/shiny/mod_analysis_ui_body.R`, `tests/testthat/test-analysis-shiny.R`
  - Automated verification: `pkgload::load_all('.')` with `testthat::test_file('tests/testthat/test-analysis-shiny.R')` and `testthat::test_file('tests/testthat/test-analysis.R')` both passed on 2026-05-11.
  - Follow-up fix: `R/analysis_utils.R` now emits R-safe escaped string literals for generated scripts, covering Windows `C:\...` paths that previously produced `'\U' used without hex digits`.
  - Remaining validation: manually confirm the Shiny UI no longer disconnects during a local multi-season run and that the downloaded `.R` script matches the configured workflow end-to-end.

- [ ] Analysis-tab local folder scan can target the output folder instead of the intended project-data folder.
  - ID: ISS-20260511-004
  - First noted: 2026-05-11
  - Symptoms: clicking `Re-scan Folder` in Analysis can inspect a different folder than the Download tab project folder; users also cannot explicitly point Analysis at a previous-session project directory.
  - Likely root cause: `inst/shiny/mod_analysis.R` overloaded `an_folder` as both output folder and local-data source, while the sidebar only exposed that single path.
  - Fix applied: split Analysis into a `project folder` source selector and a separate `analysis output folder`, defaulted local mode to the shared Download tab folder, added an Analysis-local folder override, and updated script generation to preserve the separation.
  - Files changed: `inst/shiny/mod_analysis.R`, `inst/shiny/mod_analysis_ui_sidebar.R`, `R/analysis_utils.R`
  - Automated verification: `pkgload::load_all('.')` plus direct sourcing of `inst/shiny/mod_analysis*.R` and `inst/shiny/utils_shiny.R` passed on 2026-05-11.
  - Remaining validation: manually confirm `Re-scan Folder` now follows the active project folder and that switching to an older project directory in Analysis works end-to-end.

- [ ] `Detect from Folder` in Analysis can disconnect the Shiny session when folder parsing fails unexpectedly.
  - ID: ISS-20260511-005
  - First noted: 2026-05-11
  - Symptoms: clicking `Detect from Folder` for season selection can terminate the active Shiny connection instead of returning a user-facing warning or detected batch list.
  - Likely root cause: the observer in `inst/shiny/mod_analysis.R` performed direct folder scanning and filename parsing inline without guarding filesystem and pattern-matching failures.
  - Fix applied: moved season-window detection into `R/analysis_utils.R::wapor_detect_folder_seasons()`, wrapped the observer in `tryCatch`, and converted empty/non-matching cases into notifications instead of uncaught session-breaking errors.
  - Files changed: `inst/shiny/mod_analysis.R`, `R/analysis_utils.R`, `tests/testthat/test-analysis-shiny.R`
  - Automated verification: `testthat::test_file('tests/testthat/test-analysis-shiny.R')` passed on 2026-05-11, including the new season-detection regression test.
  - Remaining validation: manually click `Detect from Folder` in the dashboard against both valid and invalid project folders and confirm the session stays alive.

## Resolved Improvements

- [x] Download-tab AOI upload flow exposed two competing local-file entry points and felt unnecessarily complex.
  - ID: ISS-20260511-006
  - Resolved: 2026-05-11
  - Root cause: `inst/shiny/mod_aoi.R` presented both a folder browser and a direct file picker for the same AOI-upload task, increasing UI complexity without adding much value.
  - Fix applied: collapsed the upload mode to a single `Browse AOI Files` entry point backed by the local file explorer and kept favorites/project assets intact.
  - Files: `inst/shiny/mod_aoi.R`
  - Validation: Shiny module load check passed; manual dashboard verification still recommended.

- [x] Download-tab AOI local file explorer did not expose directories clearly enough to navigate local vector assets.
  - ID: ISS-20260511-003
  - Resolved: 2026-05-11
  - Root cause: `inst/shiny/mod_aoi.R` relied mainly on a direct file picker flow, which made folder-by-folder exploration weak in the AOI upload UI.
  - Fix applied: added a folder-first AOI explorer with `shinyDirChoose`, current-folder display, up/refresh controls, visible subfolder and supported-file lists, and kept the direct file picker as a fallback.
  - Files: `inst/shiny/mod_aoi.R`
  - Validation: R parse/load check of the updated module; manual Shiny verification still recommended for the interactive explorer flow.

- [x] Parallel agent memory drift
  - ID: ISS-20260511-001
  - Resolved: 2026-05-11
  - Root cause: project state was split across multiple agent-specific files and partially stale repo docs.
  - Fix applied: introduced `agent-workflow/` as the shared source of truth and repointed the main adapters and hooks toward it.
  - Files: `agent-workflow/*`, `AGENTS.md`, `CLAUDE.md`, `.agent/PROJECT.md`, `.github/agents/*`, `.claude/settings.json`
  - Validation: shared startup order, memory location, and closeout path are now centralized in repo-owned files.
  - Regression test: run `agent_preflight.ps1` before work and keep model-specific docs as pointers only.
