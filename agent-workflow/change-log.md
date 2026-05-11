# Agent Workflow Change Log

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
