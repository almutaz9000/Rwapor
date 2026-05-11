# Session Brief

_Last updated: 2026-05-11_

## Active Focus

- Shared agent coordination now starts from `agent-workflow/START-HERE.md`.
- Main repo adapters now point to the shared workflow instead of parallel memory paths.
- Wrote the Shiny batch-analysis design spec at `docs/superpowers/specs/2026-05-11-shiny-batch-analysis-design.md`.
- Wrote the implementation plan at `improvements/P4_shiny_batch_analysis.md`.
- Implemented the batch-analysis patch across `inst/shiny/mod_analysis.R`, `R/analysis_utils.R`, `R/analysis_engine.R`, and `inst/shiny/mod_analysis_ui_body.R`.
- Added regression coverage in `tests/testthat/test-analysis-shiny.R` and reran targeted analysis tests successfully.

## Top Open Issues

- `ISS-20260511-002`: code fix is in place, but manual Shiny verification is still pending for the multi-season local session-disconnect scenario.

## Recently Resolved

- `ISS-20260511-001`: workflow drift fixed by centralizing memory, task state, and issue state under `agent-workflow/`.

## Pending Tasks

- [ ] Use the shared workflow during the next substantial multi-model task and remove any friction it exposes.
- [ ] Decide whether to surface the workflow in `README.md` or other human-facing docs.
- [ ] Manually verify the patched Shiny batch workflow with local multi-season rasters and confirm the session no longer disconnects.

## Guardrails

- Use `agent-workflow/` as the only canonical project-state location.
- Keep `session-brief.md` and status files concise to reduce token load.
- Use `inst/agent_skills/RWAPOR_AGENT_SKILLS.md` for package behavior, not session memory.
- Some runtime adapter files are still local-only because `.gitignore` excludes their parent paths.
