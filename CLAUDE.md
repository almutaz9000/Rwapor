# CLAUDE.md

Claude sessions in this repo must start with [agent-workflow/START-HERE.md](agent-workflow/START-HERE.md).

This file only keeps Claude-specific adapter notes.

## Runtime Notes

- Use `agent-workflow/` as the only canonical source of project memory, task state, issue state, and session handoff.
- Before claiming a task, check `agent-workflow/agents-board.json` for another model's active claim (Codex, Gemini, Hermes, Antigravity, etc. all read/write the same file); claim with `.\agent-workflow\scripts\board_claim.ps1 -Id <id> -Model claude -Status active`.
- Live view of tasks by model, open issues, and a module map:
  `powershell -ExecutionPolicy Bypass -File .\agent-workflow\scripts\run_dashboard.ps1`
- After repo changes or validated findings, run:
  `powershell -ExecutionPolicy Bypass -File .\agent-workflow\scripts\agent_closeout.ps1 -WorkPerformed`
- If a command failure reveals a reusable issue or root cause, log it in `agent-workflow/issues-log.md`.

## Claude plans, Codex implements

- For coding tasks that touch more than about 2 files or add behaviour: write a plan from
  `agent-workflow/templates/codex-plan.md`, hand it to Codex with
  `agent-workflow/scripts/codex_task.ps1` (run in the background), then verify Codex's work
  yourself (diff and rerun the tests). Full protocol: the `codex-delegate` skill.
- Do small edits (1–2 files, docs, config) directly. Delegating them costs more.
- Codex reads `AGENTS.override.md` (short on purpose) and project skills in `.agents/skills/`.
  To add or improve a Codex skill, use the `codex-skill-author` skill.

## Project Notes

- Use `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe` for `devtools::document()`, `devtools::test()`, and `devtools::check()`.
- Use `inst/agent_skills/RWAPOR_AGENT_SKILLS.md` for package usage and WaPOR-specific behavior.
- Treat `.agent/PROJECT.md` as a compact repo snapshot only, not as the memory system.
