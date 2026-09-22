# Rwapor raster streaming review: terra and gdalcubes

Date: 2026-09-18

## Scope and evidence

Reviewed the current raster path in `R/analysis_engine.R`, `R/analysis.R`, `R/analysis_indicators.R`, `R/analysis_tiled.R`, `R/anomaly.R`, and `R/gdal_config.R`, plus the existing memory and streaming tests. The working tree already contains unrelated modified and untracked files. No package source was changed by this review.

Opened web sources:

- terra `rast`: https://rspatial.github.io/terra/reference/rast.html
- terra `app`: https://rspatial.github.io/terra/reference/app.html
- terra read/write chunks: https://rspatial.github.io/terra/reference/readwrite.html
- terra options: https://rspatial.github.io/terra/reference/terraOptions.html
- terra parallelization: https://rspatial.org/pkg/10-parallel.html
- terra `chunk`: https://rspatial.github.io/terra/reference/chunk.html
- gdalcubes execution: https://gdalcubes.github.io/source/concepts/execution.html
- gdalcubes raster cube: https://gdalcubes.github.io/source/reference/ref/raster_cube.html
- gdalcubes reduce time: https://gdalcubes.github.io/source/reference/ref/reduce_time.cube.html
- gdalcubes write GeoTIFF: https://gdalcubes.github.io/source/reference/ref/write_tif.html

The opened terra documentation confirms that file-backed `SpatRaster` values are read lazily and processed in chunks. It also documents `readStart`/`readValues`/`writeStart`/`writeValues`/`writeStop`, `terraOptions(memfrac=, memmax=, parallel=, threads=)`, and `app(..., filename=, wopt=)`. Terra's parallelization guidance warns that `SpatRaster` external pointers should not be serialized directly to workers; pass filenames or use `wrap()` appropriately.

The opened gdalcubes documentation confirms that cubes are lazy proxy graphs, computation starts on materialization or export, processing is chunked in `[time, y, x]` order, and `raster_cube(..., incomplete_ok=FALSE)` is available. `reduce_time.cube` provides built-in temporal reducers including sum, mean, sd, and quantiles. `write_tif` can export time slices and supports COG output. gdalcubes uses a double-precision four-dimensional chunk buffer, so chunk size and worker count must be budgeted explicitly.

## Current Rwapor findings

### High priority memory and I/O findings

1. `R/analysis.R:134-147` materializes `terra::area(x)` with `terra::values(area_m2)` and then writes all values into another raster. This defeats lazy processing and creates a full-grid double vector. Replace with a lazy arithmetic expression such as `area_m2 / 10000`, or materialize once to a Float32 file when reuse justifies it.

2. `R/analysis.R:184-190` calls `terra::values(result, na.rm=TRUE)` only to test whether a harmonized mask contains valid pixels. Replace with a streaming global count or a small metadata/statistics query. This is a full-grid allocation on high-resolution masks.

3. `R/analysis_indicators.R:816-827` uses `terra::values()` for Theil's index, then repeats it for each class. This is the clearest existing full-value memory trap. Replace the overall calculation with a block-safe reducer and implement class summaries with a block accumulator keyed by class, or use a supported streaming zonal reducer. Do not retain a full vector per class.

4. `R/analysis_engine.R:205-215` builds and harmonizes complete time stacks before reduction. `terra::rast(paths)` itself is lazy, but repeated `resample`, arithmetic, masking, and derived products can create many temporary files and repeated full-stack passes. The production path should process aligned source windows or use a single output-backed reducer with explicit `filename` and `wopt` settings.

5. `R/analysis_indicators.R:18-46` has an `incremental` branch, but the non-incremental branch first constructs `x * weights`, optionally multiplies again, and then calls `app`. That is a large intermediate stack and extra disk I/O. The default should be an output-backed streaming reducer for long/high-resolution runs, with the faster path selected only after a memory estimate.

6. `R/analysis_indicators.R:570-607` computes weighted standard deviation through multiple raster passes. The `incremental` flag reduces only the weighted-sum part; the squared-difference accumulation still loops over all layers. Implement a one-pass or two-pass block accumulator for weighted sum, weighted sum of squares, and weight total, with explicit NA semantics.

