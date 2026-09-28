# Rwapor production-readiness plan (after 1.0.4)

- **Date**: 2026-09-28
- **Author**: Claude (review session on branch `claude/ecstatic-allen-xdfb2g`)
- **Status**: Proposed. Every work package below was prototyped and verified
  in an isolated worktree; the reference patch is
  `docs/superpowers/plans/2026-09-28-production-readiness.patch`. None of it is
  applied to the package yet.
- **Scope**: the bottlenecks left open by the 2026-09-28 install/run review
  (session brief, "Open / proposals"), plus defects found while verifying them.
- **Related**: ISS-20260925-009, ti-08 (training plan
  `docs/superpowers/specs/2026-09-24-training-driven-improvements-plan.md`),
  ISS-20260928-010/-011/-012.

---

## 1. Executive summary

Rwapor 1.0.4 on the default branch (`version-1.0.4`) is **not yet ready for
general release**. Three defects that affect every user are fixed on branch
`claude/ecstatic-allen-xdfb2g`, which must be merged first:

| Defect on `version-1.0.4` | User impact | Fixed in |
|---|---|---|
| `wapor_map()` applied the WaPOR scale twice | All downloaded maps 10x too low | `1c96421` |
| `wapor_map()` returned a status list instead of file paths (since 1.0.1) | Getting-started example fails; the dashboard reports "Download failed" after every successful download | `e52dc5e` (section 3.1) |
| Windows CI red (race in a test fixture) | No green signal for the branch users install | `312e1ed` |

The branch is green on the full CI matrix (Windows, macOS, Linux
devel/release/oldrel-1, lintr/styler; run 36417147780 on `312e1ed`).

The remaining work is grouped into work packages WP1 to WP6. All were
prototyped and measured; WP5 was withdrawn because it gave no measurable
benefit. The largest gain is WP1 (disk footprint): **44 % less disk and 22 %
faster** on a 1 M-cell seasonal run, with identical results. WP6 removes all
96 GDAL warnings from a test run (and from every user COG export).

Recommended order: merge the fix branch, then WP3 (CI and install smoke
test), WP1, WP2, WP4, WP6, and release as **1.0.5** (section 5).

---

## 2. Verification environment and method

| Item | Value |
|---|---|
| OS / R | Ubuntu 24.04, R 4.3.3 |
| terra | 1.7.65 (Ubuntu) and 1.9.50 (current CRAN), both tested |
| GDAL / PROJ | 3.8.4 / 9.4.0 |
| Dashboard | headless Chromium (Playwright), all 6 tabs |
| Cross-platform | GitHub Actions R-CMD-check matrix (5 OS/R combinations) |
| Network | WaPOR API and CRAN unreachable; WaPOR COGs simulated with Int16 files carrying GDAL scale 0.1, API calls stubbed |

Each work package was implemented in a separate git worktree
(`proto/improvement-plan`), then verified with: focused regression tests
(failing before, passing after), the full test suite on both terra versions,
`R CMD check`, a disk/runtime benchmark, and, where relevant, an end-to-end run
or a negative test showing that the check catches the fault.

Limitation: no test ran against the live WaPOR API. Run
`inst/bench/remote_smoke_test.R` on a networked machine before the release
(section 5, step 6).

---

## 3. Work packages

Each package lists the problem, the evidence, the exact change, the files, the
tests, the verification already done, compatibility notes, effort and
acceptance criteria.

### 3.1 WP0 (blocker, implemented on the fix branch): `wapor_map()` return value

- **Problem**: since `5cf44fb` (2026-09-17, 1.0.1), a single-variable
  `wapor_map()` returns `list(status, variable, output_paths, ...)`. The
  documented return value is a character path.
- **Evidence**: `terra::rast(wapor_map(...))` (vignette *getting-started*,
  section 4.1) fails with "none of the elements of x are a SpatRaster". The
  dashboard (`mod_download.R:1101`) runs `file.exists(unlist(result))`, which
  tests `"ok"` and `"L1-AETI-D"` as file names and shows "Download failed ...
  expected files were not found" after every successful non-seasonal download.
