# Session Brief

_Last updated: 2026-05-11_

## Active Focus

- Shared agent coordination now starts from `agent-workflow/START-HERE.md`.
- Main repo adapters now point to the shared workflow instead of parallel memory paths.

## Top Open Issues

- None recorded in `agent-workflow/issues-log.md`.

## Recently Resolved

- `ISS-20260511-001`: workflow drift fixed by centralizing memory, task state, and issue state under `agent-workflow/`.

## Pending Tasks

- [ ] Use the shared workflow during the next substantial multi-model task and remove any friction it exposes.
- [ ] Decide whether to surface the workflow in `README.md` or other human-facing docs.

## Guardrails

- Use `agent-workflow/` as the only canonical project-state location.
- Keep `session-brief.md` and status files concise to reduce token load.
- Use `inst/agent_skills/RWAPOR_AGENT_SKILLS.md` for package behavior, not session memory.
- Some runtime adapter files are still local-only because `.gitignore` excludes their parent paths.