7. `R/analysis_engine.R:653-715` applies a final mask to many results and monthly series after the calculations. This can force repeated reads and creates many derived raster graphs or temporary files. Mask once at the reducer boundary where possible, and avoid masking products that are already guaranteed to honor `valid_crop_mask`.

8. `R/analysis_tiled.R:877-889` writes cropped per-tile source rasters through `.wapor_window_source_rasters()`, but `.wapor_reduce_tile_indicators()` resolves and reads the original configured source paths instead of the returned `tile_sources`. This makes the source-copy phase unused work and can double local I/O and disk usage. Either remove the source-copy phase or pass the tile-local paths into the reducer.

9. The tiled engine is spatially bounded but currently processes tiles serially and only exports a subset of indicators. It is a useful correctness and restart boundary, not yet a complete high-throughput backend. Parallelize only after measuring per-worker memory and use filenames, not live `SpatRaster` pointers, across workers.

### Medium priority findings

10. `R/anomaly.R:28-34` computes mean and standard deviation as separate `terra::app` passes and then materializes a full multi-layer z-score result. This is valid but expensive for long series. Add an output-backed temporal reducer or a gdalcubes optional path for regular time cubes.

11. `R/analysis_engine.R:121-168` may project and resample a complete stack to the template grid. Reuse a validated target grid, avoid repeated geometry checks inside loops, and choose the output datatype explicitly. Continuous variables may use bilinear, while masks and season-day rasters must remain nearest neighbour.

12. `R/gdal_config.R:1-27` applies aggressive HTTP/GDAL defaults globally. `GDAL_CACHEMAX=512` and `VSI_CACHE_SIZE=100000000` are not bounded against the host's actual available RAM, and the package warning observed locally reported missing `/vsicurl/` and COG support. Make cache defaults adaptive, expose a per-run configuration, and keep capability checks separate from pure local processing.

## Verified benchmark

The benchmark used the installed package code and synthetic local Float32 GeoTIFFs because the current review scope prohibits live WaPOR calls.

Environment:

- Windows 11
- R 4.5.3
- terra 1.9.34
- GDAL 3.12.1 as reported by terra
- gdalcubes 0.7.5 installed from the author's R-universe because CRAN reported no package for this R version
- Rwapor loaded with `devtools::load_all(quiet=TRUE)`

Fixture:

- 1,000 x 1,000 cells, 36 dekadal layers, EPSG:4326, 0.001 degree cells
- Random Float32 AETI-like values and random Float32 season weights
- Local files only
- `terraOptions(memfrac=0.25)`
- Task: weighted seasonal sum, the current long-series reduction path

Results from the completed R run:

| Method | Elapsed | Mean result | In memory |
|---|---:|---:|---|
| `wapor_masked_sum(..., incremental=FALSE)` | 8.14 s | 8.998862 | TRUE |
| `wapor_masked_sum(..., incremental=TRUE)` | 6.55 s | 8.998862 | TRUE |

The incremental path was 19.5% faster in this fixture and had zero absolute difference in the reported mean. This is not a peak-RAM measurement, so it proves numerical parity and wall-clock behavior only. The result objects were memory-backed for this fixture, which means the benchmark did not yet exercise the full disk-backed regime.

The existing P95 path was also exercised on a 1,000 x 1,000 seasonal raster and 3-class mask. It completed in 2.44 s and returned 3 rows. This does not prove safe behavior at 20 m regional scale; it only confirms that the path runs on the smaller stress fixture.

A first 2,000 x 2,000, 36-layer run exceeded the 420 second execution limit during fixture creation or processing and produced no completed result. This is evidence that the benchmark must be staged at multiple sizes and instrumented for peak resident memory rather than treated as a single large run.

A separate gdalcubes run used the same 1,000 x 1,000, 36-image local fixture, a 10-day cube, 256 x 256 chunks, and annual temporal aggregation. gdalcubes construction and `aggregate_time` were lazy and took 0 s before materialization. `write_tif` materialization completed in 4.25 s. This is not an apples-to-apples comparison with Rwapor's weighted seasonal sum because the gdalcubes case used regular annual aggregation without pixel-specific season weights. It verifies the gdalcubes chunked execution path and lazy behavior, not superiority over terra.

