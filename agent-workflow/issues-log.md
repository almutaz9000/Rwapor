# Issues Log

_Operational issue tracker for agents. See `templates/issue-entry.md` for the
entry format. Stable IDs: `ISS-YYYYMMDD-###`._

## Open

- None currently recorded.

## Resolved

### ISS-20260917-001 — Dashboard crashes on every `board_claim.ps1` update (UTF-8 BOM)

- **Where**: `agent-workflow/dashboard/app.py`.
- **Root cause**: `load_board()` decoded `agents-board.json` as plain
  `utf-8`. `board_claim.ps1` (`Set-Content -Encoding utf8` on Windows
  PowerShell) always writes a UTF-8 BOM, which `json.loads`/`.read_text()`
  reject outright. This meant the dashboard had been broken since the very
  first `board_claim.ps1` call ever made against the file -- the original
  `coord-board-v1` smoke test passed because it ran before any
  `board_claim.ps1` write existed (hand-authored JSON has no BOM).
- **Fix**: Decode with `utf-8-sig` instead (tolerates a BOM or no BOM).
- **Verification**: relaunched the dashboard on a test port, confirmed
  `HTTP 200` with no traceback in the log (previously a full
  `JSONDecodeError` traceback rendered in-page); a direct script using the
  same load path confirmed correct task/status data (42 tasks, correct
  done/pending counts).

### ISS-20260917-002 — Task tracker (task-status.md / agents-board.json / IMPROVEMENT_PLAN.md) drifted from actual code state

- **Where**: `agent-workflow/task-status.md`, `agent-workflow/agents-board.json`,
  `IMPROVEMENT_PLAN.md`.
- **Found during**: a critical re-review of "pending" tasks requested by the
  user, cross-checking each task's described deliverable directly against
  the codebase (grep for the named functions/files) rather than trusting the
  tracker.
- **What was found**: several tasks listed as fully "pending" were actually
  substantially or fully implemented already:
  - **2.2 (COG write support)** -- fully done (`wapor_write_cog()` exported
    and used throughout) except `cog=FALSE` missing from
    `wapor_run_seasonal_analysis()` and no GDAL<3.1 fallback.
  - **3.1 (9 extra FAO-56 crops)** -- fully done, all 9 crops present.
  - **1.6 (reference_layer param)** -- the core parameter is done, exact
    match to spec; missing `resampling_method` per layer.
  - **3.4 (anomaly module)** -- 3 of 4 functions done and exported; missing
    `linear_trend`.
  - **5.1 / 5.2 (test coverage)** -- both test files already exist with
    real coverage, just short of the full spec (Python parity, 100x100
    grid / multi-season / local-vs-API specifics not confirmed).
  - **6.1 (vignettes)** -- 4 vignettes exist, but none under the 5
    originally-specified names/scopes.
  - **6.2 (README install guide)** -- system deps and verify step present;
    missing only the terra-from-GitHub install note.
- **Likely cause**: `IMPROVEMENT_PLAN.md`'s task list predates a lot of
  since-landed work (`feat/l3-mosaic-tiled-core`, the 2026-09-15 production
  hardening pass, etc.) and was never swept for completions; the
  2026-09-16 `agents-board.json` back-filled these as "pending" from the
  stale prose file without independently checking the code.
- **Fix**: Corrected task status/notes in `IMPROVEMENT_PLAN.md` (checkboxes)
  and `agents-board.json` (2.2, 3.1 -> done; 1.6, 3.4, 5.1, 5.2, 6.1, 6.2 ->
  notes updated with exactly what's done vs missing, status kept pending
  for the genuine remaining gap).
- **Lesson**: before starting any "pending" task from this tracker, grep
  the codebase for its named deliverable first -- the tracker is a lagging
  indicator, not ground truth. See `project-memory.md`.

### ISS-20260916-002 — Duplicate `%||%` with conflicting semantics; triplicated level->URL mapping

