# Rwapor: Critical Review and Robust Improvement Plan

**Review basis:** local clone of `almutaz9000/Rwapor`, branch `version-1.0.6`, HEAD `0edffaa` (tag `v1.0.6`; same commit as `origin/main` at review time). This is a static, code-informed review, not a claim that R CMD check or tests passed. The environment used for this review has no `R` executable, so package checks could not be run. Recheck upstream before implementation; findings below distinguish verified observations from risks to validate.

## Executive assessment

Rwapor already has substantial engineering in place: modular analysis and processing layers, fixture/known-answer testing, chunked raster handling, GDAL `/vsicurl/` streaming, retry helpers, provenance support, cross-platform CI, and a dedicated live-API workflow. Improvements should build on that foundation rather than replace it.

The highest-value next work is to make scale and load behavior measurable, harden concurrency and cache edge cases, improve network/API observability, and make spatial correctness/reproducibility gates explicit. Avoid broad refactors until tests and benchmark evidence identify a bottleneck.

## Evidence-led review findings

1. **Validation could not be executed locally (verified).** `R --version` returned `R: command not found`. The repository does define R CMD check, lint/style, install-smoke, and manually dispatched live API CI, but their current state was not retrieved during this review. Treat all test/check status as unknown until CI is queried or R is installed.
2. **Remote raster operation policy is split across layers (verified).** `R/api_client.R` defines API retry behavior for 429/5xx and `Retry-After`; `R/wapor_map.R` separately retries raster opening and calls a retry wrapper for crop/write; other processing paths also invoke the shared remote-operation retry helper. Review whether retryability, attempt limits, backoff/jitter, and diagnostics are consistent across API, GDAL reads, and file writes. Do not retry deterministic errors or non-idempotent output operations blindly.
3. **Parallel streaming has global/process-level configuration concerns (verified, risk assessment).** `wapor_map()` invokes `future_lapply()` when parallel is enabled; processing code configures terra/GDAL per worker. Confirm worker limits, restoration/isolation of global options, fork-vs-multisession behavior, cleanup after worker failure, and aggregate memory/network budgets under concurrent jobs. Add tests before changing behavior.
4. **Multi-band output assembly deserves scale and atomicity validation (verified, risk assessment).** Chunks are written to temporary GeoTIFFs and then assembled; the final stack write is outside the shown remote retry wrapper, and partial/failure handling must not leave a misleading final artifact. Test interruption, disk-full, overwrite, many bands, and cleanup. Prefer temp-file-then-atomic-rename where supported and report layer-level completeness explicitly.
5. **Persistent URL cache writes are not visibly atomic or concurrency-safe (verified).** `collect_responses()` writes an RDS cache directly with `saveRDS()` and suppresses write errors. Concurrent sessions can collide on the same key or readers may encounter a partially written entry. Use lock/temp-write/rename or an established cache primitive; test corruption recovery and parallel writers. Preserve current TTL and opt-out semantics.
6. **Operational observability can be strengthened (recommendation).** Chunk status has URLs/errors, but review user-facing logs and returned metadata for elapsed time, byte/attempt counts where available, retry reason, request IDs, and partial coverage. Keep sensitive query tokens out of logs and outputs.
7. **Geospatial scientific invariants should remain first-class (recommendation).** Protect scale/offset exactly-once behavior, CRS/grid alignment, nodata, temporal interval semantics, unit conversion, area weighting, and polygon boundary handling with small synthetic tests plus known-answer cross-validation. Do not change scientific formulas without a cited basis and golden-test impact analysis.

## Prioritized roadmap

### P0 — Establish a reproducible baseline (small, separate PR)
- Query current GitHub Actions and open issues/PRs; capture check results and avoid duplicating in-flight work.
- Run `R CMD check`, testthat, lintr/styler, package install smoke, and the offline known-answer/cross-validation suites in a supported R/GDAL environment.
- Record exact R, terra, GDAL, PROJ, GEOS versions and platform. Separate environmental failures from package defects.
- Add a concise developer validation guide listing commands and offline vs live tests.

