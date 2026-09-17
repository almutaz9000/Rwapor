# Rwapor remote COG streaming hardening plan

## Scope

This plan hardens the current `/vsicurl/` raster paths in `wapor_map()`, `wapor_ts()`, seasonal downloads, and tiled processing without making live WaPOR requests. Verification uses synthetic rasters and a local HTTP server that supports byte ranges.

## Findings and fixes

### F1. Retry coverage stops at `terra::rast()`

`terra::rast()` normally establishes a file-backed raster reference and reads metadata. Pixel I/O happens later during crop, mask, resample, zonal extraction, global reduction, conversion, or output writing. The current retry loops therefore do not cover the failure-prone part of streaming.

Fix: add a bounded retry helper and use it around the complete remote read/processing unit. The retry must return the completed result, not a lazy raster reference. Keep retries finite, log attempts, and preserve the final error.

Acceptance:
- injected failure on an operation is retried and eventually succeeds;
- repeated failure raises a clear error after the configured attempts;
- no unbounded retry or hidden failure.

### F2. Partial non-seasonal outputs can be returned as success

`wapor_map()` and `wapor_ts()` currently continue when some batches fail. This is scientifically unsafe by default because an output may represent only part of the requested period.

Fix: when any batch fails and `partial = FALSE`, stop before publishing/returning the result. When `partial = TRUE`, return the result with explicit incomplete status and failed-layer metadata.

Acceptance:
- zero failed batches behaves unchanged;
- one failed batch fails the default path;
- partial mode returns data plus an explicit incomplete marker and failed URLs.

### F3. Datatype probing can read a complete raster layer

The COG writer uses `terra::values(x)` before writing, which can materialize the first layer. This undermines out-of-core behavior for large outputs.

Fix: sample a bounded number of cells with `terra::readValues()` using only the minimum leading rows needed for the sample.

Acceptance:
- datatype classification remains correct for integer, negative, floating, and all-NA fixtures;
- sample read is bounded by at most 10,000 cells.

### F4. Fallback output is not guaranteed to have overviews

The fallback writer uses `COPY_SRC_OVERVIEWS=YES`, which copies existing overviews but does not guarantee that overviews are created. It should not claim that every fallback is a full COG.

Fix: describe the fallback accurately as tiled compressed GeoTIFF unless the COG driver is available. Keep atomic publication and validation.

Acceptance:
- COG-driver path remains unchanged;
- fallback documentation does not overclaim COG compliance;
- output remains readable and tiled where supported.

### F5. GDAL capability warning needs separate verification

COG is a GDAL driver, while `/vsicurl/` is a VSI handler. Driver-table inspection is not sufficient proof of curl support.

Fix in this slice: avoid treating the current warning as proof of a code defect and document the limitation. A real capability probe should be a separate follow-up because it needs a safe local HTTP fixture or an installed GDAL CLI and must not contact WaPOR.

## Verification matrix

1. Pure helper tests: retry success/failure, partial policy, bounded datatype sample, URL prefixing, window partitioning.
2. Synthetic local raster tests: map/TS batch behavior and output readability.
3. Local HTTP range fixture: `/vsicurl/` open plus crop/read and request statistics, never live WaPOR.
4. Package gates: `devtools::load_all()`, focused test file, full `testthat` suite, `R CMD check`, `git diff --check`.
5. Remote-state verification: after push, fetch and compare the remote branch SHA with the local commit.

## Explicit non-goals

- No live WaPOR API or production data read.
- No change to WaPOR product semantics, units, CRS, or temporal aggregation.
- No unrelated cleanup of the pre-existing working tree.
- No force push and no history rewrite.