- **Change**: return the character vector of paths (named list for several
  variables) and keep the run details in `attr(x, "wapor_status")`
  (`.wapor_map_paths()` in `R/wapor_map.R`); correct the `@return` text.
- **Tests**: `test-internal-helpers.R` "wapor_map returns file paths usable by
  terra::rast and the dashboard" (stubbed sources; stack and separate files;
  dashboard `unlist()`/`file.exists()` check).
- **Compatibility**: code written against the 1.0.1 to 1.0.4 list must use
  `attr(x, "wapor_status")$status` instead of `x$status`. No package code or
  documentation used the list form.
- **Acceptance**: the vignette example runs; a dashboard download shows
  "Download successful".

### 3.2 WP1: disk footprint of seasonal analysis (ISS-20260925-009, ti-08)

- **Problem**: large L3 runs fill the disk (Jendouba wheat: 5.1 M cells,
  21 dekads, failed at 8 GB free).
- **Root causes** (from the code):
  1. `keep_intermediates` defaults to TRUE in memory mode
     (`R/analysis_engine.R:353`) and materialises every dekadal stack.
  2. `wapor_export_analysis_outputs(include_dekadal = TRUE)` then writes them
     (the dashboard already passes FALSE).
  3. File-backed derived rasters, stream outputs and tiles are Float64
     (`terraOptions(datatype = "FLT8S")`, `processing_kernel.R:689,741`,
     `analysis_tiled.R:491`); exports inherit Float64 and are uncompressed.
  4. There is no estimate or warning before a run fills the disk.
- **Baseline measurement** (`inst/bench/disk_footprint_benchmark.R`; 1 M cells,
  18 dekads, 5 input variables, 14 indicators, local data):

  | Run | Time | terra temp | output_dir | Export | Export files |
  |---|---|---|---|---|---|
  | 1.0.4, defaults | 90.5 s | 897 MB | 151 MB | 240 MB | 63, all FLT8S |
  | 1.0.4, `keep_intermediates = TRUE` | 109.9 s | 1,009 MB | 151 MB | 531 MB | 68 |
  | **Prototype, defaults** | **70.5 s** | **505 MB** | **86 MB** | **124 MB** | 63, all FLT4S |
  | **Prototype, `keep_intermediates = TRUE`** | **76.6 s** | **559 MB** | **86 MB** | **124 MB** | 63 |

  Seasonal AETI mean: 468.051073 in all four runs (identical to 6 decimals).
  Total footprint: 1,288 MB to 715 MB by default (-44 %); 1,690 MB to 769 MB
  with kept intermediates (-55 %). Linear extrapolation to Jendouba (x5.1
  cells, x21/18 dekads): about 7.7 GB to 4.3 GB by default, 10 GB to 4.6 GB
  with kept intermediates (the training run failed at 8 GB free).
- **Change**:
  1. `keep_intermediates` is FALSE unless set (`isTRUE(config$keep_intermediates)`);
     registry steps still get stacks lazily (existing
     `results$dekadal_stacks %||% materialize_stacks()` path).
  2. `include_dekadal` defaults to FALSE in `wapor_export_analysis_outputs()`.
  3. Float32 for file-backed derived rasters, stream outputs, tiles and
     exports, written with `COMPRESS=LZW, PREDICTOR=3`
     (`.wapor_float_gtiff_options()`). The packed season-profile keys
     (`profile_keys.tif`) stay Float64 because they must be exact.
  4. `.wapor_estimate_disk_bytes()` and `.wapor_check_disk_space()`
     (`R/processing_plan.R`): the engine logs the estimate and warns when the
     output folder or terra's temp folder has less free space (via
     `ps::ps_disk_usage()`, already in Suggests; skipped when ps is missing;
     `options(Rwapor.disk_check = FALSE)` switches it off). The estimate uses a
     factor of 3 over the result layers, calibrated on the benchmark (measured
     2.6x), so it errs on the safe side.
