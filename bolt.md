# Bolt Adapter

Shared agent sessions in this repo must start with `agent-workflow/START-HERE.md`.

Use this file for repository-level task entry and runtime guidance. The canonical project workflow, memory, task state, and issue state live under `agent-workflow/`.

## Required Start Flow

Before making changes:

1. Read `agent-workflow/START-HERE.md`.
2. Read `agent-workflow/session-brief.md`.
3. Read `agent-workflow/task-status.md`.
4. Read `agent-workflow/issues-log.md`.
5. Read `agent-workflow/project-memory.md` only if relevant.

## Online Work Queue

- Use unchecked items in `agent-workflow/task-status.md` as the default pending work queue.
- Prefer tasks that already have clear scope and validation steps.
- Check `agent-workflow/issues-log.md` for open regressions and unresolved root causes before starting.

## Update Rules

- Use `agent-workflow/task-status.md` for live task progress.
- Log confirmed root causes, regressions, and resolutions in `agent-workflow/issues-log.md`.
- Update `agent-workflow/session-brief.md` after validated work so later sessions can pick up quickly.
- Update `agent-workflow/change-log.md` when repo-visible workflow or behavior changes are confirmed.

## Validation And Commits

- Validate the touched area before committing.
- Commit only validated changes.
- Keep commits scoped to the completed task.
- After validated repo changes, update:
	- `agent-workflow/session-brief.md`
	- `agent-workflow/task-status.md`
	- `agent-workflow/issues-log.md`
	- `agent-workflow/change-log.md`

## Guardrails

- Treat `agent-workflow/` as the only canonical source of truth.
- Use `inst/agent_skills/RWAPOR_AGENT_SKILLS.md` for package and WaPOR behavior.
