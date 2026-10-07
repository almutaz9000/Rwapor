# P2 batch B5: plots and offline URL lists

_Batch brief for the implementing agent (Codex, Antigravity, Claude or any other model).
Implement **this batch only**. The next batch starts after this one passes its verification gate._

| | |
|---|---|
| **Priority** | P2-3 (polish) |
| **Board tasks** | `p2-b5` (batch gate: set to done only by the verifier after gate G1-G10 passes) + feature tasks `ti-14`, `ti-15` (claim them before editing: `board_claim.ps1 -Id <id> -Model <you> -Status active`) |
| **Depends on** | B1 passed its gate |
| **Branch** | `version-1.0.6` (update it from the default branch first; do not commit or push unless asked) |
| **Specification** | `docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md`: implement exactly section 7 WP5 **part B** (steps 3-4, tests 4-5) |
| **Science reference** | `docs/superpowers/reviews/2026-09-30-p2-domain-expert-review.md` (defaults, formulas and sources; never turn an UNVERIFIED value into a default) |

## Before you start

1. Read `agent-workflow/START-HERE.md`, then the master plan sections 0 (principles and conventions),
   1A (roadmap and verification gate) and the sections above, then the review sections they cite.
2. Check that the previous batch passed its gate: no other batch is in progress on the branch.
3. Edit only the files listed below. If anything else must change, stop and report.

## Files you may change

- `R/viz.R`
- the file where `wapor_generate_urls()` caches API responses (grep `Rwapor.cache_ttl`)
- `tests/testthat/test-viz-basic.R`, `tests/testthat/test-offline-urls.R` (new)
- `NEWS.md`
- `man/*.Rd` (only via `devtools::document()`)

## Goal of this batch

Plots without the deprecated `aes_string()`, guarded because ggplot2 is only in Suggests, at full resolution, with a calendar- and stage-aware Kc plot (FAO-56 stage names by default, dormant periods, seasons crossing 1 January); URL lists usable offline from the cache with a clear message.

## Validation (run in this order; report the result line of each)

```powershell
$R = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe"
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'viz')"
& $R -e "devtools::test(filter = 'offline-urls')"
& $R -e "devtools::test(filter = 'known-answer')"
```

## Done criteria

- [ ] WP5 tests 4-5 pass; no `aes_string` left in `R/`
- [ ] Old plot calls produce the same output as before
- [ ] `devtools::test(filter = 'known-answer')` passes unchanged; `tests/testthat/fixtures/known-answer/` untouched
- [ ] No files changed outside the list above
- [ ] NEWS entry added under `# Rwapor 1.0.6 (development)`

## Report format (final message)

STATUS (done / partial / blocked) / FILES / VALIDATION (result line per command) / DONE CRITERIA (each
with evidence) / DEVIATIONS / QUESTIONS. The verifier then runs gate checks G1 to G10 (master plan
section 1A) before the next batch starts.

## Out of scope

Shiny dashboard plots; plot types beyond WP5B.
