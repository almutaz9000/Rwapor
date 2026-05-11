# Issues Log

_Last updated: 2026-05-11_

## Open Issues

- [ ] None currently recorded in the shared workflow.

## Resolved Improvements

- [x] Parallel agent memory drift
  - ID: ISS-20260511-001
  - Resolved: 2026-05-11
  - Root cause: project state was split across multiple agent-specific files and partially stale repo docs.
  - Fix applied: introduced `agent-workflow/` as the shared source of truth and repointed the main adapters and hooks toward it.
  - Files: `agent-workflow/*`, `AGENTS.md`, `CLAUDE.md`, `.agent/PROJECT.md`, `.github/agents/*`, `.claude/settings.json`
  - Validation: shared startup order, memory location, and closeout path are now centralized in repo-owned files.
  - Regression test: run `agent_preflight.ps1` before work and keep model-specific docs as pointers only.
