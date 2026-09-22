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
   - `agents-board.json` (always — see "Cross-model coordination" below)
   - `issues-log.md` (always — open issues/regressions)
   - `project-memory.md` (only if the task touches an area with durable lessons)
4. Before making any edit, produce a short digest:
   - **Mode**: Quick (one file / doc tweak) or Full (multi-file / behavior change)
   - **Scope**: target files
   - **Relevant open task**: from `task-status.md`, or "none"
   - **Relevant open issue**: from `issues-log.md`, or "none"
   - **Validation plan**: what you will run to confirm the change works
   - **Exit criteria**: what "done" means for this task

## Cross-model coordination (agents-board.json)

This repo is worked by more than one model — Claude, Codex, Gemini, Hermes,
Antigravity, Warp, and others, via the adapter file each of them reads
(`CLAUDE.md`, `GEMINI.md`, `QWEN.md`, `WARP.md`, `.clinerules`, `.goosehints`,
etc. — all of them point back to this file). `agent-workflow/agents-board.json`
is the single machine-readable record of who is working on what, so a
different model picking up this repo tomorrow sees in-flight and finished work
instead of re-discovering it from scratch.

- **Before claiming a task**, open `agents-board.json` and check its `model`
  and `status` fields — if another model already has it `"active"`, don't
  duplicate the work; pick a different pending task or coordinate first.
- **When you start a task**, set that task's `status` to `"active"`, `model`
  to your own slug (`claude`, `codex`, `gemini`, `hermes`, `antigravity`,
  `warp`, `qwen`, `copilot`, `cursor`, `cline`, `goose`, or add a new one to
  `known_models` if none fits), `attribution` to `"recorded"`, and
  `claimed_utc` to the current UTC timestamp. `agent-workflow\scripts\board_claim.ps1`
  does this for you: `.\agent-workflow\scripts\board_claim.ps1 -Id 1.5 -Model claude -Status active`.
- **When you finish or pause**, update that task's `status` (`"done"` or back
  to `"pending"`/`"blocked"`), `notes`, and `updated_utc` — same script, with
  `-Status done -Notes "..."`.
- **Every task, issue, and session added to `agents-board.json` must also be
  reflected in `task-status.md` / `issues-log.md` / `session-brief.md`** (and
  vice versa) — the JSON is not a replacement for the prose files, it's what
  the dashboard (`agent-workflow/dashboard/`) and other models parse
  programmatically. Keep both in sync in the same edit.
- Entries dated on or before 2026-09-15 have `attribution: "inferred"` — they
  predate this board and were back-filled from `session-brief.md`, not
  self-reported. Every new entry must be `"recorded"`.

## During work

- Update `task-status.md` when a task's state changes.
- Update `agents-board.json` (task status/model/notes) in the same edit — see
  above.
- Update `issues-log.md` when you find a new issue, root cause, or regression
  (and mirror it into `agents-board.json`'s `issues` array).
- Update `project-memory.md` only for a durable, confirmed, reusable lesson —
  not a diary entry.
- Reference existing entries instead of re-explaining background; keep updates
  short.

## Closeout (end of session, or after a meaningful change)

1. Run:
   `powershell -ExecutionPolicy Bypass -File .\agent-workflow\scripts\agent_closeout.ps1 -WorkPerformed`
2. Update `session-brief.md`, `task-status.md`, and `issues-log.md`.
3. Set any task you claimed to `"done"`/`"pending"`/`"blocked"` in
   `agents-board.json` (via `board_claim.ps1`) and append a `sessions` entry
   with your model slug, date, and a one-line summary.
4. Append one short line to `change-log.md`.
5. Add to `project-memory.md` only if something durable was newly confirmed.

## Live status dashboard

`agent-workflow/dashboard/` is a Streamlit app that reads `agents-board.json`
(plus `task-status.md`/`issues-log.md`) and shows, at any time: active/pending/
done tasks grouped by which model is on them, open issues, decisions that need
a human, and a module-dependency map of `R/` and `inst/shiny/`. Launch it with
`powershell -ExecutionPolicy Bypass -File .\agent-workflow\scripts\run_dashboard.ps1`.
It is a monitoring tool for the human maintainer — it is not part of the
Rwapor package's own Shiny app (`inst/shiny/app.R`) and ships nothing to
package users.

## Rules

- `agent-workflow/` is authoritative. Do not create a parallel memory system
  under `.agent/`, `.claude/`, `.gemini/`, or elsewhere.
- Keep entries short — a compact `session-brief.md` plus one relevant task/issue
  entry should be enough to resume work. Use the templates in `templates/`.
- `project-memory.md` is curated, not a log — do not let it grow unbounded.
- Use stable issue IDs: `ISS-YYYYMMDD-###`.
- `agents-board.json` must stay valid JSON — validate with `board_claim.ps1`
  or `python -m json.tool agent-workflow\agents-board.json` before committing
  a hand edit.
