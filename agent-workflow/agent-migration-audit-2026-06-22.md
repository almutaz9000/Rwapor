# Agent & Skill Configuration Audit
_Date: 2026-06-22 | Purpose: Migration investigation — verify missing files on other machine_

---

## Context

The project underwent a workflow migration (ISS-20260511-001) to centralize all agent state
under `agent-workflow/`. This audit documents what broke in the process and what to look for
on other machines where the pre-migration files may still exist.

---

## Directory Map (this machine)

### Files that EXIST

```
agent-workflow/               ← canonical, git-tracked
  START-HERE.md
  session-brief.md
  task-status.md
  issues-log.md
  project-memory.md
  change-log.md
  templates/
    issue-entry.md
    memory-entry.md
    session-brief.md
    task-entry.md
  scripts/
    agent_preflight.ps1
    agent_closeout.ps1
    agent_digest.ps1

inst/agent_skills/
  RWAPOR_AGENT_SKILLS.md     ← in-package API reference, version 0.9.8

.agents/skills/               ← local-only (gitignored), Claude Code Skill tool reads here
  rwapor-developer/
    SKILL.md                  ← has content (203 lines, version 1.1.0)
    references/
      analysis-pipeline.md
      bug-log.md
      core-api.md
      download-pipeline.md
      feature-log.md
      prompt-history.md
      shiny-dashboard.md
      ui-decisions.md
      utilities.md
  project-memory/
    SKILL.md
    assets/_template.md
    references/_template.md   ← only template, no actual memory entries
  wapor-resources/
    SKILL.md
  agent-development/
    SKILL.md + examples/ + references/
  skill-development/
    SKILL.md + references/
  find-skills/
    SKILL.md

~/.claude/agents/             ← global, all machines via sync
  wapor-agent.agent.md
  wapor-r-subagent.agent.md
  wapor-gee-subagent.agent.md
  wapor-dl-subagent.agent.md
  wapor-viz-subagent.agent.md
  geo-developer.agent.md
  geo-project-analyst.agent.md
  geo-python-subagent.agent.md
  geo-r-subagent.agent.md
  geo-js-webmap-subagent.agent.md
  geo-ml-dl-subagent.agent.md
  geo-bigdata-sql-subagent.agent.md
  geo-viz-dashboard-subagent.agent.md

~/.claude/skills/             ← global
  graphify/SKILL.md
  notebooklm/SKILL.md

~/.claude/projects/.../memory/   ← Claude Code auto-memory
  MEMORY.md
  user_profile.md
  project_context.md
  feedback.md
```

---

### Files that DO NOT EXIST on this machine (gitignored, empty or absent)

```
CLAUDE.md                     ← missing from project root (in .gitignore)
.agent/PROJECT.md             ← does not exist
.agent/skills/                ← directory exists but ALL subdirs are EMPTY:
  r-package-expert/           ← empty (no SKILL.md)
  shiny-developer/            ← empty (no SKILL.md)
  viz-reference/              ← empty (no SKILL.md)
  wapor-api-reference/        ← empty (no SKILL.md)
  rwapor-developer/           ← empty (no SKILL.md, no references/)
  project-memory/             ← empty
```

---

## What to Check on the Other Machine

These are the files the global wapor agents reference. If they exist on the other machine,
they are from the pre-migration setup and explain the intended design.

### High priority — agents break without these

| Path agents reference | Where agents look | What to check |
|---|---|---|
| `.agent/PROJECT.md` | `wapor-agent` Step 1 | Does it exist? What's in it? (project name, branch, skill list) |
| `.agent/skills/rwapor-developer/SKILL.md` | `wapor-r-subagent` always loads | Does it exist? Is it same as `.agents/skills/rwapor-developer/SKILL.md`? |
| `.agent/skills/rwapor-developer/references/bug-log.md` | `wapor-r-subagent` on bug fix | Exists? Content differs from `.agents/` version? |
| `.agent/skills/shiny-developer/SKILL.md` | `wapor-r-subagent` for Shiny UI | Exists? Any content? |
| `.agent/skills/r-package-expert/SKILL.md` | `wapor-r-subagent` for package infra | Exists? Any content? |
| `.agent/skills/wapor-api-reference/SKILL.md` | `wapor-r-subagent` for API work | Exists? Any content? |
| `.agent/skills/viz-reference/SKILL.md` | `wapor-viz-subagent` always loads | Exists? Any content? |
| `CLAUDE.md` (project root) | `wapor-agent` fallback | Exists? What does it say? |

