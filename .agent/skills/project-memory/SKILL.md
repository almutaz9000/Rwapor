---
name: project-memory
description: >
  Maintain a persistent record of project-specific successes and failures across
  conversations. Use this skill whenever a user references an ongoing project,
  task, or topic where past decisions matter — especially when they say things
  like "remember what worked last time", "don't repeat the mistake from before",
  "we already tried that", "keep track of this", "note that down", "save this
  approach", or when starting a complex multi-session task (e.g., a data pipeline,
  dashboard, report, code package). Also trigger automatically when the user
  explicitly confirms or rejects a solution during a session. This skill ensures
  future interactions build on what works and never repeat known failures.
---

# Project Memory

A skill for maintaining persistent, structured records of confirmed successes
and documented failures, scoped per project or topic.

---

## Core Logic

```
START of task
  └─► Does a memory file exist for this project?
        ├─► YES → READ it → Summarize relevant entries → Proceed informed
        └─► NO  → Note this is a fresh project → Proceed → Create file after first
                  confirmed success or failure

DURING / END of task
  └─► Did the user confirm or reject anything?
        ├─► Confirmed ("works", "perfect", "keep this", "use this approach")
        │       └─► Add to ✅ Confirmed section
        ├─► Rejected ("failed", "not right", "don't do this", "revert")
        │       └─► Add to ❌ Failed section
        └─► Neither → No memory update needed
```

---

## Workflow

### Step 1 — Identify the Project

Determine the project/topic name from:
- Explicit user mention ("for the WaPOR dashboard", "in the ASIS pipeline")
- Conversation context (file names, tool names, prior messages)
- If ambiguous, ask: *"Should I track this under a specific project name?"*

Slugify the name for file use (e.g., `rwapor-dashboard`, `asis-bigquery-pipeline`).

### Step 2 — Check for Existing Memory

Look for the file at:
```
references/{project-slug}.md
```

**If found:**
- Read the file
- Before proposing any solution, explicitly state:
  - Which confirmed approaches are relevant
  - Which failures to avoid
  - Example: *"Based on past work on this project: X approach worked well, and Y was previously rejected because Z."*

**If not found:**
- Proceed normally
- Create the file at the end of the session if anything was confirmed or rejected

### Step 3 — Update Memory

After any user confirmation or rejection, update the relevant section.

Rules:
- Be **specific** — include the exact approach, config, or pattern, not just "it worked"
- Be **concise** — one to three lines per entry
- Include **context** — why it worked or failed, not just that it did
- If a former failure is now resolved, **move it** to ✅ with a note on the fix
- Do **not** duplicate entries — check before adding

### Step 4 — Apply Memory Proactively

At the start of each relevant new task:
1. State which memory file you are consulting
2. Summarize the applicable entries (do not dump the whole file)
3. Tailor your proposed plan accordingly

---

## Memory File Format

Store memory files at: `references/{project-slug}.md`

Use this template:

```markdown
# Project: {Project Name}
_Last updated: {YYYY-MM-DD}_

## ✅ Confirmed / Working

- **[Approach / Tool / Pattern]**: What was done and why it worked.
  _Context: {brief note on the situation when this was confirmed}_

- **[Approach / Tool / Pattern]**: Description.
  _Context: {brief note}_

## ❌ Failed / Avoid

- **[Approach / Tool / Pattern]**: What failed and why.
  _Error or reason: {specific message or user feedback}_

- **[Approach / Tool / Pattern]**: Description of what not to do.
  _Error or reason: {specific message or user feedback}_

## 📝 Open Questions / Undecided

- {Any approach still being evaluated or not yet confirmed/rejected}
```

---

## Maintenance Rules

| Situation | Action |
|---|---|
| Entry confirmed after being in ❌ | Move to ✅, add fix note |
| Entry invalidated after being in ✅ | Move to ❌, add reason |
| Redundant entries | Merge into one |
| Project renamed | Rename file, keep history |
| Memory file > 60 entries | Archive old entries to `references/{project-slug}-archive.md` |

---

## Behavior Notes

- **Never silently update memory** — always tell the user when you are recording something:
  *"I've noted this approach as confirmed in the project memory."*
- **Never invent entries** — only record what the user explicitly confirmed or rejected
- **Scope tightly** — one file per project/topic, not one global file
- **Respect privacy** — do not store credentials, tokens, or sensitive personal data in memory files

---

## File Structure Reference

```
project-memory/
├── SKILL.md                          ← This file
├── references/
│   ├── {project-slug}.md             ← Per-project memory (auto-created)
│   ├── {project-slug}-archive.md     ← Archived old entries (when needed)
│   └── _template.md                  ← Blank template for new projects
└── assets/
    └── _template.md                  ← Copy of template (reference)
```

---

## Example Interaction

**User:** "Let's keep working on the ASIS BigQuery pipeline."

**Claude (with memory):**
> Consulting memory for `asis-bigquery-pipeline`...
> - ✅ Area-weighted DI calculation using `SUM(di * area) / SUM(area)` is confirmed
> - ✅ 24-month rolling window logic using `RANGE BETWEEN` is confirmed  
> - ❌ Joining directly on `pixel_id` without a spatial index caused timeout on 130k polygons — use batched approach instead
>
> Proceeding with these constraints in mind. What would you like to tackle today?
