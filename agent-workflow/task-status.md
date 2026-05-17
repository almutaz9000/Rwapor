# Task Status

_Last updated: 2026-05-13_

## Active

- [ ] Refer to `.jules/bolt.md` for Jules-specific active tasks.

## Recently Completed

- [x] Archived development-only assets to `dev-archive/2026-05-production-cleanup/` and moved utility scripts to `dev-tools/scripts/` with updated path references (2026-05-14).
- [x] Hardened dashboard dependency checks to include async runtime packages (2026-05-13).
- [x] Made `wapor_validate_analysis_config()` non-throwing for malformed period dates and added regression tests (2026-05-13).
- [x] Replaced silent Analysis module sourcing with explicit startup failures and improved diagnostics (2026-05-13).
- [x] Added Shiny app runtime restoration for `future::plan()` and future-related options on app stop (2026-05-13).
- [x] Ran `devtools::test()` and `devtools::check(document = FALSE, manual = FALSE, cran = FALSE)` after fixes (2026-05-13).
- [x] Improved folder-selection UI in Download and Analysis tabs (2026-05-12).
- [x] Fixed four bugs in `mod_analysis.R`: duplicate observer, auto-scan performance, code-preview path escaping, fav reset.

## Pending

- [ ] Refer to `.jules/bolt.md` for Jules-specific pending tasks.

## Completed Recently

- [x] Surfaced the shared workflow in `README.md` (2026-05-14).
- [x] Relaxed `.gitignore` for shared agent adapter files (2026-05-14).
- [x] Updated `vignettes/getting-started.Rmd` with automatic temperature conversion and dekadal default documentation (2026-05-14).
- [x] Approved the shared agent workflow design.
- [x] Wrote the design spec at `docs/superpowers/specs/2026-05-11-agent-workflow-design.md`.
- [x] Wrote the Shiny batch-analysis implementation plan at `dev-archive/2026-05-production-cleanup/improvements/P4_shiny_batch_analysis.md`.
- [x] Implemented the Shiny batch-analysis and script-generation patch with regression tests.
- [x] Separated the Analysis tab local project-data source from the analysis output folder and added a project-folder override in Analysis.
- [x] Hardened Analysis `Detect from Folder` with a tested helper and safe notification path.
- [x] Simplified the download-tab AOI loader to a single browser-driven file flow.
- [x] Added `agent-workflow/`, shared templates, and workflow scripts.
- [x] Repointed the main repo adapters, hooks, and memory entrypoints to `agent-workflow/`.
