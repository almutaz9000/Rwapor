# terra and gdalcubes benchmark and Rwapor integration assessment

Date: 2026-09-17

## Executive conclusion

`gdalcubes` is technically compatible with several Rwapor workloads, but it should be introduced as an optional temporal-cube backend, not as a replacement for terra.

The local benchmark showed exact numerical parity for a controlled temporal mean, but terra was faster for this small local crop. gdalcubes becomes more attractive when the workload is a repeated, regular spatiotemporal cube operation over many source images, especially when chunked processing, temporal regularization, on-the-fly reprojection, and chained pixel operations are useful.

The main adoption risk is semantic: gdalcubes regularizes time into a `cube_view` and can tolerate incomplete I/O by default. Rwapor must preserve WaPOR dekad boundaries, overlap-day weights, missing-period status, native product resolution, categorical-mask resampling, and the package default of refusing incomplete results.

## Sources reviewed

- gdalcubes project and capabilities: https://github.com/appelmar/gdalcubes/
- `raster_cube()` reference: https://gdalcubes.github.io/source/reference/ref/raster_cube.html
- `create_image_collection()` reference: https://gdalcubes.github.io/source/reference/ref/create_image_collection.html
- Collection formats: https://gdalcubes.github.io/source/concepts/collection_formats.html
- Data-cube operations: https://gdalcubes.github.io/source/concepts/operations.html
- terra COG access guide: https://guide.cloudnativegeo.org/cloud-optimized-geotiffs/accessing-cogs-in-r-terra.html

## gdalcubes capabilities relevant to Rwapor

### Image collections

`create_image_collection()` builds a SQLite index containing references and metadata for local files or GDAL dataset identifiers. It can also accept virtual filesystem identifiers. Without a collection format, a single-band-per-file collection can be created by supplying explicit dates and band names.

`stac_image_collection()` can build the index from STAC features without opening every image during collection creation. This is the preferred cloud workflow when a STAC catalog exists.

The current Rwapor API path returns URL lists rather than STAC Items. Therefore, direct gdalcubes integration would need either:

1. an adapter that creates a collection from `/vsicurl/` URLs plus dates and band names, or
2. a Rwapor STAC/catalog adapter if the upstream service can provide equivalent metadata.

### Regular data cubes

`cube_view()` defines the target spatial extent, CRS, resolution, temporal extent, temporal resolution, aggregation, and resampling. `raster_cube()` returns a lazy proxy. Expensive reading begins when the cube is materialized or exported.

`raster_cube()` supports configurable chunking in time, y, and x order. It also exposes `incomplete_ok`, which defaults to `TRUE`. Rwapor must set `incomplete_ok = FALSE` for complete-data workflows and independently validate requested coverage.

### Operations

Relevant operations include:

- `select_bands()`
- `select_time()` and `slice_time()`
- `crop()`
- `filter_geom()` and `filter_pixel()`
- `apply_pixel()`
- `reduce_time()`
- `reduce_space()`
- `window_time()` and `window_space()`
- `join_bands()`
- `query_timeseries()` and `zonal_statistics()`
- `write_tif()` and `write_ncdf()`

The operation chain is lazy and chunked. This can reduce intermediate files and make temporal expressions concise.

### COG and GDAL support

The installed gdalcubes build reports the COG and HTTP GDAL drivers. `write_tif()` supports `COG = TRUE`, overviews, compression creation options, and JSON descriptions. This is stronger than Rwapor's current fallback contract, although actual COG validity still needs inspection with GDAL metadata tools.

## Benchmark method

The reproducible script is:

`docs/research/benchmark_terra_gdalcubes.R`

Fixture:

- R 4.5.0
- terra 1.9.50
- gdalcubes 0.7.4
- GDAL 3.12.1 as reported by terra
- six synthetic 256 x 256 Float32 tiled GeoTIFFs
- dates every ten days from 2023-01-01
- constant values 1 through 6 by date
- identical 192 x 192 spatial subset
- explicit gdalcubes `dt = "P10D"`
- nearest-neighbour spatial resampling
- temporal mean over the same six observations
- gdalcubes chunking `c(1, 128, 128)`
- local files only, no WaPOR or external network request

The initial benchmark used `nt = 3` without an explicit `dt`, and gdalcubes extended the temporal view and returned 2.25 instead of terra's 2.0. Re-running with explicit `dt = "P10D"` returned exact parity. This demonstrates that temporal view construction is a material correctness requirement.

## Benchmark result

| Case | terra | gdalcubes |
|---|---:|---:|
| Elapsed time | 0.02 s | 0.44 s |
| Output cells | 36,864 | 36,864 |
| Mean value | 3.5 | 3.5 |
| Maximum absolute difference | 0 | 0 |

