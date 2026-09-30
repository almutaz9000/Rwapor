# Plan How a Raster Job Should Be Processed

Estimates the memory a job needs and chooses how to run it:

- `"memory"`: the whole area and every dekad are processed at once.

- `"stream"`: the whole area is processed, reading dekads in batches.

- `"tiled"`: the area is split into square tiles, each streamed
  separately and assembled with a VRT. Tiles run in parallel under the
  active
  [`future::plan()`](https://future.futureverse.org/reference/plan.html).

## Usage

``` r
wapor_plan_processing(
  template = NULL,
  aoi = NULL,
  resolution = NULL,
  n_layers = 36L,
  n_vars = 1L,
  native_resolution = NULL,
  n_targets = NULL,
  n_profiles = 1L,
  workers = NULL,
  processing = c("auto", "memory", "stream", "tiled")
)
```

## Arguments

- template:

  Optional `SpatRaster` defining the analysis grid.

- aoi:

  Optional bounding box `c(xmin, ymin, xmax, ymax)` in degrees, used
  with `resolution` when no template is available.

- resolution:

  Analysis resolution in metres (for example 20, 100 or 300), used with
  `aoi`.

- n_layers:

  Integer. Dekads per variable (36 for one year).

- n_vars:

  Integer. Number of variables read.

- native_resolution:

  Optional numeric vector of each variable's native resolution in
  metres. Defaults to the analysis resolution.

- n_targets:

  Integer. Outputs accumulated per variable (the season plus each
  month). Default `1 + ceiling(n_layers / 3)`.

- n_profiles:

  Integer. Unique season profiles (crop class, start, end).

- workers:

  Integer. Parallel workers. Defaults to
  [`future::nbrOfWorkers()`](https://future.futureverse.org/reference/nbrOfWorkers.html).

- processing:

  One of `"auto"`, `"memory"`, `"stream"`, `"tiled"`.

## Value

An object of class `wapor_plan` with the chosen `mode`, the estimate
(`working_set_bytes`, `budget_bytes`), `batch_size`, `tile_size`,
`gdal_chunk_bytes`, and the `reasons` for the choice.

## Details

Results are identical whichever mode runs; only memory use and speed
differ.

The memory budget is half of the free RAM divided by the number of
workers. Override it with `options(Rwapor.memory_budget_mb = ...)`. Mode
thresholds (fractions of the budget) can be changed with
`options(Rwapor.plan_thresholds = c(memory = 0.25, stream = 1, layer = 0.1))`.

## Examples

``` r
# A 5 km x 5 km farm at 20 m for one year: runs in memory
wapor_plan_processing(aoi = c(35, 33, 35.05, 33.05), resolution = 20, n_layers = 36)
#> <wapor_plan>
#>   mode        : memory
#>   grid        : 277 x 234 cells
#>   layers      : 36 dekad(s), 13 output target(s), 1 season profile(s)
#>   working set : 113.5 MB (budget 6.9 GB, 1 worker(s))
#>   batch size  : 36 dekad(s)
#>   GDAL chunk  : 256.0 KB
#>   reasons     :
#>     - Estimated working set in memory: 113.5 MB (budget 6.9 GB per worker, 1 worker(s)).
#>     - Working set is below 25% of the budget: in memory.

# A 150 km x 150 km scheme at 20 m: tiled
wapor_plan_processing(aoi = c(35, 33, 36.5, 34.5), resolution = 20,
                      n_layers = 36, n_vars = 4)
#> <wapor_plan>
#>   mode        : tiled
#>   grid        : 8,294 x 6,942 cells
#>   layers      : 36 dekad(s), 13 output target(s), 1 season profile(s)
#>   working set : 312.7 GB (budget 6.9 GB, 1 worker(s))
#>   batch size  : 1 dekad(s)
#>   tile size   : 1896 px
#>   GDAL chunk  : 10.0 MB
#>   reasons     :
#>     - Estimated working set in memory: 312.7 GB (budget 6.9 GB per worker, 1 worker(s)).
#>     - Even one layer batch over the whole area exceeds the budget: tiling.
```
