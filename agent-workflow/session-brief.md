# Session Brief

_Last updated: 2026-05-12_

## Active Focus

- Shared agent coordination now starts from `agent-workflow/START-HERE.md`.
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

## Top Open Issues

- `ISS-20260511-002`: code fix is in place, but manual Shiny verification is still pending for the multi-season local session-disconnect scenario.

## Recently Resolved

- `ISS-20260511-001`: workflow drift fixed by centralizing memory, task state, and issue state under `agent-workflow/`.

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
