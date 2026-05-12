# Agent Workflow Change Log

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

## 2026-05-11

- Added the shared `agent-workflow/` coordination layer.
- Added root `AGENTS.md` as the cross-model entrypoint.
- Migrated durable project memory into `agent-workflow/project-memory.md`.
- Started repointing repo-local adapters, skills, and hooks away from parallel memory paths.
- Validated `agent_preflight.ps1`, `agent_digest.ps1`, and `agent_closeout.ps1` from the repo root.
- Added the Shiny batch-analysis design spec at `docs/superpowers/specs/2026-05-11-shiny-batch-analysis-design.md`.
- Added the Shiny batch-analysis implementation plan at `improvements/P4_shiny_batch_analysis.md`.
- Logged `ISS-20260511-002` for the multi-season local-analysis session disconnect and script-preview drift.
- Implemented the Shiny batch-analysis patch and added regression tests for batch parsing, batch scripts, and named-list period handling.
- Fixed generated script escaping for Windows paths after a follow-up `\U` parse error report.