- **Where**: `R/utils.R`, `R/wapor_metadata_cache.R`, `R/api_client.R`,
  `R/metadata.R`.
- **Root cause**: `%||%` was defined twice -- `R/utils.R:8`
  (`is.null()`-only) and `R/wapor_metadata_cache.R` (also `length() > 0`).
  `DESCRIPTION` has no `Collate:` field, so R loads `R/*.R` alphabetically;
  `wapor_metadata_cache.R` loads after `utils.R` and its definition silently
  overwrote the package-wide `%||%` binding for ~40 call sites across
  `crop_defaults.R`, `wapor_ts.R`, `wapor_map.R`, `analysis_engine.R`,
  `analysis_tiled.R`, `wapor_monitoring.R`, `wapor_cog.R`,
  `rwapor_favorites.R`, `analysis_utils.R`. Separately, the FAO catalogue
  workspace URL for a level was hardcoded independently in three files
  (`wapor_generate_urls_internal()`, the `url_map` inside
  `wapor_update_metadata()`, and a `switch()` inside
  `.fetch_metadata_api_variable()`); the `wapor_update_metadata()` copy had
  already drifted (missing `AGERA5`).
- **Fix**: Deleted the duplicate `%||%`; kept one canonical definition in
  `R/utils.R`. Verified against the full test suite which one is correct --
  `tests/testthat/test-wapor_metadata_cache.R:104` requires the
  length-aware behavior, because `jsonlite::write_json()` round-trips a
  `NULL` list element as an empty *non-`NULL`* list, not `NULL`, so a plain
  `is.null()` check would have kept the empty list instead of falling
  through to the real default. Added `.wapor_level_workspace_url(level)` in
  `R/api_client.R` as the single source of truth for the URL mapping.
  **Correction (2026-09-17)**: the 2026-09-16 fix was reported as routing
  all three call sites through the helper but actually only did 2 of 3 --
  `.fetch_metadata_api_variable()` in `metadata.R` still had its own
  hardcoded `switch()`. Caught via diff self-review while implementing
  Phase 7.1 the next day and fixed then; all three sites are genuinely
  consolidated as of 2026-09-17.
- **Verification**: `devtools::load_all()` clean; `devtools::document()`
  produced no unexpected `NAMESPACE`/`man/` diffs; full test suite
  `0 fail / 1019 passed` (an intermediate `1 fail / 1018 passed` was caught
  and fixed before this was considered done).

### ISS-20260916-001 — Metadata service duplication and resolution ambiguity

- **Where**: `R/metadata.R`, `R/wapor_metadata_cache.R`,
  `R/plan_wapor_time_slices.R`, `R/wapor_res_key.R`.
- **Fix**: Unified API and bundled metadata normalization, separated level,
  temporal resolution, and spatial resolution, added atomic snapshots and a
  manifest, and routed temporal planning and resolution grouping through the
  validated catalogue.
- **Verification**: Full test suite passed with 0 failures; bundled L1/L2/L3
  snapshots validated for unique codes and matching level/temporal fields.

### ISS-20260903-002 — L3 seasonal planning trusts a static, region-blind availability list

- **Where**: `wapor_temporal_codes()` in `R/plan_wapor_time_slices.R`.
- **Resolution**: Temporal availability now starts from the validated metadata
  catalogue and, for L3 requests with a region and period, checks actual URLs
  for each candidate resolution before planning. Static metadata remains only
  as a controlled fallback.
- **Verification**: Planner and full test suites pass; region-filtered temporal
  availability is covered by regression tests.

### ISS-20260903-001 — Seasonal download pipeline could silently serve wrong or incomplete data

- **Reported/found**: 2026-09-03, during a robustness audit of the WaPOR
  smart seasonal download path (`R/api_client.R`, `R/seasonal_download.R`,
  `R/plan_wapor_time_slices.R`).
