# Change Log

_Short, agent-facing operational change summary. Complements but does not
replace `NEWS.md` or `git log` — only major workflow changes, meaningful repo
structure changes, and fixes that affect future sessions belong here._

## 2026-09-03

- Created the `agent-workflow/` hub (`START-HERE.md`, `project-memory.md`,
  `task-status.md`, `issues-log.md`, `session-brief.md`, `change-log.md`,
  `templates/`, `scripts/agent_preflight.ps1`,
  `scripts/agent_closeout.ps1`, `scripts/agent_digest.ps1`). This folder was
  the mandated entry point in every adapter file but did not previously
  exist — see `docs/superpowers/specs/2026-05-11-agent-workflow-design.md`.
- Fixed WaPOR seasonal download robustness: SHA-256 disk-cache key (was a
  collision-prone checksum), retry-with-backoff in the seasonal raster
  loader, plan-vs-loaded reconciliation (`missing_periods`), and
  exponential-backoff/`Retry-After`-aware API retries. Added `digest` to
  `Imports`. See NEWS.md (Rwapor 0.9.9, "Download Robustness") and
  `issues-log.md` ISS-20260903-001.
- Added an `agent-workflow/START-HERE.md` pointer header to the generic
  fable-skill-managed files that lacked one (`GEMINI.md`, `QWEN.md`,
  `WARP.md`, `.rules`, `.goosehints`, `CONVENTIONS.md`, `replit.md`,
  `.junie/guidelines.md`, `.openhands/microagents/repo.md`) and added a
  sibling `rwapor-agent-workflow` rule file for the rules-directory tools
  (`.cursor`, `.continue`, `.windsurf`, `.clinerules`, `.roo`, `.trae`,
  `.kilocode`, `.kiro`, `.augment`) without touching their managed
  fable-skill files.
