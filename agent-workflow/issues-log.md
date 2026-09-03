# Issues Log

_Operational issue tracker for agents. See `templates/issue-entry.md` for the
entry format. Stable IDs: `ISS-YYYYMMDD-###`._

## Open

### ISS-20260903-002 — L3 seasonal planning trusts a static, region-blind availability list

- **Where**: `wapor_temporal_codes()` in `R/plan_wapor_time_slices.R`
  (fallback branch), backed by the static `WAPOR3_VARS` list in
  `R/metadata.R`.
- **Root cause**: available temporal resolutions (A/M/D/E) for a variable are
  looked up from a hardcoded list, not from the live GISMGR API for the
  specific `l3_region` requested. A given L3 mosaic region may not actually
  publish every resolution the static list implies.
- **Impact**: the seasonal planner can select a resolution (e.g. monthly) for
  which that specific L3 region has no data. `wapor_generate_urls()` then
  returns zero URLs for that code group.
- **Mitigation in place (2026-09-03)**: `download_seasonal_rasters()` now
  tracks any code group with zero URLs and surfaces it in a single aggregated
  warning plus `missing_periods`/`attr(result, "missing_periods")`, instead of
  silently dropping it. This makes the gap visible but does not prevent it.
- **Real fix (not done)**: query live L3 metadata per region before planning,
  or fall back to a finer resolution automatically when a coarser one yields
  no URLs.

## Resolved

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