- **Root causes** (three related defects):
  1. `.wapor_url_hash()` used a byte-sum + length checksum as the disk-cache
     key. Two different date-range queries whose request strings are
     character permutations of equal length collided, so the wrong cached
     URL list could be served within the 24h TTL. `IMPROVEMENT_PLAN.md` had
     already specified `digest::digest(url_query, "sha256")` for this; the
     shipped code diverged from that spec.
  2. `download_seasonal_rasters()` had no retry on `terra::rast(vsicurl_urls)`
     (unlike the non-seasonal path in `wapor_ts.R`), so one transient network
     failure dropped an entire resolution group (e.g. all monthly slices).
  3. Both the "no URLs for a code group" and "no URL match for a plan row"
     cases were `warning()`-and-`next` with no reconciliation against the
     plan, so the returned seasonal sum could silently under-represent the
     requested period.
- **Fix**: `.wapor_url_hash()` now uses `digest::digest(x, "sha256")`
  (`digest` added to `Imports`). Added retry-with-backoff (3 attempts) to the
  seasonal raster loader, matching `wapor_ts.R`'s existing pattern. Added
  `missing_period_ids` tracking across all three failure points in
  `download_seasonal_rasters()`, with a single aggregated warning (exact
  missing period IDs + day-coverage shortfall) and a `missing_periods` field
  on the return value, exposed to callers via
  `attr(wapor_ts(seasonal=TRUE) result, "missing_periods")`. Also upgraded
  the shared API retry policy (`.wapor_req_retry()`) to exponential backoff
  with `Retry-After` header support.
- **Regression tests**: `tests/testthat/test-url-cache.R` (hash collision +
  determinism), `tests/testthat/test-seasonal_download.R` (aggregated warning
  + `missing_periods` on partial failure; clean `missing_periods` on full
  success).
- **Verification**: `devtools::test()` — 638 passed, 0 failed, 0 warnings,
  6 skipped (live-API tests, no network in this environment).

### ISS-20260917-003 — Remote COG streaming retries stopped before pixel I/O

- **Found**: 2026-09-17, during a terra/COG streaming audit against the Cloud
  Native Geo terra guidance.
- **Root causes**: retry loops covered `terra::rast()` metadata opening but not
  later crop, extraction, reduction, or output operations that force pixel I/O;
  non-seasonal map/time-series paths could return partial batches by default;
  datatype probing used `terra::values()` and could materialize a full layer;
  fallback COG documentation overclaimed overview support.
- **Fix**: added `.wapor_retry_remote_operation()` and applied it around crop,
  zonal extraction, global reduction, tiled window reads, and output writes;
  default `partial = FALSE` now refuses incomplete map/time-series results;
  partial time-series results carry `partial` and `failed_layers` attributes;
  datatype probing uses a bounded `readValues()` window; fallback output is
  documented as tiled compressed GeoTIFF when the COG driver is unavailable.
  - **Verification**: all scoped R files parse; direct retry-helper execution
    passes; `git diff --check` passes. Full R tests are blocked in this working
    environment because `terra`, `devtools`, and `testthat` are not installed.

  - **2026-09-21 resolution (Codex)**: User reassigned ownership. A real local
    `terra`/GDAL environment is available. A live 12-layer JVA monthly stack
    opened in 2.81 seconds, so the 10 MB range-cache setting was not the
    observed bottleneck. The reported run looked frozen because no status was
    emitted during the later crop-and-write phase; granular console and Shiny
    progress were added. Parse, Shiny construction, 138 focused assertions,
    and a 12-layer live output run passed. A 72-layer temporary probe emitted
    chunk 1 and 2 progress but did not provide a completion line in this tool
    session; it is not claimed as a complete end-to-end result.
- **Remaining**: run the complete suite and local HTTP range fixture on an R
  environment with terra/GDAL; replace driver-table curl detection with a
  dedicated local capability probe; remove tiled-source duplicate remote reads.
