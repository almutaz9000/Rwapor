# Issues Log

_Last updated: 2026-05-11_

## Open Issues

- [ ] Batch-mode local analysis can destabilize the Shiny session and disconnect the R console session.
  - ID: ISS-20260511-002
  - First noted: 2026-05-11
  - Symptoms: when running multi-season analysis against local downloaded rasters, the Shiny app remains open but the session disconnects and analysis stops; the generated script also does not reliably reflect the configured batch workflow.
  - Likely root cause: `inst/shiny/mod_analysis.R` still mixes single-period and batch-period assumptions in validation, local data coverage checks, and run setup, while script preview is split between a generator path and a generic fallback.
  - Planned fix: implement the approved design in `docs/superpowers/specs/2026-05-11-shiny-batch-analysis-design.md` so validation, execution, and script export consume one canonical config builder.
  - Regression test: add coverage for batch parsing, multi-season local config flow, and batch script generation.

## Resolved Improvements

- [x] Parallel agent memory drift
  - ID: ISS-20260511-001
  - Resolved: 2026-05-11
  - Root cause: project state was split across multiple agent-specific files and partially stale repo docs.
  - Fix applied: introduced `agent-workflow/` as the shared source of truth and repointed the main adapters and hooks toward it.
  - Files: `agent-workflow/*`, `AGENTS.md`, `CLAUDE.md`, `.agent/PROJECT.md`, `.github/agents/*`, `.claude/settings.json`
  - Validation: shared startup order, memory location, and closeout path are now centralized in repo-owned files.
  - Regression test: run `agent_preflight.ps1` before work and keep model-specific docs as pointers only.