### Also check

| Path | Question |
|---|---|
| `.agent/skills/project-memory/references/*.md` | Are there actual memory entries (not just `_template.md`)? |
| `.geo-agent/` | Did geo-developer ever run and create a workspace here? |
| `.jules/bolt.md` | What does it contain? (exists on this machine as a Jules adapter) |

---

## The Broken Flow (documented for reference)

When `wapor-agent` is spawned, the intended flow is:

```
1. Read .agent/PROJECT.md           → provides project context block
2. Delegate to wapor-r-subagent     → passes project context block
3. wapor-r-subagent reads:
     .agent/skills/rwapor-developer/SKILL.md
     .agent/skills/rwapor-developer/references/<module>.md
     .agent/skills/shiny-developer/SKILL.md  (for UI tasks)
     .agent/skills/r-package-expert/SKILL.md (for package infra)
     .agent/skills/wapor-api-reference/SKILL.md (for API tasks)
4. Outputs DEV BRIEF block before writing any code
5. Hooks: PostToolUseFailure → log to bug-log.md
          Stop → update prompt-history.md + project-memory
```

On this machine, steps 1 and 3 fail completely because all `.agent/skills/` are empty.
The agent has no project context and no skills loaded.

What actually works instead:
```
Skill("rwapor-developer") → reads .agents/skills/rwapor-developer/SKILL.md  ✅
  (Claude Code Skill tool knows to look in .agents/skills/)

agent-workflow/ files → manual read, works for any agent or model  ✅

inst/agent_skills/RWAPOR_AGENT_SKILLS.md → in-package API reference  ✅

~/.claude/projects/.../memory/ → auto-memory (user profile, feedback)  ✅
```

---

## Redundant / Conflicting Files

| Item | Issue |
|---|---|
| `.agent/skills/` (8 empty dirs) | Entire tree is empty. Referenced by all wapor agents. Can be deleted or repopulated. |
| `~/.claude/agents/geo-r-subagent.agent.md` | Overlaps with `wapor-r-subagent` (both handle R/terra). No `.geo-agent/` workspace on this machine. |
| `~/.claude/agents/geo-viz-dashboard-subagent.agent.md` | Overlaps with `wapor-viz-subagent` (both handle Shiny/tmap). |
| `~/.claude/agents/geo-ml-dl-subagent.agent.md` | Overlaps with `wapor-dl-subagent`. |
| `.agents/skills/project-memory/references/` | Only `_template.md`. No actual entries. Redundant with `agent-workflow/project-memory.md` and `~/.claude/projects/.../memory/`. |
| Three knowledge stores for Rwapor | `agent-workflow/project-memory.md` + `~/.claude/projects/.../memory/` + `.agents/skills/project-memory/` — no sync between them. |
| Hooks in agent files | Described as if they're Claude Code hook events, but no hooks are registered in any `settings.json`. They're just behavioral instructions inside agent prompts. |

---

## Gitignore Entries (relevant)

```
.agents/
.agent/
CLAUDE.md
```

All agent infrastructure is local-only. This is why the other machine may still have the
pre-migration files — they were never committed or deleted via git. Per task-status.md,
the decision to relax `.gitignore` for `CLAUDE.md` and `.agent/*` is still pending.

---

## Recommended Fix (after checking other machine)

**If the other machine has `.agent/skills/` populated:**
- Copy the missing SKILL.md files to this machine's `.agent/skills/`
- OR: update the global wapor agents to read from `.agents/skills/` instead (one path change per agent)

**Minimum viable fix without the other machine:**
1. Update `wapor-agent.agent.md` Step 1 fallback to read `agent-workflow/session-brief.md`
2. Update `wapor-r-subagent.agent.md` to load `.agents/skills/rwapor-developer/SKILL.md` instead of `.agent/skills/...`
3. Create missing skills (`shiny-developer`, `r-package-expert`, `wapor-api-reference`, `viz-reference`) in `.agents/skills/`
4. Add a minimal `CLAUDE.md` at project root pointing to `agent-workflow/START-HERE.md` and remove it from `.gitignore`
