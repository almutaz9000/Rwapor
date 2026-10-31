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
- Baseline and cache changes are committed on `docs/critical-review-improvement-plan`; nothing has been pushed. Cross-platform CI remains pending. Next distinct roadmap task: P2 raster I/O resilience and output integrity.


## Review limits and next verification

This review inspected package metadata, workflow configuration, selected API/cache and raster streaming implementations, test inventory, repository history, and current GitHub Actions summaries/log output. It did not inspect every source file. The repository branch was `version-1.0.6` at `0edffaa` when cloned; the review plan was committed locally on `docs/critical-review-improvement-plan`, and the baseline repairs described above are currently uncommitted. Local R validation is now available via `/opt/data/envs/rwapor`; GitHub Actions must still be rerun on the eventual branch to verify cross-platform behavior. Revisit and rank the roadmap after CI results.
