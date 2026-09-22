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

## Project Notes

- Use `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe` for `devtools::document()`, `devtools::test()`, and `devtools::check()`.
- Use `inst/agent_skills/RWAPOR_AGENT_SKILLS.md` for package usage and WaPOR-specific behavior.
- Treat `.agent/PROJECT.md` as a compact repo snapshot only, not as the memory system.