**Acceptance:** CI/check results linked in PR; test counts and skips reported; no claim of green when checks were not run.

### P1 — Cache correctness and concurrency (high impact, bounded)
- Make URL-cache writes atomic and safe for concurrent readers/writers; validate entry shape/version and recover from corrupt/stale files.
- Add tests for simultaneous same-key requests, truncated RDS, zero/negative TTL, cache disabled, and cache invalidation.
- Consider deduplicating duplicate in-flight API requests only if evidence shows meaningful traffic or race issues.

**Acceptance:** deterministic tests pass on Windows/macOS/Linux; no partial cache files observed; public cache behavior remains compatible.

### P2 — Raster I/O resilience and output integrity
- Unify retry policy semantics across catalogue requests and remote raster operations while retaining distinct retry classifiers for HTTP, GDAL/network, and local filesystem failures.
- Add exponential backoff with bounded jitter where appropriate; honor server retry hints; make attempts/timeouts configurable only if a concrete use case exists.
- Write final products to a same-filesystem temporary path and atomically publish only after successful close/validation; clean temporary artifacts on errors.
- Test transient vs permanent failures, partial mode, all-chunks-failed, output overwrite, disk-full simulation, and process interruption.
- Ensure final output metadata records expected/received/failed layers and time coverage, with no silent gaps.

**Acceptance:** failure-injection tests prove no corrupt final file is presented as complete; partial mode is explicit and auditable; retry logs identify the failing operation without leaking URLs/secrets.

### P3 — Big-data/concurrency budgets and benchmarks
- Build reproducible synthetic raster benchmarks varying AOI size, layer count, chunk size, worker count, compression, local vs remote source, and memory/disk constraints.
- Measure peak RSS, temp-disk use, throughput, and output equivalence; report environment and warm/cold cache conditions.
- Verify worker-level GDAL cache/memory limits sum to a safe process-wide budget, that user future plans are respected/restored, and that parallel execution does not oversubscribe network/API or file descriptors.
- Tune defaults only from benchmark evidence; document knobs and trade-offs.

**Acceptance:** benchmark script produces machine-readable results; serial/parallel outputs match the same known-answer tolerances; bounded-memory claim backed by measured scaling.

### P4 — Spatial/scientific correctness and API contract
- Expand fixtures for rotated/non-square grids, differing CRS/resolution, nodata edges, antimeridian or invalid geometries where supported, scale/offset metadata variants, empty/one-pixel AOIs, and temporal gaps/overlaps.
- Add API contract tests from sanitized recorded responses: pagination, malformed envelope/link, missing fields, 429/5xx, Retry-After, redirects, and schema drift.
- Pin/test supported dependency ranges (especially terra, GDAL, httr2); report dependency versions in diagnostics.
- Keep golden values and provenance manifests versioned; changes to expected outputs require documented scientific rationale.

**Acceptance:** boundary-focused tests demonstrate intended CRS, grid, nodata, time, units, and provenance behavior; live API test remains optional and separate from deterministic offline checks.

### P5 — Package maintainability and user-facing contracts
- Audit exported API consistency, argument validation, return classes, warning/error semantics, and lifecycle of temporary/cache files.
- Ensure all exports have current examples and Rd docs; check README/vignettes agree with actual Imports/Suggests and installation paths.
- Review CI action pinning/security and matrix coverage; use least-privilege tokens and avoid live-service dependencies in routine pull-request checks.
- Add migration/release notes for any behavior changes; retain backwards compatibility unless explicitly versioned.

**Acceptance:** R CMD check clean under the declared support matrix, docs/examples consistent, and any breaking change called out in NEWS and migration notes.

## PR sequencing and boundaries