## Recommendation

Do not replace terra in Rwapor. Keep terra as the package-facing engine and as the default for masks, season rasters, alignment, polygon summaries, L3 coverage policy, and irregular WaPOR-specific seasonal weighting.

Add a feature-flagged gdalcubes backend only for regular, large, multi-image temporal cubes. The adapter should:

1. Convert the validated Rwapor URL/date plan into an image collection with explicit dates and band names.
2. Define an explicit cube view with native CRS, native resolution, exact time boundaries, and declared resampling.
3. Set `incomplete_ok=FALSE` and independently validate the expected image/dekad set before materialization.
4. Use `reduce_time` or `apply_time` for regular temporal reducers, not for pixel-specific season weighting unless an adapter preserves the exact weights.
5. Keep categorical masks and season start/end rasters in terra.
6. Export with explicit COG options and convert to the existing `SpatRaster` contract.
7. Persist backend, package versions, source URLs, planned periods, missingness, chunking, and resampling metadata.

## Improvements plan

Phase 0, baseline and instrumentation

- Add peak RSS, elapsed time, temporary-file bytes, output size, and read/write counters to the benchmark harness.
- Benchmark 512, 1024, 2048, and, where hardware permits, a true 20 m regional window. Use 3, 12, 36, and 120 layers.
- Compare full, incremental, output-backed block, and optional gdalcubes paths on exactly the same values, masks, temporal plan, and missingness.

Phase 1, safe terra streaming

- Replace full `values()` calls in pixel-area, mask validation, and Theil paths.
- Add `filename` and explicit `wopt` to long-series reducers.
- Implement a shared block reducer using `readStart`/`readValues` and `writeStart`/`writeValues`, or equivalent terra output-backed operations.
- Remove the unused tile source copy or make the reducer consume it.
- Add tests for numerical parity, NA handling, zero weights, partial seasons, one-pixel tiles, and tile restart.

Phase 2, tile throughput

- Add bounded parallel tile execution using source filenames and a worker memory budget.
- Align tile boundaries to source GDAL blocks where possible.
- Record per-tile timing, bytes, retries, and peak estimates in the manifest.
- Expand tiled outputs only after each indicator has a documented memory and parity test.

Phase 3, optional gdalcubes pilot

- Add internal capability detection and an optional dependency path. Do not add gdalcubes to Imports.
- Implement a local-file adapter first, then a local HTTP COG fixture, then an opt-in WaPOR adapter.
- Require exact parity for temporal boundaries, missingness, CRS/resolution, and resampling before enabling it for users.
- Use gdalcubes for regular time-cube reductions and keep Rwapor's terra engine for irregular season logic and categorical products.

## Confirmed plan decisions

The grill-me decision round confirmed:

- Use both synthetic fixtures for automated gates and a local or cached true WaPOR L3 20 m fixture for release evidence.
- Keep terra as the primary engine. Add gdalcubes only as an optional backend for regular temporal cubes.
- First implementation slice: remove full-grid `values()` traps, fix tiled source-copy waste, and add instrumented benchmarks.
- Accept only results whose peak resident memory stays within a declared budget and scales with tile size rather than full-AOI cell count.

Implementation should wait for a separate scoped change session after this review, because the current working tree contains existing work owned by other changes.

High confidence: terra is the lower-risk optimization target because it is already an Rwapor dependency, is integrated throughout the engine, and officially supports file-backed chunk processing.

Medium confidence: gdalcubes is a useful optional backend for regular temporal cube workloads. The official documentation supports the required lazy/chunked primitives, but the current benchmark did not compare equivalent Rwapor seasonal semantics.

Speculative until a larger instrumented run: expected speedup at true 20 m regional scale. The completed run measured wall time and numerical parity but not peak resident memory, and the larger fixture timed out.

Not tested: live WaPOR HTTP range behavior, remote COG compatibility in this local GDAL build, multi-worker throughput, exactextractr parity, and production-sized 20 m regions.