Interpretation:

- terra was approximately 10.75 times faster in this small local benchmark.
- This is not a general performance ranking. The workload is small, local, already aligned, and has no network latency.
- gdalcubes paid proxy/cube/chunk orchestration overhead that dominates at this size.
- A larger cloud benchmark is still required to compare HTTP range requests, repeated temporal reductions, and memory behavior.

## Comparison for Rwapor workloads

| Rwapor workload | terra | gdalcubes | Recommendation |
|---|---|---|---|
| Open one WaPOR COG and crop an AOI | Direct and simple | Possible but unnecessary cube setup | Keep terra |
| Polygon time series from a few layers | Existing exactextractr path is integrated | `zonal_statistics()` may help but needs parity validation | Keep terra initially |
| Seasonal dekadal AETI/RET aggregation | Existing WaPOR-specific overlap-day semantics | Possible with `cube_view` and `reduce_time`, but semantics need an adapter | Pilot only |
| Large regular multiband time cube | Requires application-level batching | Native cube/chunk model is attractive | Consider gdalcubes |
| Pixel expressions across bands/time | terra supports app/map algebra | `apply_pixel()` and reducers are natural | Consider gdalcubes |
| L3 multi-region mosaic | Rwapor has explicit coverage policy and manifests | Cube can combine sources, but coverage provenance needs custom handling | Keep Rwapor orchestration |
| Crop-mask and season start/end rasters | terra integration already exists | Requires joining/aligning separate cubes | Keep terra |
| COG output | Current atomic writer and validation | `write_tif(COG=TRUE)` is useful | Compare and optionally reuse |
| Local fallback without COG GDAL driver | Rwapor fallback exists | gdalcubes also depends on GDAL capabilities | Do not use as fallback without capability checks |

## Proposed integration boundary

### Keep in terra

- Region parsing and CRS-safe AOI handling
- Categorical crop masks and nearest-neighbour alignment
- Season start/end rasters and Julian-day logic
- WaPOR-specific temporal planning and overlap-day multipliers
- Existing exactextractr polygon statistics until numerical parity is proven
- L3 selection, mosaic-all policy, coverage manifests, and provenance
- Final package-facing `SpatRaster` results and current compatibility APIs

### Add as an optional backend

Add an internal adapter only after a pilot proves parity:

1. Convert the validated Rwapor URL/date plan into a gdalcubes image collection.
2. Set an explicit `cube_view` with native product CRS/resolution and exact time windows.
3. Set `incomplete_ok = FALSE`.
4. Apply only continuous-data resampling to AETI, RET, PCP, NPP, and temperature.
5. Keep masks and season rasters in terra or create a separate categorical cube with nearest-neighbour resampling.
6. Materialize only requested windows or time slices.
7. Convert the result back to terra for existing calculations and output contracts.
8. Preserve source URLs, planned periods, missing periods, L3 codes, and backend/version metadata in the result.

A possible internal API is:

`wapor_gdalcubes_available()`

`wapor_gdalcubes_collection(urls, dates, band, ...)`

`wapor_gdalcubes_cube(plan, extent, crs, resolution, ...)`

`wapor_gdalcubes_reduce_time(cube, rule, ...)`

`wapor_gdalcubes_to_terra(cube, ...)`

These should remain internal until the adapter passes parity tests.

## Required pilot tests before adoption

1. Constant-raster temporal mean and sum parity.
2. Dekad with partial overlap at the season start and end.
3. Leap-year and March-February season boundary behavior.
4. NA, zero, and incomplete-source behavior.
5. L1/L2/L3 resolution and CRS preservation.
6. Bilinear continuous versus nearest-neighbour categorical resampling.
7. Polygon zonal-statistic parity against exactextractr for small, boundary, and sub-pixel polygons.
8. Multiple L3 sources with explicit coverage metadata.
9. Local HTTP COG range fixture for terra and gdalcubes.
10. Failure injection with `incomplete_ok = FALSE`, HTTP retry behavior, and no false-success output.
11. Memory benchmark across at least 256, 1024, and 4096 spatial windows and 3, 12, and 36 temporal layers.
12. COG output validation using GDAL metadata and round-trip reads.

## Decision

Do not replace terra in Rwapor now. The recommended design is a feature-flagged, optional gdalcubes backend for large regular temporal cube workloads. First implement the adapter against synthetic/local HTTP fixtures, then compare it against the existing terra engine at row/cell level. Adoption should require exact temporal and missingness parity, not only similar regional averages.