1. Baseline evidence and validation guide (no runtime changes).
2. Cache atomicity/concurrency (isolated implementation + focused tests).
3. Remote I/O/output atomicity (separate from cache changes).
4. Benchmark/diagnostics and evidence-based tuning.
5. Spatial/API contract test expansion and any independently justified fixes.
6. Documentation/API polish after behavior stabilizes.

Each PR should state the observed problem, evidence/reproduction, scope, scientific/data implications, tests actually run, and residual limitations. Keep PRs reviewable; no catch-all “hardening” PR. Do not push directly to the default branch or merge PRs without explicit authorization.

## Current remote validation evidence (queried 2026-10-31)

- `gh run list` showed the latest push workflow run `39423716949`, started 2026-10-20 at 12:37 UTC for HEAD `0edffaa`. The matching test-coverage run `39423716952` failed; pkgdown succeeded.
- Latest run check-runs showed install-smoke passing on Ubuntu/macOS/Windows and lintr/styler passing. The R CMD check matrix failed on Ubuntu release/devel/oldrel-1, macOS release, and Windows release.
- Retrieved failed log output shows 7,149 passes, 47 failures, 11 warnings, 6 skips in the Ubuntu devel check; the visible failures include `test-indicator-spec.R` expecting entries/fields in `inst/spec/indicators.yaml` that are missing. The captured log was extremely large/truncated, so this is evidence of at least one failure class, not a complete diagnosis of all matrix failures. Fetch concise logs/artifacts and inspect the actual YAML/test loader behavior before proposing a fix.
- No open GitHub issues or pull requests were returned.

## Execution status (updated 2026-10-31)

- **P0 baseline: complete locally.** Installed R 4.5.3 in `/opt/data/envs/rwapor` with terra 1.9.50, sf 1.1.3, GDAL 3.13.3, and package test dependencies. This is an isolated user-space environment; invoke it with `/opt/data/.local/bin/micromamba run -p /opt/data/envs/rwapor ...`.
- **Existing failures reproduced and addressed in the working branch.** The indicator-spec failure came from tests leaving temporary indicator registrations in the shared package registry. Tests now defer cleanup of registrations they add. The cross-validation fixture manifest had an outdated SHA-256 for `expected.json`; updated only the checksum, not expected values.
- **P1 cache safety: implemented and locally verified.** URL-cache RDS entries are serialized to unique sibling temporary files, read back for validation, and then published by rename; a platform fallback may cause a brief cache miss but never exposes a partially serialized cache file. Added tests for concurrent PSOCK writers, failed publication cleanup, corrupt-entry refetch/repair, zero-TTL bypass, replacement, and no leftover temp files.
- **Verification:** focused registry/spec, cross-validation, API-fixture, and URL-cache tests passed. The complete R CMD check passed with `Status: OK` using `_R_CHECK_FORCE_SUGGESTS_=false`, `--no-manual`, and `--no-build-vignettes`; package build generated vignettes, check confirmed their code runs, and vignette-output rebuilding was skipped. Test summary: 4,030 passed, 0 failed, 11 warnings, 29 skipped (optional/live cases). `lintr` passed on the modified R files. This is local Linux validation, not a replacement for the GitHub platform matrix.
- **P2 output-publication slice: complete locally.** `wapor_map()` now publishes multi-band stacks and separate per-date rasters through the sibling-temp raster writer. The writer validates a non-empty temp file, preserves/restores an existing output if publication fails, and cleans temporary artifacts; removed the non-atomic `file.copy()` fallback that could expose an incomplete final GeoTIFF.
- **Verification:** focused map/download-cache tests passed. Complete R CMD check passed with `Status: OK`; test summary: 4,036 passed, 0 failed, 11 warnings, 29 skipped. `lintr` passed on touched R files. Cross-platform GitHub CI remains pending; this is local Linux validation.
- Baseline, P1 cache-safety, and P2 output-publication changes are committed on `docs/critical-review-improvement-plan`; nothing has been pushed. Remaining P2 work includes retry classification/consistency, transient-vs-permanent failure tests, and explicit completeness/coverage behavior.



