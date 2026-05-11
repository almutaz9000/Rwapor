# Task Status

_Last updated: 2026-05-11_

## Active

- [ ] Monitor the shared `agent-workflow/` flow during the next real multi-model work session.
  - Scope: confirm the startup digest, closeout behavior, and shared handoff stay practical in normal use.
  - Next action: use the workflow on the next substantial repo task and trim any newly exposed friction.

## Pending

- [ ] Implement the approved Shiny batch-analysis and script-generation fixes from `docs/superpowers/specs/2026-05-11-shiny-batch-analysis-design.md`.
- [ ] Reproduce and fix the Shiny session disconnect in multi-season local analysis, then add regression coverage for the batch path.
- [ ] Decide whether to surface the shared workflow in human-facing contributor docs such as `README.md`.
- [ ] Decide whether to relax `.gitignore` for selected adapter files (`CLAUDE.md`, `.agent/*`, `.github/agents/*`) if you want those pointers shared through Git instead of local-only.
- [ ] Run the package test follow-up for the earlier temperature-conversion work when that code path is next touched.
- [ ] Update user-facing docs for automatic temperature conversion and dekadal defaults in a future documentation pass.

## Completed Recently

- [x] Approved the shared agent workflow design.
- [x] Wrote the design spec at `docs/superpowers/specs/2026-05-11-agent-workflow-design.md`.
- [x] Wrote the Shiny batch-analysis implementation plan at `improvements/P4_shiny_batch_analysis.md`.
- [x] Added `agent-workflow/`, shared templates, and workflow scripts.
- [x] Repointed the main repo adapters, hooks, and memory entrypoints to `agent-workflow/`.
