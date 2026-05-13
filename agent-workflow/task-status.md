# Task Status

_Last updated: 2026-05-13_

## Active

- [ ] Manually verify dashboard startup + shutdown behavior in an interactive Shiny session.
  - Scope: confirm module-source failures are explicit and async runtime state is restored after app close.
  - Next action: launch `run_wapor()` from a clean session and validate close/relaunch behavior.

## Recently Completed

- [x] Hardened dashboard dependency checks to include async runtime packages (2026-05-13).
- [x] Made `wapor_validate_analysis_config()` non-throwing for malformed period dates and added regression tests (2026-05-13).
- [x] Replaced silent Analysis module sourcing with explicit startup failures and improved diagnostics (2026-05-13).
- [x] Added Shiny app runtime restoration for `future::plan()` and future-related options on app stop (2026-05-13).
- [x] Ran `devtools::test()` and `devtools::check(document = FALSE, manual = FALSE, cran = FALSE)` after fixes (2026-05-13).
- [x] Improved folder-selection UI in Download and Analysis tabs (2026-05-12).
- [x] Fixed four bugs in `mod_analysis.R`: duplicate observer, auto-scan performance, code-preview path escaping, fav reset.

## Pending

- [ ] Reinstall or load the updated package code before rerunning standalone analysis scripts generated from the Shiny UI.
- [ ] Reinstall or load the updated package code before rerunning standalone indicator-by-indicator analysis scripts that use `beneficial_fraction`.
- [ ] Manually verify the Analysis crop-mask and Kc preview plots render cleanly and survive window resize without graphics warnings.
- [ ] Manually verify the patched Shiny batch workflow with local multi-season rasters and confirm the R console session stays connected.
- [ ] Manually verify the Analysis tab project-folder override and confirm `Re-scan Folder` follows the active source folder instead of the output folder.
- [ ] Manually verify that Analysis `Detect from Folder` no longer disconnects the session for valid and invalid project folders.
- [ ] Manually verify the simplified download-tab AOI browser flow with nested folders and representative vector files on Windows.
- [ ] Decide whether to surface the shared workflow in human-facing contributor docs such as `README.md`.
- [ ] Decide whether to relax `.gitignore` for selected adapter files (`CLAUDE.md`, `.agent/*`, `.github/agents/*`) if you want those pointers shared through Git instead of local-only.
- [ ] Run the package test follow-up for the earlier temperature-conversion work when that code path is next touched.
- [ ] Update user-facing docs for automatic temperature conversion and dekadal defaults in a future documentation pass.

## Completed Recently

- [x] Approved the shared agent workflow design.
- [x] Wrote the design spec at `docs/superpowers/specs/2026-05-11-agent-workflow-design.md`.
- [x] Wrote the Shiny batch-analysis implementation plan at `improvements/P4_shiny_batch_analysis.md`.
- [x] Implemented the Shiny batch-analysis and script-generation patch with regression tests.
- [x] Separated the Analysis tab local project-data source from the analysis output folder and added a project-folder override in Analysis.
- [x] Hardened Analysis `Detect from Folder` with a tested helper and safe notification path.
- [x] Simplified the download-tab AOI loader to a single browser-driven file flow.
- [x] Added `agent-workflow/`, shared templates, and workflow scripts.
- [x] Repointed the main repo adapters, hooks, and memory entrypoints to `agent-workflow/`.