## Review limits and next verification

This review inspected package metadata, workflow configuration, selected API/cache and raster streaming implementations, test inventory, repository history, and current GitHub Actions summaries/log output. It did not inspect every source file. The repository branch was `version-1.0.6` at `0edffaa` when cloned; the review plan was committed locally on `docs/critical-review-improvement-plan`, and the baseline repairs described above are currently uncommitted. Local R validation is now available via `/opt/data/envs/rwapor`; GitHub Actions must still be rerun on the eventual branch to verify cross-platform behavior. Revisit and rank the roadmap after CI results.

## Documentation and indicator audit (2026-11-02)

**Review basis:** active local checkout `/opt/data/Rwapor`, branch `docs/critical-review-improvement-plan`, HEAD `a953116`. Working tree was clean before this audit. Findings were cross-checked against current source files; full offline test suite completed with 7,070 passed, 0 failed, 11 warnings, 15 skipped (optional packages and disabled live API tests). This audit is supplementary to the engineering roadmap above.

### Verified documentation defects

1. **Fixed:** `vignettes/getting-started.Rmd` now uses exported `wapor_variable_metadata()` rather than internal `get_variable_metadata()`.
2. **Fixed:** `vignettes/getting-started.Rmd` no longer says Rwapor automatically sets 10 MB GDAL chunks; it describes the current default and links readers to `wapor_configure_gdal()`.
3. **Fixed:** `vignettes/data-catalog.Rmd` now distinguishes retrieval mode `unit_conversion = "none"` from target-unit values such as `"day"` accepted by the lower-level conversion helpers.
4. **Fixed:** README and data-catalog now describe 20 m as the standard Level 3 resolution and note selected daily 10 m products. Package metadata contains 21 L3 records with resolutions {10, 20}; FAO's current overview gives 20 m as the standard and its Jendouba pilot page documents the selected 10 m daily exception.
5. **Fixed:** README now lists all seven package vignettes locally and online; all seven published HTML articles were confirmed on `origin/gh-pages`.
6. **Fixed:** README citation now matches `inst/CITATION` and `DESCRIPTION` (2026, package version 1.0.6); the R CMD check badge now tracks the verified `version-1.0.6` remote branch.
7. **Fixed:** `.Rbuildignore` now matches the plural `IMPROVEMENTS_PLAN.md`. A source tarball built before the fix included the internal plan; a tarball built after the fix excluded it.
8. **Fixed:** first-person verification narration in `vignettes/wheat-water-productivity.Rmd` was replaced with neutral descriptions of per-season masks and timing behavior.

### Methodology/processing findings to validate before changing behavior

- `R/analysis_engine.R:160-166` defaults RET resampling to nearest while PCP is bilinear. This is a meaningful continuous-variable consistency question, but the correct choice depends on the analysis-grid and source-grid contract. Compare documented intent and test both methods on synthetic gradients and native product grids before changing defaults.
- `R/utils.R:238-245` uses a factor of 3 to convert dekadal totals to monthly totals. This may be correct for three dekadal accumulation values per calendar month; do not treat the varying number of days in the third dekad as proof of a bug. Validate the meaning of the source units and output semantics, then update tests/docs if needed.
- The crop-yield `fc` parameter appears in the implemented equation but is fixed at 1 in defaults. Its scientific interpretation and cited support are not established by this code review. Trace the method to primary references and document or constrain it; do not remove it or alter yield math without source-backed justification and independent numeric tests.
- The remaining AETI/ETc, green/blue partition, NPP-to-biomass, yield, CWP/BWP, area-weighting, cross-year timing, and monthly Peff computations inspected so far had coherent internal implementation/tests. This is not an exhaustive scientific validation of every indicator.

### Gated implementation sequence

