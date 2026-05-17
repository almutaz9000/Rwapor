# Jules Adapter

Jules sessions in this repo must start with `agent-workflow/START-HERE.md`.

Use this file only for Jules-specific runtime guidance. The canonical project workflow, memory, task state, and issue state live under `agent-workflow/`.

## Required Start Flow

Before making changes:

1. Read `agent-workflow/START-HERE.md`.
2. Read `agent-workflow/session-brief.md`.
3. Read `agent-workflow/task-status.md`.
4. Read `agent-workflow/issues-log.md`.
5. Read `agent-workflow/project-memory.md` only if relevant.

## Online Work Queue

- **Primary Entry Point**: Use the **Active Tasks** section below for Jules-specific pending work.
- Check `agent-workflow/issues-log.md` for open regressions and unresolved root causes before starting.

## Active Tasks

- [ ] Manually verify dashboard startup + shutdown behavior in an interactive Shiny session.
  - Scope: confirm module-source failures are explicit and async runtime state is restored after app close.
  - Next action: launch `run_wapor()` from a clean session and validate close/relaunch behavior.
- [ ] Reinstall or load the updated package code before rerunning standalone analysis scripts generated from the Shiny UI.
- [ ] Reinstall or load the updated package code before rerunning standalone indicator-by-indicator analysis scripts that use `beneficial_fraction`.
- [ ] Manually verify the Analysis crop-mask and Kc preview plots render cleanly and survive window resize without graphics warnings.
- [ ] Manually verify the patched Shiny batch workflow with local multi-season rasters and confirm the R console session stays connected.
- [ ] Manually verify the Analysis tab project-folder override and confirm `Re-scan Folder` follows the active source folder instead of the output folder.
- [ ] Manually verify that Analysis `Detect from Folder` no longer disconnects the session for valid and invalid project folders.
- [ ] Manually verify the simplified download-tab AOI browser flow with nested folders and representative vector files on Windows.
- [ ] Run the package test follow-up for the earlier temperature-conversion work when that code path is next touched.

## Update Rules

- Update the **Active Tasks** section here for live progress.
- Log confirmed root causes, regressions, and resolutions in `agent-workflow/issues-log.md`.
- Update `agent-workflow/session-brief.md` after validated work so later sessions can pick up quickly.
- Update `agent-workflow/change-log.md` when repo-visible workflow or behavior changes are confirmed.
- Put durable lessons in `agent-workflow/project-memory.md`, not here.

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

- Treat `agent-workflow/` as the only canonical source of truth.
- Use `inst/agent_skills/RWAPOR_AGENT_SKILLS.md` for package and WaPOR behavior.
- Do not store lasting project learnings in `.jules/`.