- **Files**: `R/analysis_engine.R`, `R/analysis_utils.R`,
  `R/processing_kernel.R`, `R/analysis_tiled.R`, `R/processing_plan.R`,
  `R/wapor_map.R` (GTiff options), `man/wapor_export_analysis_outputs.Rd`,
  `tests/testthat/test-processing.R`, new `inst/bench/disk_footprint_benchmark.R`.
- **Tests**: existing mode-equivalence tests (memory = stream = tiled within
  1e-6) pass with Float32; new test "disk estimate scales with
  keep_intermediates and the check warns when space is short" (mocked free
  space, option switch).
- **Compatibility / behaviour change** (NEWS entry required):
  `results$dekadal_stacks` is no longer returned in memory mode unless
  `keep_intermediates = TRUE`; exports no longer contain `dekadal_stacks/`
  unless `include_dekadal = TRUE`; file-backed results are Float32
  (relative difference below 1e-7, far below the 0.1 mm resolution of WaPOR
  inputs).
- **Effort / risk**: 1 day / low.
- **Acceptance**: benchmark reproduces the table above within 10 %; mode
  equivalence tests pass; low-space warning shown with mocked free space.

### 3.3 WP2: `wapor_map()` stacks and local analysis

- **Problem**: `wapor_map()` writes one multi-band file by default
  (`<product>.<start>_<end>.tif`). `wapor_local_rasters()` matches only one
  file per time step and silently skips the stack, so a local analysis on
  default downloads finds no data without saying why.
- **Change**:
  1. `wapor_local_rasters()` warns when it skips stacks, naming the file and
     the remedy.
  2. New exported `wapor_unstack_map(path, folder, overwrite, remove_stack)`
     splits a stack into `<product>.<date>.tif` files (the
     `separate_files = TRUE` layout), keeps units, skips existing files, and
     validates the file name and band dates.
- **Rejected alternative**: reading stacks directly in the kernel. The kernel,
  tiling and date alignment all assume one path per dekad
  (`.wapor_align_paths_to_dekads()`); changing that touches three processing
  modes for a convenience that a one-line split provides.
- **Files**: `R/analysis.R`, `R/wapor_map.R`, `NAMESPACE`,
  `man/wapor_unstack_map.Rd`, `tests/testthat/test-processing.R`.
- **Tests**: "local reader warns about wapor_map() stacks and
  wapor_unstack_map() splits them" (warning text, split names, values, stack
  removal, bad path error).
- **Verification**: an end-to-end run with the stubbed downloader writes the
  stack, the reader warns ("Ignoring 1 multi-band stack(s) ..."), and the
  split files match `separate_files = TRUE` output.
- **Effort / risk**: 0.5 day / low (additive; one new export).
- **Acceptance**: a local analysis on default downloads either works after
  `wapor_unstack_map()` or stops with an actionable warning.

### 3.4 WP3: CI coverage, release signals and an install smoke test

- **Problems**:
  1. Workflows list branches by name; R-CMD-check covers `version-1.0.4` only
     because it was added by hand, and will stop at the next release branch.
  2. `test-coverage` never runs on the default branch.
  3. `pkgdown` deploys from `main`/`version-0.9.9`, not from the default
     branch, so the site documents old code.
  4. The README badge shows `main`, not the default branch.
  5. Nothing tests the install path users follow (README list,
     `install_github(build_vignettes = TRUE)`, `run_wapor()`). The missing
     `knitr`/`rmarkdown` and the undeclared `raster` dependency found on
     2026-09-28 would have been caught.
