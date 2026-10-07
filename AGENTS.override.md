# Codex entry point (Rwapor)

Codex reads this file instead of `AGENTS.md`. It is kept short on purpose so every
Codex run starts cheaply. Other agents still read `AGENTS.md`.

## Which mode are you in?

**A. Delegated by Claude.** Your prompt points to a plan in `docs/superpowers/plans/`.
Use the `rwapor-plan-executor` skill and follow it. Skip the startup reading in
`agent-workflow/START-HERE.md`; Claude handles the board, logs and handoff.

**B. Working directly for the user.** Follow `agent-workflow/START-HERE.md`
(preflight, session-brief, task-status, agents-board, issues-log) before editing,
and claim tasks with `agent-workflow/scripts/board_claim.ps1 -Model codex`.

## Always

- Load `rwapor-r-dev` before running R or editing `R/` or `tests/`.
- Project skills live in `.agents/skills/`. Load one only when its description matches the task.
- For general agent discipline, use the user-level `fable-skill` skill when a task is
  long, risky or ambiguous. It is not preloaded, to save tokens.
- Never commit, push or change branches unless the user asks.
