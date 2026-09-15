# Start Here

This is the canonical, repo-owned coordination layer for Rwapor. Every model
(Claude, Codex, Gemini, Copilot, or any other agent working in this repo) reads
this file first and treats `agent-workflow/` as the single source of truth for
project state — not `.agent/`, `.gemini/`, or any other model-specific folder.

See `docs/superpowers/specs/2026-05-11-agent-workflow-design.md` for the full
design rationale if you need it. You do not need to read it for normal work.

## Startup (every session)

1. Read this file.
2. Run the preflight check:
   `powershell -ExecutionPolicy Bypass -File .\agent-workflow\scripts\agent_preflight.ps1`
3. Read, in order, only what you need:
   - `session-brief.md` (always — short handoff from the last session)
   - `task-status.md` (always — live work state)
   - `issues-log.md` (always — open issues/regressions)
   - `project-memory.md` (only if the task touches an area with durable lessons)
4. Before making any edit, produce a short digest:
   - **Mode**: Quick (one file / doc tweak) or Full (multi-file / behavior change)
   - **Scope**: target files
   - **Relevant open task**: from `task-status.md`, or "none"
   - **Relevant open issue**: from `issues-log.md`, or "none"
   - **Validation plan**: what you will run to confirm the change works
   - **Exit criteria**: what "done" means for this task

## During work

- Update `task-status.md` when a task's state changes.
- Update `issues-log.md` when you find a new issue, root cause, or regression.
- Update `project-memory.md` only for a durable, confirmed, reusable lesson —
  not a diary entry.
- Reference existing entries instead of re-explaining background; keep updates
  short.

## Closeout (end of session, or after a meaningful change)

1. Run:
   `powershell -ExecutionPolicy Bypass -File .\agent-workflow\scripts\agent_closeout.ps1 -WorkPerformed`
2. Update `session-brief.md`, `task-status.md`, and `issues-log.md`.
3. Append one short line to `change-log.md`.
4. Add to `project-memory.md` only if something durable was newly confirmed.

## Rules

- `agent-workflow/` is authoritative. Do not create a parallel memory system
  under `.agent/`, `.claude/`, `.gemini/`, or elsewhere.
- Keep entries short — a compact `session-brief.md` plus one relevant task/issue
  entry should be enough to resume work. Use the templates in `templates/`.
- `project-memory.md` is curated, not a log — do not let it grow unbounded.
- Use stable issue IDs: `ISS-YYYYMMDD-###`.