1. **Baseline gate (in progress):** finish and record full offline `devtools::test()` output; confirm exit status and warnings. Build/check package with vignettes enabled and inspect package contents. Do not use successful test command launch as evidence of success.
2. **Documentation correctness slice:** fix the exported metadata function example, obsolete GDAL claim, invalid unit-conversion prose, product-resolution wording after authoritative metadata check, omitted vignette links, stale badge/citation, and first-person notes. After each cohesive change, render/build relevant vignette(s), run their examples where offline-safe, and inspect README links/code blocks.
3. **Packaging hygiene slice:** correct the `.Rbuildignore` pattern only if tarball inspection proves the internal plan is included unintentionally; rebuild and inspect the sdist.
4. **Resampling methodology slice:** document input/output grid behavior, add a synthetic continuous-gradient test and a product-grid regression test, decide nearest vs bilinear based on declared semantics, then change code only if evidence supports it. Re-run focused and full tests.
5. **Unit-conversion semantics slice:** test known dekad accumulations across 28/29/30/31-day months and daily-rate inputs; make the source and target units explicit. Change code only if current output violates the intended unit contract; otherwise correct/expand docs and tests.
6. **Yield-method slice:** locate and cite primary scientific support for `fc`, `AOT`, moisture content and harvest index; add independent hand-calculated tests for defaults and non-default parameters. If the literature does not support a term, resolve the formula before modifying it.
7. **Landing-page structure polish:** after accuracy is fixed, provide visible routes for dashboard/no-code users, R users, and contributors; add a screenshot/output preview and only verified status badges; keep installation and getting-started steps copy-pasteable.

**Gate rule:** complete, verify, and record each slice before starting the next. At every code change, run the focused test first, then the full offline suite at the end; for documentation, build the affected vignette/site and validate links/snippets. Preserve a clean separation between confirmed defects and scientific choices awaiting source evidence. No external actions (push/PR/release) are authorized by this plan.

### Execution log