- **Change**:
  1. R-CMD-check and test-coverage: `push: branches: ['version-*', main,
     master]`, `pull_request` on all branches.
  2. pkgdown: same push filter plus a job condition
     `github.event_name != 'push' || github.ref_name ==
     github.event.repository.default_branch`, so only the default branch,
     releases and manual runs deploy.
  3. README badge: `?branch=version-1.0.4` (update at each release branch, or
     drop the branch parameter).
  4. New job `install-smoke` (Windows, macOS, Linux): installs the README
     package list, installs Rwapor with `remotes::install_local(".",
     build_vignettes = TRUE)`, runs README step 4, checks that vignettes are
     installed, starts `run_wapor()` in a background process and requires
     HTTP 200 within 180 s (log printed on failure).
- **Verification**: actionlint (wasm build) reports 0 findings on all three
  workflows, and it does flag a deliberately broken workflow. The smoke step
  script ran locally against a package installed with
  `install_local(build_vignettes = TRUE)`: HTTP 200 after about 21 s. With a
  deliberately broken dashboard module it fails and prints the cause
  ("Failed to source 'mod_download.R'"). The workflow changes themselves can
  only run on GitHub; run them once with `workflow_dispatch` after merging.
- **Files**: `.github/workflows/R-CMD-check.yaml`, `test-coverage.yaml`,
  `pkgdown.yaml`, `README.md`.
- **Effort / risk**: 0.5 day / low (CI only). Adds about 15 minutes of runner
  time per push (3 jobs, parallel).
- **Acceptance**: a PR from any branch triggers checks; the smoke job is green
  on all three OSs; pushing to the default branch redeploys the site.

### 3.5 WP4: GDAL settings applied at load time

- **Problem**: `.onLoad()` sets ten GDAL environment variables with
  `Sys.setenv()`, overwriting values the user, `.Renviron` or an institutional
  setup defined (for example `GDAL_HTTP_VERSION`, `GDAL_CACHEMAX`, proxy-related
  tuning). There is no opt-out: `RWAPOR_AUTO_CONFIG` is documented in a comment
  but not read.
- **Change**: `wapor_configure_gdal(overwrite = TRUE)` gains `overwrite`;
  `.onLoad()` calls it with `overwrite = FALSE` (only unset variables get the
  Rwapor defaults) and skips configuration when `RWAPOR_AUTO_CONFIG=false` or
  `options(Rwapor.configure_gdal = FALSE)`. Manual calls keep today's
  behaviour.
- **Files**: `R/gdal_config.R`, `man/wapor_configure_gdal.Rd`,
  `tests/testthat/test-gdal_config.R`.
- **Tests**: "load-time configuration keeps GDAL variables the user already
  set"; ".onLoad can be switched off with RWAPOR_AUTO_CONFIG".
- **Note on HTTP/2**: `GDAL_HTTP_VERSION=2` falls back to HTTP/1.1 when the
  server or proxy does not negotiate HTTP/2, so it stays the default; WP4 only
  makes it overridable.
- **Effort / risk**: 2 hours / low.

### 3.6 WP5: offline test-suite speed (withdrawn after measurement)

- **Hypothesis**: offline, API-dependent tests wait through httr2's
  exponential backoff (2 + 4 + 8 + 16 s), as seen in the first `R CMD check`
  of the review.
- **Prototype**: an `Rwapor.http_max_tries` option read by
  `.wapor_req_retry()`, set to 1 in `tests/testthat/setup.R`.
- **Measurement**: per-test timings of the full suite, branch versus prototype
  (terra 1.7.65): 228 s versus 224 s in total (noise); network-touching files
  1.4 s versus 1.7 s; no "retry backoff" lines in either `R CMD check`. The
  earlier waits came from the network test that now skips offline
  (fixed on the branch, `1c96421`), and dashboard start-up retries are
  already bounded (`wapor_fetch_l3_regions(timeout = 10, retry = FALSE)`).
- **Decision**: withdrawn; not in the reference patch. Revisit only if a new
  test calls the API without `skip_if_wapor_offline()`.

### 3.7 WP6: warning noise from `wapor_write_cog()`

