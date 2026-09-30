# P2 batch B1: configurable classification engine

_Batch brief for the implementing agent (Codex, Antigravity, Claude or any other model).
Implement **this batch only**. The next batch starts after this one passes its verification gate._

| | |
|---|---|
| **Priority** | P2-1 (foundation) |
| **Board tasks** | `p2-b1` (batch gate: set to done only by the verifier after gate G1-G10 passes) + feature tasks `ti-10` (claim them before editing: `board_claim.ps1 -Id <id> -Model <you> -Status active`) |
| **Depends on** | nothing |
| **Branch** | `version-1.0.6` (update it from the default branch first; do not commit or push unless asked) |
| **Specification** | `docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md`: implement exactly section 3 (WP1) |
| **Science reference** | `docs/superpowers/reviews/2026-09-30-p2-domain-expert-review.md` (defaults, formulas and sources; never turn an UNVERIFIED value into a default) |

## Before you start

1. Read `agent-workflow/START-HERE.md`, then the master plan sections 0 (principles and conventions),
   1A (roadmap and verification gate) and the sections above, then the review sections they cite.
2. Check that the previous batch passed its gate: first batch, nothing to check.
3. Edit only the files listed below. If anything else must change, stop and report.

## Files you may change

- `R/classify.R` (new)
- `tests/testthat/test-classify.R` (new)
- `NEWS.md`
- `NAMESPACE`, `man/*.Rd` (only via `devtools::document()`)

## Goal of this batch

`wapor_classify()`, `wapor_class_defaults()` and `wapor_class_info()`: one classifier for every classification in the package, with literature defaults (adequacy, equity, per-method uniformity, spots) and their sources, user breaks and labels, fixed or percentile methods, reference groups, `min_n`, class direction, and metadata that survives GeoTIFF.

## Validation (run in this order; report the result line of each)

```powershell
$R = "C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe"
& $R -e "devtools::document()"
& $R -e "devtools::test(filter = 'classify')"
& $R -e "devtools::test(filter = 'known-answer')"
```

## Done criteria

- [ ] All 10 WP1 test groups pass with the independent expected values listed in WP1
- [ ] Thresholds only in `wapor_class_defaults()`; every scheme has a `source`
- [ ] `devtools::test(filter = 'known-answer')` passes unchanged; `tests/testthat/fixtures/known-answer/` untouched
- [ ] No files changed outside the list above
- [ ] NEWS entry added under `# Rwapor 1.0.6 (development)`

## Report format (final message)

STATUS (done / partial / blocked) / FILES / VALIDATION (result line per command) / DONE CRITERIA (each
with evidence) / DEVIATIONS / QUESTIONS. The verifier then runs gate checks G1 to G10 (master plan
section 1A) before the next batch starts.

## Out of scope

Zonal statistics, indicators and masks (later batches). No change to existing analysis code.
