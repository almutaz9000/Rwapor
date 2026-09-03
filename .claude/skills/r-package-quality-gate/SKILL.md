---
name: r-package-quality-gate
description: >
  The command sequence every code change to Rwapor should pass before it's
  considered done — from a single-function edit up to a release. Use before
  finishing any R/ or inst/shiny/ change, and always before a release. This
  operationalizes IMPROVEMENT_PLAN.md's "Verification Strategy" section.
---

# R Package Quality Gate

Three tiers, matched to the size of the change. Never skip a tier because
the change "looks small" — run the fast tier every time, escalate as
scope grows.

## Tier 1 — every change, no exceptions

```r
# Fast, no network, targeted to the area touched
devtools::load_all()
devtools::test(filter = "test-indicators-math|test-analysis-engine")  # adjust filter to the area touched
```

Pick the filter to match what you touched:

| Touched | Filter |
|---|---|
| `R/indicators_math.R`, `R/analysis_indicators.R` | `test-indicators-math\|test-analysis-indicators` |
| `R/analysis_engine.R`, `R/analysis_tiled.R`, `R/analysis_registry.R` | `test-analysis-engine\|test-analysis-registry` |
| `R/analysis_utils.R` (pixel area, alignment) | `test-pixel-area` |
| `R/anomaly.R` | `test-anomaly` |
| `R/crop_defaults.R`, crop CSVs | `test-custom-crops` |
| `R/wapor_metadata_cache.R`, `R/metadata.R` | `test-wapor_metadata_cache` |
| `R/wapor_monitoring.R` | (DuckDB monitoring — check for a matching test file before assuming coverage; add one if missing) |
| `R/plan_wapor_time_slices.R` | `test-plan_wapor_time_slices` |
| `R/gdal_config.R` | `test-gdal_config` |
| `inst/shiny/*` | `test-dashboard-validation\|test-analysis-shiny` |

## Tier 2 — before opening/updating a PR

```r
lintr::lint_package()      # once .lintr exists — see r-package-cran-expert gaps list
styler::style_pkg()
devtools::test()            # full suite — all ~20 files under tests/testthat/
```

A change that fails Tier 1 but is "fixed" by narrowing the test filter
further is not fixed — go back to Tier 1 with the original filter.

## Tier 3 — before a release / merging anything release-adjacent

```r
devtools::test()
covr::package_coverage()
devtools::build_vignettes()
rcmdcheck::rcmdcheck(args = c("--as-cran", "--no-manual"), error_on = "warning")
```

Then hand off to the `cran-release-readiness` skill for the full
submission playbook (win-builder, R-hub, cran-comments.md).

## Non-negotiables regardless of tier

- **New/changed indicator math**: add or update a unit test on a small,
  hand-computed matrix in the pure-math test files
  (`test-indicators-math.R` et al.) — not just an integration test through
  a SpatRaster. This is `IMPROVEMENT_PLAN.md` §5.1's explicit standard,
  and it's the only way to keep these tests fast and terra-independent.
- **New/changed raster alignment or area logic**: test at more than one
  latitude (see `test-pixel-area.R`'s existing pattern) — a
  latitude-independent bug hides trivially in a single-latitude fixture.
- **New/changed Suggests-package usage in `R/`**: confirm a
  `requireNamespace()`/`rlang::check_installed()` guard exists — see
  `r-package-cran-expert`'s Suggests audit.
- **New/changed network-touching code**: confirm the corresponding test
  uses the existing offline-skip pattern (`tests/testthat/helper-skip.R`,
  `setup.R`) rather than either always running against the live API or
  silently no-op'ing.
- **Never** commit with a red Tier 1 result "to fix later" — a failing
  test on `main`/the release branch erodes the signal for everyone after
  you.
