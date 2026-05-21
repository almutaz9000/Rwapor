# Start Here

Canonical workflow for Claude, Codex, Gemini, and Copilot in this repo.

## Start

1. Check `.jules/bolt.md` for the current Active Tasks.
2. Run:
   `powershell -ExecutionPolicy Bypass -File .\agent-workflow\scripts\agent_preflight.ps1`
3. Read in this order:
   - `agent-workflow/session-brief.md`
   - `agent-workflow/task-status.md`
   - `agent-workflow/issues-log.md`
   - `agent-workflow/project-memory.md` only if relevant
3. Produce this 6-line digest before real work:
   - `Mode: Quick|Full`
   - `Scope: <target files>`
   - `Top Pending: <task>`
   - `Top Open Issue: <issue or none>`
   - `Validation Plan: <checks>`
   - `Exit Criteria: <done condition>`

## During Work

- Update `task-status.md` when task state changes.
- Update `issues-log.md` when you confirm a new issue, root cause, or resolution.
- Update `project-memory.md` only for durable lessons worth reusing.
- Keep summaries short. Point to files instead of repeating full context.

## Closeout

For sessions that change repo state or confirm a new finding, run:
`powershell -ExecutionPolicy Bypass -File .\agent-workflow\scripts\agent_closeout.ps1 -WorkPerformed`

Then refresh:
- `agent-workflow/session-brief.md`
- `agent-workflow/task-status.md`
- `agent-workflow/issues-log.md`
- `agent-workflow/change-log.md`

Refresh `project-memory.md` only when a durable lesson was confirmed.
