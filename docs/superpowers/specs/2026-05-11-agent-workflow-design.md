# Agent Workflow Design

_Date: 2026-05-11_
_Project: Rwapor_
_Status: Draft approved in chat; written for repo review_

## Goal

Create one enforced, token-efficient repo workflow that Claude, Codex, Gemini, and Copilot can all use consistently in VS Code or Antigravity, so each model can build on previous work without maintaining separate project memories.

## Problem

The repository currently has multiple partially overlapping agent systems:

- `CLAUDE.md`
- `.agent/PROJECT.md`
- `.agent/skills/project-memory/...`
- `.agent/skills/memory-maintenance/...`
- `.github/agents/rwapor-dev.agent.md`
- tool-owned state under `.gemini/...`

This creates drift, stale instructions, and duplicated context. The repo needs one canonical operational source of truth and thin model-specific adapters.

## Decision Summary

Adopt a shared repo-owned coordination layer at `agent-workflow/` and treat it as the single authoritative source of project state for all models.

Model-specific folders remain, but only for runtime/config integration:

- `.claude/`
- `.gemini/`
- `.github/agents/`
- `.agent/`

They must point agents to the shared workflow instead of storing parallel project truth.

## Canonical Structure

```text
agent-workflow/
  START-HERE.md
  project-memory.md
  task-status.md
  issues-log.md
  session-brief.md
  change-log.md
  templates/
    issue-entry.md
    task-entry.md
    session-brief.md
    memory-entry.md
  scripts/
    agent_preflight.ps1
    agent_closeout.ps1
    agent_digest.ps1
```

## File Responsibilities

### `START-HERE.md`

Small universal startup procedure. Every model reads this first.

Contents:

- startup read order
- required preflight command
- required short digest format
- update rules
- closeout rule
- links to the other workflow files

### `project-memory.md`

Durable, curated lessons only:

- confirmed working patterns
- recurring pitfalls
- stable project constraints
- cross-session decisions worth reusing

Not a diary and not a copy of `git log`.

### `task-status.md`

Live execution state:

- current active tasks
- pending follow-ups
- blocked items
- next actions
- ownership/status markers if needed

### `issues-log.md`

Operational issue tracker for agents:

- open issues
- root causes
- attempted fixes if relevant
- resolved issues with migration notes
- regression tracking

### `session-brief.md`

Very short handoff file optimized for token efficiency.

Purpose:

- default first context read after `START-HERE.md`
- summarize last meaningful session
- point to the relevant task/issue entries

### `change-log.md`

Short agent-facing operational change summary:

- major workflow changes
- meaningful repo structure changes
- notable fixes that affect future sessions

This complements, but does not replace, `NEWS.md` or `git log`.

### `templates/`

Standardized write formats to keep entries structurally consistent across models.

### `scripts/`

Lightweight enforcement helpers:

- verify required files exist
- print minimal startup digest
- verify closeout updates were made

## Workflow Lifecycle

### Start Of Session

Every model must:

1. Read `agent-workflow/START-HERE.md`
2. Run `agent-workflow/scripts/agent_preflight.ps1`
3. Read only the minimum required context in this order:
   - `session-brief.md`
   - `task-status.md`
   - `issues-log.md`
   - `project-memory.md` only if relevant
4. Produce a short digest before real work:
   - mode
   - target files
   - relevant open task
   - relevant open issue
   - validation plan
   - exit criteria

### During Work

- update `task-status.md` when task state changes
- update `issues-log.md` when a new issue, root cause, or regression is found
- update `project-memory.md` only for durable learnings
- keep token usage low by referencing existing entries rather than replaying full context

### End Of Session

Every model must:

1. Run `agent-workflow/scripts/agent_closeout.ps1`
2. Update:
   - `session-brief.md`
   - `task-status.md`
   - `issues-log.md`
3. Append a short operational note to `change-log.md`
4. Add durable learnings to `project-memory.md` if newly confirmed

## Enforcement Model

Use lightweight enforcement rather than brittle heavy gating.

### Recommended Enforcement

- repo-owned workflow files are authoritative
- scripts validate startup and closeout expectations
- adapters in model-specific config point to shared files
- hooks give reminders where supported
- instructions stay short to reduce token cost