- **Problem**: every COG write emits four GDAL messages ("driver MEM does not
  support creation option COMPRESS/OVERVIEWS/PREDICTOR/BIGTIFF"), 96 in one
  test run. terra passes the COG creation options to its intermediate
  dataset; the output is a valid COG (`LAYOUT=COG`, LZW). Users see the
  messages on every `cog = TRUE` export and may think the export failed.
- **Change**: `wapor_write_cog()` muffles exactly the "does not support
  creation option" messages and keeps all other warnings; the two
  `writeRaster()` branches are merged into one `do.call()`.
- **Verification**: terra 1.7.65 and 1.9.50: 4 warnings before, 0 after; output
  still `LAYOUT=COG`, values equal within 1e-6.
- **Tests**: "wapor_write_cog writes a valid COG without creation-option noise".
- **Effort / risk**: 1 hour / very low.

---

## 4. Consolidated verification results

| Check | Result |
|---|---|
| CI matrix on fix branch `312e1ed` (run 36417147780) | 6/6 jobs green (Windows, macOS, Linux devel/release/oldrel-1, lint) |
| CI matrix on fix branch `4455a67` incl. WP0 (run 36420057250) | green |
| CI on `version-1.0.4` `94b1533` (run 36397653719) | Windows failed (fixture race), fixed by `312e1ed` |
| Full suite, fix branch `4455a67`, terra 1.7.65 | 241 tests, 1,251 expectations, 0 failed, 7 skipped (live API), 231 s |
| Full suite, fix branch, terra 1.9.50 | 241 tests, 1,251 expectations, 0 failed, 238 s |
| Full suite, prototype (WP1 to WP6), terra 1.7.65 | 246 tests, 1,269 expectations, 0 failed, 229 s |
| Full suite, prototype, terra 1.9.50 | 246 tests, 1,269 expectations, 0 failed, 228 s |
| `R CMD check` (vignettes built and re-run), fix branch | Status: 1 NOTE (Suggests not installable offline); tests FAIL 0, **WARN 96**, PASS 1,251 |
| `R CMD check` (vignettes built and re-run), prototype | Status: 1 NOTE (same); tests FAIL 0, **WARN 0**, PASS 1,269 |
| Reference patch | applies cleanly to `4455a67` (`git apply --check`) |
| WP0 regression test on the old code | errors (2), passes after the fix |
| WP2 end to end (stubbed downloader) | reader warns on the stack; split files equal `separate_files = TRUE` output (max difference 0, units kept) |
| Dashboard, prototype build | 6 tabs, 0 server errors, 0 browser errors |
| Disk benchmark | table in 3.2 |
| Dashboard in headless Chromium (fix branch) | 6 tabs, 0 server errors, startup 12 s offline |
| Install smoke step (local) | HTTP 200 in 21 s; broken module detected |
| actionlint | 0 findings (3 workflows) |

---

## 5. Release plan (1.0.5)

1. **Merge** `claude/ecstatic-allen-xdfb2g` into `version-1.0.4` (scale fix,
   COG truncation fix, return-value fix, fixture fix, dashboard fixes).
   Confirm CI green on the default branch.
2. **Apply WP3 first** (CI only), then run R-CMD-check with
   `workflow_dispatch` to prove the smoke job on all three OSs.
3. **Apply WP1, WP2, WP4, WP6** from the reference patch, one commit each,
   regenerating `man/` and `NAMESPACE` with roxygen2 7.3.3
   (`devtools::document()`), so each can be reverted alone. The patch was
   produced with roxygen2 7.3.1; `RoxygenNote` is unchanged, but regenerate
   to be sure the Rd files match 7.3.3 output. Files per package:
   - WP1: `R/analysis_engine.R`, `R/analysis_utils.R`, `R/processing_kernel.R`,
     `R/analysis_tiled.R`, `R/processing_plan.R`, `R/wapor_map.R`
     (`.wapor_float_gtiff_options()` only), `man/wapor_export_analysis_outputs.Rd`,
     `man/wapor_run_seasonal_analysis.Rd`, `tests/testthat/test-processing.R`
     (disk test), `tests/testthat/test-analysis-shiny.R`,
     `inst/bench/disk_footprint_benchmark.R`;
   - WP2: `R/analysis.R`, `R/wapor_map.R` (`wapor_unstack_map()`), `NAMESPACE`,
     `man/wapor_unstack_map.Rd`, `tests/testthat/test-processing.R` (stack test);
   - WP3: `.github/workflows/*.yaml`, `README.md` (badge);
   - WP4: `R/gdal_config.R`, `man/wapor_configure_gdal.Rd`,
     `tests/testthat/test-gdal_config.R`;
   - WP6: `R/wapor_cog.R`, `tests/testthat/test-streaming-hardening.R`.
4. **Version**: create branch `version-1.0.5`, set `Version: 1.0.5`, move the
   1.0.4 NEWS items that were never released under 1.0.5 and add the
   behaviour-change notes from WP0 and WP1.
5. **Local checks on Windows** (maintainer machine):
   `devtools::test()`, `devtools::check()`, then `run_wapor()` and one
   download from each tab.
6. **Live checks** (networked machine): `inst/bench/remote_smoke_test.R`
   (5 live checks), one `wapor_map()` of `L1-AETI-D` for a small bbox:
   stored value x 0.1 x days per dekad must equal the output (for example
   25 mm/dekad for a stored 25 in a 10-day dekad), and one training case
   (JVA citrus) compared with the 2026-09-25 reference: seasonal AETI
   1,035.86 mm.
7. **Tag** `v1.0.5`, publish a GitHub release (triggers pkgdown), switch the
   repository default branch to `version-1.0.5`, update the README badge.
8. **Announce** with the NEWS behaviour changes (WP0 return value, WP1
   defaults).

### Optional, after 1.0.5 (not verified here)

- **Binary installs via R-universe** (`almutaz9000.r-universe.dev`): users get
  `install.packages("Rwapor", repos = c("https://almutaz9000.r-universe.dev",
  "https://cloud.r-project.org"))` with prebuilt binaries and no vignette
  build step. Needs a `packages.json` registry repository; about 1 hour.
- **Dashboard regression tests with shinytest2**: the headless check used here
  covers start-up and tab rendering; shinytest2 would also cover a download
  and an analysis run with stubbed data.
- ISS-20260923-002 (DuckDB raster blobs), ti-06 (download cache), ti-07
  (parallel remote opening) stay in the training plan.

---

## 6. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Scripts use the 1.0.1 to 1.0.4 list returned by `wapor_map()` | Low (undocumented) | NEWS note; details in `attr(x, "wapor_status")` |
| Users rely on `dekadal_stacks` being returned by default | Low | `keep_intermediates = TRUE` restores it; NEWS note |
| Float32 changes a published number | Very low | Differences below 1e-7 relative; benchmark means identical to 6 decimals |
| Disk estimate warns too often or too rarely | Medium | Calibrated with a safety factor of 3; warning only, never an error; `options(Rwapor.disk_check = FALSE)` |
| `ps_disk_usage()` misreports quotas (containers, network drives) | Medium | Warning only; falls back silently when unknown |
| CI smoke job flaky on runner start-up | Low | 180 s start-up window; the log is printed on failure |

---

## 7. Reproducing the measurements

- Disk benchmark: `Rscript inst/bench/disk_footprint_benchmark.R <pkg_path>
  <label> [default|TRUE|FALSE]` (set `BENCH_ROOT` to reuse the generated data,
  `BENCH_N` for the grid side; default 1000).
- Scale regression: `test-internal-helpers.R` ("map output applies the source
  file scale exactly once").
- Workflow lint: `npm install actionlint` (wasm), then lint each file in
  `.github/workflows/`.
- Dashboard: `run_wapor(launch.browser = FALSE, port = 8767)` and open each tab.
