# Session Brief

_Last updated: 2026-05-14_

## Active Focus

- Evaluated and decided against surfacing the AI agent workflow in human-facing README.md to keep the final production version clean of agent icon files.
- Replaced dynamic function resolution via `getFromNamespace` with explicit namespace prefixes inside `inst/shiny/utils_shiny.R` and `inst/shiny/mod_analysis.R` for cleaner local development and loading.
- Implemented comprehensive unit tests for `wapor_convert_temperature()` in `tests/testthat/test-wapor.R`.
- Relaxed `.gitignore` for shared agent configuration files (`bolt.md`, `CLAUDE.md`, `.agent/PROJECT.md`, `.github/agents/*`) to support Git-tracked coordination pointers.
- Migrated primary configuration from `.jules/bolt.md` to root `bolt.md` as requested.
- Shared agent coordination now starts from `bolt.md` which points to `agent-workflow/START-HERE.md`.
- Reorganized development-only repository assets into `dev-archive/2026-05-production-cleanup/` and moved utility scripts to `dev-tools/scripts/` for a cleaner production-facing root.
- Implemented batch-analysis patch; added regression coverage in `tests/testthat/test-analysis-shiny.R`.
- Patched Windows-safe script serialization (`’\U’ used without hex digits` follow-up).
- Improved download-tab AOI local explorer in `inst/shiny/mod_aoi.R`.
- Separated Analysis tab project-data source from output folder; added project-folder override.
- Hardened crop-mask and Kc preview plots (`figure margins too large` fix).
- Normalized `peff` → `agg_peff` across script generation and seasonal-analysis engine.
- Fixed `beneficial_fraction` — no longer requires explicit `agg_t` selection.
- Added `wapor_export_analysis_outputs()` for structured seasonal/dekadal/monthly exports.
- Improved folder-selection UX: path-existence badge, Create Folder button, readable favorites, better shinyFiles roots.
- Fixed four bugs in `mod_analysis.R`: duplicate crop-mask observer, auto-scan on keystroke, Windows path in code preview, silent `an_incremental` FALSE.
- Added a Jules adapter in `.jules/bolt.md` that points online Jules work to `agent-workflow/` for startup, pending tasks, issue logging, and validated commits.
- Hardened dashboard startup dependency checks to include async runtime packages (`future`, `promises`).
- Made `wapor_validate_analysis_config()` robust to malformed period dates (returns validation errors instead of throwing).
- Replaced silent Analysis UI sourcing with explicit error messages if module files fail to load.
- Added Shiny app runtime-state restoration for `future::plan()` and `options()` on app shutdown.
- Added regression tests in `tests/testthat/test-dashboard-validation.R` for dashboard dependencies and date-validation behavior.
- Fixed Shiny preview plotting to avoid restoring full `par()` state (prevents device-size-dependent `pin` errors on resize).
- Added regression coverage in `tests/testthat/test-analysis-shiny.R` to guard against reintroducing full `par(no.readonly=TRUE)` restore patterns.

## Top Open Issues

- `ISS-20260511-002`: code fix is in place, but manual Shiny verification is still pending for the multi-season local session-disconnect scenario.

## Recently Resolved

- `ISS-20260514-016`: .gitignore fully excluded shared agent adapter and config files; relaxed ignore rules with selective un-ignores (`!`) to support Git tracking of `CLAUDE.md`, `.agent/PROJECT.md`, `.claude/settings.json`, and `.github/agents/*`.
- `ISS-20260512-010`: standalone Shiny module can fail to find internal helper functions; fixed by explicit namespace referencing and replacing dynamic `getFromNamespace` resolution.
- `ISS-20260511-001`: workflow drift fixed by centralizing memory, task state, and issue state under `agent-workflow/`.
- `ISS-20260513-011`: dashboard startup precheck now includes async runtime dependencies.
- `ISS-20260513-012`: analysis config validation no longer throws on malformed dates.
- `ISS-20260513-013`: app/module startup now fails explicitly on source errors and restores async global state on shutdown.

## Pending Tasks

- [ ] Use the shared workflow during the next substantial multi-model task and remove any friction it exposes.
- [ ] Decide whether to surface the workflow in `README.md` or other human-facing docs.
- [ ] Manually verify the patched Shiny batch workflow with local multi-season rasters and confirm the session no longer disconnects.
- [ ] Reinstall or load the updated package code before rerunning standalone analysis scripts generated from the Shiny UI.
- [ ] Reinstall or load the updated package code before rerunning standalone indicator-by-indicator analysis scripts that include `beneficial_fraction`.
- [ ] Manually verify that Analysis `Re-scan Folder` follows the active project folder and that the Analysis-local project-folder override works with older downloads.
- [ ] Manually verify that Analysis `Detect from Folder` no longer disconnects the session.
- [ ] Manually verify that the Analysis crop-mask and Kc preview plots render cleanly and survive window resize without graphics warnings.
- [ ] Manually verify the simplified AOI browser flow against nested Windows/OneDrive folders and representative vector files.

## Guardrails

- Use `agent-workflow/` as the only canonical project-state location.
- Keep `session-brief.md` and status files concise to reduce token load.
- Use `inst/agent_skills/RWAPOR_AGENT_SKILLS.md` for package behavior, not session memory.
- Some runtime adapter files are still local-only because `.gitignore` excludes their parent paths.