### Avoid

- parallel memory systems in `.claude/`, `.gemini/`, or `.agent/`
- long duplicated instructions in multiple places
- heavy automation tied to one vendor runtime
- using tool-owned chat state as project truth

## Adapter Strategy

### Root-level discovery

Add a root `AGENTS.md` that only points to `agent-workflow/START-HERE.md`.

Purpose:

- improve discovery for tools that scan the repo root
- keep one visible entrypoint

### `CLAUDE.md`

Convert from a large standalone rule file into a thin adapter:

- keep only truly Claude-specific runtime notes if needed
- point to `agent-workflow/START-HERE.md` first
- avoid duplicating workflow logic

### `.claude/settings.json`

Update hooks to reference the shared workflow files:

- failure reminders point to `agent-workflow/issues-log.md`
- stop reminders point to `agent-workflow/session-brief.md`, `task-status.md`, and `project-memory.md`

### `.github/agents/rwapor-dev.agent.md`

Replace old memory paths with `agent-workflow/*` and preserve the short startup digest requirement.

### `.agent/PROJECT.md`

Reduce to a compact project snapshot and pointer into `agent-workflow/`.

### `.agent/skills/project-memory/*`

Preserve the skill, but change its canonical read/write target from `references/rwapor.md` to `agent-workflow/project-memory.md` or a compatibility layer that clearly forwards there.

### `.agent/skills/memory-maintenance/*`

Update workflows and templates so session maintenance targets the shared workflow files rather than the old parallel memory structure.

### `.gemini/` and Antigravity

Treat these folders as runtime-owned state only. If a repo hint file is added for Gemini, it should point to `agent-workflow/START-HERE.md` and not store separate project memory.

### Copilot in VS Code

Copilot should rely on root-discoverable instructions such as `AGENTS.md` plus the shared workflow folder. The repo should not assume Copilot supports the same hook model as Claude.

## Token Efficiency Rules

To keep startup context small:

- `START-HERE.md` must stay short
- `session-brief.md` must stay short and current
- `project-memory.md` must stay curated
- issue and task entries must use compact templates
- adapters should point instead of restating

Target behavior:

- most sessions can start from `START-HERE.md` + `session-brief.md` + one relevant task/issue entry
- deeper reads happen only when needed

## Migration Plan

### Phase 1: Create shared workflow

- create `agent-workflow/`
- add core files, templates, and scripts
- add root `AGENTS.md`

### Phase 2: Repoint adapters

- update `CLAUDE.md`
- update `.claude/settings.json`
- update `.github/agents/rwapor-dev.agent.md`
- update `.agent/PROJECT.md`
- update relevant skills under `.agent/skills/...`

### Phase 3: De-duplicate old sources

- mark old memory locations as legacy
- move durable content into the new workflow files
- remove redundant instructions where safe

### Phase 4: Operational hardening

- keep preflight/closeout scripts lightweight
- verify startup flow works in the current development environment
- ensure docs stay consistent with repo reality

## Risks

### Risk: stale parallel docs remain

Mitigation:

- convert old files into pointers
- remove duplicated workflow text where possible

### Risk: over-enforcement becomes brittle

Mitigation:

- use lightweight validation scripts and reminders
- avoid complex runtime-specific gating

### Risk: memory files become noisy

Mitigation:

- keep `project-memory.md` curated
- use `session-brief.md` for short-lived handoff
- use templates to constrain entry size

## Success Criteria

The design is successful when:

- all models start from the same repo-owned entrypoint
- repo truth lives under `agent-workflow/`
- model-specific folders no longer contain independent project memory
- startup context becomes smaller and more predictable
- one model can continue another model's prior work using the shared files alone

## Implementation Scope For Next Step

The implementation phase should:

1. create the `agent-workflow/` folder and files
2. add root `AGENTS.md`
3. add PowerShell preflight/closeout/digest helpers
4. migrate or repoint existing agent instructions and skills
5. keep the initial version concise and maintainable

## Open Questions Resolved In This Design

- Canonical folder name: `agent-workflow/`
- Enforcement style: lightweight automation plus shared adapters
- Cross-model consistency approach: one shared repo source of truth
- Token efficiency approach: small startup chain with curated memory files
