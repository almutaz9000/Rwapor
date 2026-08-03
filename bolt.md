# Bolt configuration

This file is the primary entry point for all AI agent tasks and requests in this repository. Always check this file first at the start of a session.

## Canonical Project Workflow

All agents must follow the coordination workflow starting from `agent-workflow/START-HERE.md`.

Use this file for repository-wide configuration, runtime guidance, and direct user requests.

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
- Do not create a parallel agent task list or separate repo memory.

## Update Rules

- Use `agent-workflow/task-status.md` for live task progress.
- Log confirmed root causes, regressions, and resolutions in `agent-workflow/issues-log.md`.
- Update `agent-workflow/session-brief.md` after validated work so later sessions can pick up quickly.
- Update `agent-workflow/change-log.md` when repo-visible workflow or behavior changes are confirmed.
- Put durable lessons in `agent-workflow/project-memory.md`.

## Validation And Commits

- Validate the touched area before committing.
- For R package changes, use `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe` for package commands.
- Commit only validated changes.
- Keep commits scoped to the completed task.
- After validated repo changes, run or mirror the closeout expectations from `agent-workflow/scripts/agent_closeout.ps1 -WorkPerformed` by updating:
	- `agent-workflow/session-brief.md`
	- `agent-workflow/task-status.md`
	- `agent-workflow/issues-log.md`
	- `agent-workflow/change-log.md`

## Guardrails

- Treat `agent-workflow/` as the only canonical source of truth for project state.
- Use `inst/agent_skills/RWAPOR_AGENT_SKILLS.md` for package and WaPOR behavior.
- Do not store lasting project learnings in `bolt.md`.