- **Baseline:** `/opt/data/.local/bin/micromamba run -p /opt/data/envs/rwapor Rscript -e 'devtools::test()'` completed: 7,070 passed, 0 failed, 11 warnings, 15 skipped (optional packages and disabled live API tests).
- **Documentation fixes completed and verified:** public metadata function call returned `mm/day`; `wapor_configure_gdal()` export and `chunk_size` argument confirmed; resolver accepted `"none"` and rejected `"day"`, while `wapor_convert_units()` converted 20 mm/dekad to 2 mm/day; L3 metadata JSON confirmed 21 records with 10/20 m resolution values. The edited Getting Started, Data Catalog, and Wheat vignettes rendered to HTML with code execution disabled; the seasonal-mask behavior test passed (9/9). FAO WaPOR pages were checked for the 20 m baseline and Jendouba 10 m daily exception.
- **README/package hygiene slice completed and verified:** all 7 vignettes have README browse commands and existing pkgdown article files; version/year/citation match package metadata and the badge branch exists remotely. A source tarball included `IMPROVEMENTS_PLAN.md` before the `.Rbuildignore` correction and excluded it afterward. These builds used `--no-build-vignettes` only to inspect source-package membership; they are not package-check results.
- **Documentation build/check gate completed:** `R CMD build .` built `Rwapor_1.0.6.tar.gz` with vignettes; `_R_CHECK_FORCE_SUGGESTS_=false R CMD check --no-manual Rwapor_1.0.6.tar.gz` completed with `Status: OK`. Vignette outputs rebuilt successfully and tests passed. Constraint: optional Suggests were unavailable (including ggplot2, leaflet, arrow, duckdb, and related packages), so this is not a full Suggests-matrix check; Rd cross-reference checking reported an INFO for unavailable `ggplot2`.
- **Confirmed global-tiled vignette correction:** replaced the incorrect claim that WaPOR RET is AgERA5 at about 9 km with the package metadata-backed description (L1 RET is about 30 km) and made clear RET defaults to nearest while PCP defaults to bilinear. Rendered `vignettes/global-tiled.Rmd` successfully; Pandoc reported the existing YAML/index-title mismatch and deprecated `--mathjax` warning. The change does not decide whether the RET default should change.
- **RET methodology review:** research notes saved in `docs/RET_RESAMPLING_RESEARCH.md`. Initial interpolation-theory arguments were narrowed after checking WaPOR-specific literature: studies document both nearest-neighbour and bilinear use in different processing contexts, but do not compare their accuracy for Rwapor's current v3 L1 RET alignment. A local synthetic-gradient experiment confirmed bilinear had lower RMSE than nearest on a constructed linear field (square-grid control: 0.05484 vs 0.16057; non-square 0.3125° × 0.25° grid: 0.03478 vs 0.10675). This is algorithm behavior on an analytic field, not evidence of real-product accuracy. No resampling behavior changed.
- **Yield-method documentation slice:** primary FAO and peer-reviewed WaPOR method sources confirm the yield formula's literature lineage and show that `fc`, biomass fraction, and HI conventions are method/crop-specific. The preliminary scratch review overclaimed numeric contradictions; therefore no crop defaults, formula, or validator bounds were changed. Updated `fc` docs from “ground cover/light interception” to LUE correction, clarified crop-specific AOT/HI interpretation (including root/tuber method conventions), and added the FAO quality-assessment and WaPOR case-study references to the yield API docs. Focused `analysis-indicators` tests passed (84/84); lintr found no issues in touched R files.
- **README example-flow correction:** the end-to-end analysis example now constructs its maize `crop_params` object and explicitly states the local raster and class-mask prerequisites. The crop parameter construction was exercised in R. The complete package build/check after these documentation changes completed with `Status: OK`; check was constrained with `_R_CHECK_FORCE_SUGGESTS_=false` and retained the `ggplot2` Rd-xref INFO.
- **P2 retry-classification slice implemented and checked:** GDAL already has request-level HTTP retries configured; the package-level API classifier previously treated every 5xx as transient, and the remote-operation wrapper retried every error, including permission failures. The API/raster classifiers now share an explicit transient HTTP status set (429, 500, 502, 503, 504); the outer raster wrapper retries recognized HTTP/cURL/network failures only and stops on local or unrecognized errors. RED/GREEN regression tests cover timeout/503 retries, 501 and permission-denied no-retry, and the NULL sentinel. Focused API/cache/retry tests passed (48); full `devtools::test()` before the final map call-site cleanup passed 7,078, failed 0, warnings 11, skips 15; the additional NULL test passed separately. The manual `wapor_map()` open retry loop now uses the shared classifier while preserving its failed-chunk result shape. Focused download-cache/internal-helper/retry tests passed (93); lintr and `git diff --check` passed. The vignettes-enabled package build/check on that tree completed `Status: OK` with constrained optional Suggests and the `ggplot2` Rd-xref INFO.
- **P2 backoff, hints, and retry-cache recovery implemented and verified:** `Retry-After` uses httr2's parser for delay-seconds and HTTP-date; API and remote-operation waits use bounded exponential full jitter; transient raster retries clear GDAL's process-local VSI cache. In a local HTTP/COG probe, a 503 followed by a valid TIFF failed without cache cleanup (the failed URL was not requested again) and succeeded on retry after cache cleanup. A separate forced 503 GET probe observed four GDAL GET attempts for a configured maximum of three, after which terra returned an unsupported-format error and the outer classifier correctly avoided another whole-operation retry. Full `devtools::test()` after the httr2 callback fix passed 7,092, failed 0, warnings 11, skips 15. Sequential `R CMD build .` and `_R_CHECK_FORCE_SUGGESTS_=false R CMD check --no-manual Rwapor_1.0.6.tar.gz` completed `Status: OK`; R CMD check reported 4,058 passes, 0 failures, 11 warnings, and 29 skips (optional/live/CRAN-conditional cases), plus the `ggplot2` Rd-xref INFO. Focused retry/API/cache tests, lintr, and `git diff --check` passed.
- **P2 output completeness slice implemented:** added chunk-status metadata for `ok`, `partial`, and `failed` runs, including expected/received/failed layer counts, coverage fraction, requested period, received layer names, and chunk counts. Strict mode errors on missing chunks; partial mode reports `status = "partial"`; all-chunks-failed returns no paths with `status = "failed"`. `separate_files = TRUE` stages all layers and publishes the set with rollback; stack chunks stage in a hidden per-run directory that is cleaned on strict-mode abort. Local fixture tests cover partial stacks/files, all-failed status, strict no-publish/temp cleanup, and a later per-file publication failure that rolls back prior outputs. Focused internal/map tests passed (109); full `devtools::test()` passed 7,170, failed 0, warnings 11, skips 15. Sequential package build/check completed `Status: OK`; R CMD check reported 4,136 passes, 0 failures, 11 warnings, and 29 skips, with optional Suggests constrained and the `ggplot2` Rd-xref INFO. `lintr` and `git diff --check` passed.
- **Retry-attempt probe (bounded evidence):** with the local HTTP/COG fixture, a permanently failing HEAD was requested once per outer attempt (3 times for `max_retries = 3`) after VSI-cache clearing; a forced 503 range GET produced four GDAL GET attempts with `GDAL_HTTP_MAX_RETRY = 3`, after which terra surfaced a generic unsupported-format error and the outer classifier did not retry it. This characterizes one GDAL/Rwapor setup, not a global throughput/load bound; attempt defaults were left unchanged.
- **P3 benchmark instrumentation and scaling smoke:** `large_raster_benchmark.R` accepts a durable results directory and worker count, and records R/terra/GDAL/PROJ, grid/dekad/budget, planned workers, tile/batch sizes, process-tree RSS, and cache caveats in CSV. At 1000×1000/12 dekads, serial and 2-worker mean AETI matched exactly (419.99357). With a 512 MB total budget, serial forced memory/stream/tiled above-baseline RSS was 822/658/840 MB; with 2 workers it was 803/416/177 MB. At 1200×1200/18 dekads with 2 workers, `auto` selected tiled (tile size 777; estimated per-worker working set 255.6 MB against a 256 MB per-worker budget); mean AETI matched across modes (633.5364). Forced memory/stream measured 2,101.9/765.4 MB above baseline, while auto/tiled measured about 235/221 MB. The process-tree sampler saw up to three processes but peak RSS often occurred in one process, so this is not yet a validated worker-specific memory bound. No defaults were tuned; OS page cache was uncontrolled. CSVs are in `/opt/data/cache/scratch/rwapor-bench-*`.
- **Disk-footprint benchmark improvement:** `disk_footprint_benchmark.R` writes a machine-readable CSV to an explicit path, records versions/cache conditions, labels `gc()` output as post-analysis R heap (not peak), and computes dekad keys when `BENCH_ROOT` already exists. A 500×500/18-dekad smoke run: 23.3 s analysis, 2.2 s export, 216.6 MB terra temp, 25.7 MB output, 50.3 MB export (73 Float32 TIFFs), mean AETI 467.947595. CSV: `/opt/data/cache/scratch/rwapor-diskbench/results_500.csv`. Both scripts ran and passed lintr; a final `R CMD build .` succeeded and tar inspection confirmed both updated scripts are included while `IMPROVEMENTS_PLAN.md` is excluded. A full R CMD check was not repeated for these benchmark-script-only edits.
- **Next:** measure actual parallel-tile RSS and temporary disk use on larger, resource-safe cases; test remote/local source differences and reconcile those measurements with the planner's per-worker estimates before tuning defaults.
