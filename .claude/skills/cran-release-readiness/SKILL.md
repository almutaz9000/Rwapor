---
name: cran-release-readiness
description: >
  Step-by-step playbook for taking the Rwapor R package from its current state
  to a CRAN submission (and through CRAN's review/resubmission cycle). Use
  whenever the user asks about publishing Rwapor to CRAN, preparing a release,
  running R CMD check --as-cran, writing cran-comments.md, setting up
  win-builder/R-hub checks, or interpreting CRAN reviewer feedback. Primarily
  used by the r-package-cran-expert agent, but any agent should load this
  before touching release-adjacent files (DESCRIPTION, NAMESPACE, NEWS.md,
  .Rbuildignore, cran-comments.md, CI workflows).
---

# CRAN Release Readiness Playbook

This is the procedure, not just the checklist. Follow it in order — most
CRAN rejections come from skipping a step, not from a single hard bug.

## 0. Before you start: policy is a moving target

CRAN's Repository Policy changes without a changelog you'll be notified
of. Before a real submission attempt, fetch the current text at
https://cran.r-project.org/web/packages/policies.html rather than relying
on cached knowledge of "CRAN rules" — package size limits, example-runtime
budgets, and acceptable NOTE categories have all shifted over time.

## 1. Local hygiene pass

```r
# From the package root
devtools::document()          # regenerate NAMESPACE + Rd from roxygen2
devtools::load_all()          # sanity: package loads cleanly
devtools::test()              # full testthat suite, must be green
devtools::spell_check()       # or spelling::spell_check_package()
urlchecker::url_check()       # dead links are a check failure
```

Fix everything here before spending a check-machine cycle. `Rwapor` has 20
files under `tests/testthat/` as of this writing — a full green run is
non-negotiable before proceeding, not "the important ones pass."

## 2. Suggests-package audit

CRAN requires every use of an optional (`Suggests`) package inside `R/` to
degrade gracefully when that package isn't installed:

```r
# Correct pattern
if (!requireNamespace("duckdb", quietly = TRUE)) {
  stop("Package 'duckdb' is required for this function. Install it with ",
       "install.packages('duckdb').", call. = FALSE)
}
```

or, if `rlang` is available:

```r
rlang::check_installed("duckdb", reason = "to use wapor_monitoring functions")
```

Grep every `Suggests` entry from `DESCRIPTION` against `R/*.R` and confirm
a guard exists at every call site. `inst/shiny/*.R` is exempt — it's a
runtime app script, not parsed by `R CMD check` the way `R/` is — but
`run_wapor()` itself (the `R/`-level entry point that launches it) should
still confirm `shiny` is installed before calling `shiny::runApp()`.

## 3. R CMD check --as-cran

```r
rcmdcheck::rcmdcheck(args = c("--as-cran", "--no-manual"), error_on = "warning")
```

Target: 0 errors, 0 warnings. Every remaining NOTE gets either fixed or an
explicit justification written into `cran-comments.md` (step 6). Common
NOTE categories and what they usually mean for a geospatial package like
this one:

- *"installed size is Mb"* — large data objects (check
  `fao_crop_coefficients.csv`, `fao_growth_stages.csv`, and any bundled
  test rasters under `tests/rasters_inputs_samples/` — confirm the latter
  is excluded from the build via `.Rbuildignore`, not shipped).
- *"Namespaces in Imports field not imported from"* — an `Imports` entry
  with no actual `::` or `@importFrom` use; either use it or move it.
- *"Package has help entries with missing... executable examples"* — an
  exported function's Rd lacks a runnable `@examples` block or wraps it
  entirely in `\dontrun{}` with no non-`\dontrun` fallback.

## 4. Multi-platform checks

A local pass is necessary but not sufficient — Windows and macOS toolchain
differences (especially for `terra`/`sf`'s GDAL/GEOS/PROJ bindings) are a
recurring real risk for this package (see
`dev-tools/scripts/debug/check_env_windows.R`, an existing debug harness
for exactly this class of problem).

```r
devtools::check_win_devel()     # win-builder, R-devel
devtools::check_win_release()   # win-builder, R-release
rhub::rhub_check()               # R-hub v2, multiple platforms — requires GH Actions setup
```

Do not submit to CRAN until at least win-builder devel is clean — Windows
is the platform most likely to surface a GDAL/PROJ-related failure that
Linux CI won't catch.

## 5. CI workflows

If `.github/workflows/R-CMD-check.yaml` doesn't exist on the actual GitHub
remote (verify there, not just in a local checkout — branches can differ),
set it up from the current `r-lib/actions` examples
(https://github.com/r-lib/actions) rather than hand-rolling: a
`check-standard.yaml`-style matrix (ubuntu release + devel, windows,
macos) plus a separate coverage workflow feeding the `codecov.yml` that
already exists in this repo. Getting CI green *before* a CRAN submission
attempt saves check-machine cycles.

## 6. cran-comments.md

Required for every submission, new or update. Template:

```markdown
## R CMD check results

0 errors | 0 warnings | N notes

* This is a new release. / This release fixes ...
* [Explain every remaining NOTE here, one bullet each]

## Test environments

* local: <OS>, R <version>
* win-builder (devel and release)
* R-hub: <platforms actually run>
* GitHub Actions: ubuntu-latest (release, devel), windows-latest, macos-latest

## Downstream dependencies

[If this is not the first release: state whether reverse dependencies
were checked, e.g. via `revdepcheck::revdep_check()`, and the result.]
```

## 7. Version and NEWS discipline

- `DESCRIPTION` `Version` bump and the matching `NEWS.md` top entry
  (`# Rwapor X.Y.Z`) land in the same commit — this repo's existing
  convention (see current `NEWS.md`), keep it.
- Follow semantic versioning intent even though CRAN doesn't enforce
  SemVer strictly: breaking changes (like the 0.9.7 `rwapor_*` →
  `wapor_*` rename) deserve a major/minor bump and an explicit migration
  note, exactly as 0.9.7's `NEWS.md` entry already models.

## 8. Submission and resubmission

- Submit via https://cran.r-project.org/submit.html (or `devtools::release()`,
  which walks the same checklist interactively).
- A CRAN reviewer's first-round feedback is usually specific and small —
  fix exactly what's asked, re-run steps 1–3, and reply to the same
  submission thread rather than opening a new one, unless CRAN's own
  reply says otherwise.
- Never argue past two rounds without addressing the substance — CRAN
  maintainers volunteer their time; a fast, precise fix beats a long
  justification.

## Post-acceptance

- Tag the release in git (`vX.Y.Z`) and cut a GitHub Release matching
  `IMPROVEMENT_PLAN.md`'s stated release checklist.
- Watch the CRAN check results page for the package after acceptance —
  new R-devel or platform-specific failures surface there before anyone
  files an issue.
