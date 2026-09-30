# P2 batch B4: perennial crops, Kc helper, effective rainfall and rainfed classes

_Batch brief for the implementing agent (Codex, Antigravity, Claude or any other model).
Implement **this batch only**. The next batch starts after this one passes its verification gate._

| | |
|---|---|
| **Priority** | P2-2 (core value) |
| **Board tasks** | `p2-b4` (batch gate: set to done only by the verifier after gate G1-G10 passes) + feature tasks `ti-11`, `p2-peff` (claim them before editing: `board_claim.ps1 -Id <id> -Model <you> -Status active`) |
| **Depends on** | B1 passed its gate (independent of B2 and B3) |
| **Branch** | `version-1.0.6` (update it from the default branch first; do not commit or push unless asked) |
| **Specification** | `docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md`: implement exactly section 6 (WP4) and section 8 (WP6) |
| **Science reference** | `docs/superpowers/reviews/2026-09-30-p2-domain-expert-review.md` (defaults, formulas and sources; never turn an UNVERIFIED value into a default) |

## Before you start

1. Read `agent-workflow/START-HERE.md`, then the master plan sections 0 (principles and conventions),
   1A (roadmap and verification gate) and the sections above, then the review sections they cite.
2. Check that the previous batch passed its gate: board task `p2-b1` is done and no other batch is in progress on the branch (never two batches at once).
3. Edit only the files listed below. If anything else must change, stop and report.

## Files you may change

- `R/crop_defaults.R`
- `R/kc_adjust.R` (new)
- the Kc curve code (`wapor_build_kc()` in `R/analysis.R`; kernel profile code in `R/processing_kernel.R`)
- the yield-chain and Peff / green-blue code (`R/analysis_engine.R`, `R/analysis_registry.R`, `R/indicators_math.R`, `R/analysis_indicators.R`; locate with grep as the WPs say)
- `tests/testthat/test-perennial.R`, `tests/testthat/test-peff-methods.R` (new)
- `NEWS.md`
- `man/*.Rd` (only via `devtools::document()`)

## Goal of this batch

Verified FAO-56 perennial rows (citrus x6 starting January, olives, grapes x2, pistachio, deciduous orchards x2); evergreen and deciduous crop types with dormant Kc; seasons crossing 1 January; NPP yield chain skipped for perennials; `wapor_adjust_kc_climate()` as a **manual helper only** (decision D10); corrected `fc` docs and crop-table notes (values unchanged, decision D5); effective-rainfall methods (`usda_cropwat` default unchanged, `fao_aglw`, `fixed`, `none`); rainfed classes (blue = 0, `unexplained_water`).

## Validation (run in this order; report the result line of each)

```powershell
$R = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe"
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'perennial')"
& $R -e "devtools::test(filter = 'peff-methods')"
& $R -e "devtools::test(filter = 'crop')"
& $R -e "devtools::test(filter = 'known-answer')"
& $R -e "devtools::test()"
```

## Done criteria

- [ ] All WP4 (8) and WP6 (6) test groups pass
- [ ] Default runs reproduce all 236 golden values (engine changes only act for perennial or rainfed types and non-default Peff methods)
- [ ] Every new crop row cites FAO-56; no UNVERIFIED crop (date palm, avocado, banana) added
- [ ] `wapor_adjust_kc_climate()` is not called anywhere in the analysis engine
- [ ] `devtools::test(filter = 'known-answer')` passes unchanged; `tests/testthat/fixtures/known-answer/` untouched
- [ ] No files changed outside the list above
- [ ] NEWS entry added under `# Rwapor 1.0.6 (development)`

## Report format (final message)

STATUS (done / partial / blocked) / FILES / VALIDATION (result line per command) / DONE CRITERIA (each
with evidence) / DEVIATIONS / QUESTIONS. The verifier then runs gate checks G1 to G10 (master plan
section 1A) before the next batch starts.

## Out of scope

Do not change existing crop values (decision D5 open). No automatic climate adjustment (D10). No measured-yield input (D1 open).
