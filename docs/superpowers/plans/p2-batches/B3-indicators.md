# P2 batch B3: irrigation performance indicators, productivity gaps and spots

_Batch brief for the implementing agent (Codex, Antigravity, Claude or any other model).
Implement **this batch only**. The next batch starts after this one passes its verification gate._

| | |
|---|---|
| **Priority** | P2-2 (core value) |
| **Board tasks** | `p2-b3` (batch gate: set to done only by the verifier after gate G1-G10 passes) + feature tasks `ti-09`, `ti-13` (claim them before editing: `board_claim.ps1 -Id <id> -Model <you> -Status active`) |
| **Depends on** | B1 and B2 passed their gates |
| **Branch** | `version-1.0.6` (update it from the default branch first; do not commit or push unless asked) |
| **Specification** | `docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md`: implement exactly section 5 (WP3) |
| **Science reference** | `docs/superpowers/reviews/2026-09-30-p2-domain-expert-review.md` (defaults, formulas and sources; never turn an UNVERIFIED value into a default) |

## Before you start

1. Read `agent-workflow/START-HERE.md`, then the master plan sections 0 (principles and conventions),
   1A (roadmap and verification gate) and the sections above, then the review sections they cite.
2. Check that the previous batch passed its gate: `R/zonal_stats.R` and `R/mask_helpers.R` exist, their tests pass, and board task `p2-b2` is done.
3. Edit only the files listed below. If anything else must change, stop and report.

## Files you may change

- `R/performance_indicators.R` (new)
- `R/analysis_indicators.R` (roxygen `@export` for `wapor_calc_cv`, `wapor_calc_peff`, `wapor_calc_theil` only; no behaviour change)
- `tests/testthat/test-performance-indicators.R` (new)
- `NEWS.md`
- `NAMESPACE`, `man/*.Rd` (only via `devtools::document()`)

## Goal of this batch

Adequacy classes, relative water deficit, uniformity (1 - CV, CU, DU_lq; classes per irrigation method), equity, temporal reliability, climate normalization (and its application), productivity targets and gaps, bright/dark spots (protocol rule) and net irrigation requirement, for pixels or any units, built on B1 and B2.

## Validation (run in this order; report the result line of each)

```powershell
$R = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe"
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'performance-indicators')"
& $R -e "devtools::test(filter = 'zonal')"
& $R -e "devtools::test(filter = 'known-answer')"
```

## Done criteria

- [ ] All 12 WP3 test groups pass with the independent values listed
- [ ] Every function's help states its formula, source and caveats
- [ ] `devtools::test(filter = 'known-answer')` passes unchanged; `tests/testthat/fixtures/known-answer/` untouched
- [ ] No files changed outside the list above
- [ ] NEWS entry added under `# Rwapor 1.0.6 (development)`

## Report format (final message)

STATUS (done / partial / blocked) / FILES / VALIDATION (result line per command) / DONE CRITERIA (each
with evidence) / DEVIATIONS / QUESTIONS. The verifier then runs gate checks G1 to G10 (master plan
section 1A) before the next batch starts.

## Out of scope

No change to the seasonal-analysis engine; no registry indicator steps; the optional training example check must not tune defaults.
