# Plan: <task-id> — <short title>

_Written by Claude for Codex. Save as `docs/superpowers/plans/<YYYY-MM-DD>-<task-id>.md`.
Codex executes this plan exactly; every design decision is made here, not by Codex._

- **Board task**: `<task-id>` (claimed for `codex`)
- **Branch**: `<branch>` (Codex does not switch branches or commit)
- **Skills to load**: `rwapor-plan-executor`, `rwapor-r-dev` (+ any task-specific skill)

## Goal

<One or two sentences: what changes for the user of the package and why.>

## Context Codex needs (and nothing more)

- `<path>:<line>` — <what is there and why it matters>
- Root cause / evidence: <one short paragraph, or link to issues-log entry>

## Files

| File | Change |
|---|---|
| `R/<file>.R` | <what to change> |
| `tests/testthat/test-<file>.R` | <tests to add> |

Codex must not edit any file outside this table. If another file must change, stop and report.

## Steps

1. <Exact change: function, argument, behaviour, edge cases. Include signatures and
   expected values. Pseudocode or a short snippet is fine when it removes ambiguity.>
2. <...>
3. Add tests: <test names, inputs, expected outputs, including the regression case>.
4. If roxygen changed: run `devtools::document()`.

## Validation (run in this order, report the result line of each)

```powershell
& "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe" -e "devtools::test(filter = '<file>')"
```

<Add `devtools::document()` / a wider `devtools::test()` only when needed. Avoid
`devtools::check()` unless the plan changes exports, DESCRIPTION or docs.>

## Done criteria (Claude verifies each)

- [ ] <Observable behaviour 1>
- [ ] <Regression test that failed before and passes now>
- [ ] Validation commands pass with 0 failures
- [ ] No files changed outside the table

## Out of scope

- <Things Codex must not touch or "improve" while there.>
