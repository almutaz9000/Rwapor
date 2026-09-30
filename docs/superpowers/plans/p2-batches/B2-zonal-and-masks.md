# P2 batch B2: zonal statistics engine and mask helpers

_Batch brief for the implementing agent (Codex, Antigravity, Claude or any other model).
Implement **this batch only**. The next batch starts after this one passes its verification gate._

| | |
|---|---|
| **Priority** | P2-1 (foundation) |
| **Board tasks** | `p2-b2` (batch gate: set to done only by the verifier after gate G1-G10 passes) + feature tasks `ti-10`, `ti-16`, `ti-12` (claim them before editing: `board_claim.ps1 -Id <id> -Model <you> -Status active`) |
| **Depends on** | B1 passed its gate |
| **Branch** | `version-1.0.6` (update it from the default branch first; do not commit or push unless asked) |
| **Specification** | `docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md`: implement exactly section 4 (WP2) and section 7 WP5 **part A** (steps 1-2, tests 1-3) |
| **Science reference** | `docs/superpowers/reviews/2026-09-30-p2-domain-expert-review.md` (defaults, formulas and sources; never turn an UNVERIFIED value into a default) |

## Before you start

1. Read `agent-workflow/START-HERE.md`, then the master plan sections 0 (principles and conventions),
   1A (roadmap and verification gate) and the sections above, then the review sections they cite.
2. Check that the previous batch passed its gate: `R/classify.R` exists, `devtools::test(filter = 'classify')` passes, and board task `p2-b1` is done.
3. Edit only the files listed below. If anything else must change, stop and report.

## Files you may change

- `R/zonal_stats.R` (new)
- `R/mask_helpers.R` (new)
- `tests/testthat/test-zonal-stats.R`, `tests/testthat/test-zonal-known-answer.R`, `tests/testthat/test-mask-helpers.R` (new)
- `NEWS.md`
- `NAMESPACE`, `man/*.Rd` (only via `devtools::document()`)

## Goal of this batch

`wapor_zonal_stats()` for any polygons at any scale (nested levels, dissolve, AOI, crop share vs coverage, fraction weights, volumes only from depths or with `days`, population sd, weighted quantiles equal to type 7 for equal weights, CU, DU_lq, Gini, Theil, class shares) and the mask helpers `wapor_rasterize_mask()` and `wapor_harmonize_mask()`, whose fraction output is the `weights` input of the zonal engine.

## Validation (run in this order; report the result line of each)

```powershell
$R = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe"
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'zonal')"
& $R -e "devtools::test(filter = 'mask-helpers')"
& $R -e "devtools::test(filter = 'classify')"
& $R -e "devtools::test(filter = 'known-answer')"
```

## Done criteria

- [ ] All WP2 synthetic (18) and fixture (4) test groups and WP5A tests 1-3 pass
- [ ] One extra test: a fraction mask from `wapor_harmonize_mask()` used as `weights` in `wapor_zonal_stats()` gives the hand-computed weighted mean
- [ ] Crop share and coverage are separate; volumes only from depths or with `days`
- [ ] `devtools::test(filter = 'known-answer')` passes unchanged; `tests/testthat/fixtures/known-answer/` untouched
- [ ] No files changed outside the list above
- [ ] NEWS entry added under `# Rwapor 1.0.6 (development)`

## Report format (final message)

STATUS (done / partial / blocked) / FILES / VALIDATION (result line per command) / DONE CRITERIA (each
with evidence) / DEVIATIONS / QUESTIONS. The verifier then runs gate checks G1 to G10 (master plan
section 1A) before the next batch starts.

## Out of scope

Indicators (B3), crops and effective rainfall (B4), plots and offline URLs (B5). Do not refactor `wapor_ts()` or monitoring.
