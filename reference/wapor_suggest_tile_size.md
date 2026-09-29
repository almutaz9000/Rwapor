# Suggest a safe tile size for the tiled seasonal analysis engine

Computes the largest square tile (in pixels) that fits within
`target_ram_mb` of working memory, given the number of raster layers,
variables and parallel workers.
[`wapor_plan_processing()`](https://almutaz9000.github.io/Rwapor/reference/wapor_plan_processing.md)
chooses a tile size automatically; use this helper to pick one by hand
for
[`wapor_run_seasonal_analysis_tiled()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis_tiled.md).

## Usage

``` r
wapor_suggest_tile_size(
  n_layers,
  n_workers = 1L,
  bytes_per_val = 8L,
  target_ram_mb = 4096,
  min_tile = 64L,
  max_tile = 4096L,
  n_vars = 1L,
  overhead = 2.5
)
```

## Arguments

- n_layers:

  Integer. Number of raster layers to hold in memory at once (e.g. total
  dekadal layers in the season).

- n_workers:

  Integer. Number of parallel tile workers. Each worker holds one tile
  in RAM simultaneously. Default `1L`.

- bytes_per_val:

  Integer. Bytes per cell in memory. terra holds values as 8-byte
  doubles, so the default is `8L`.

- target_ram_mb:

  Numeric. RAM budget in megabytes. Default `4096` (4 GB).

- min_tile:

  Integer. Minimum tile size to return. Default `64L`.

- max_tile:

  Integer. Maximum tile size to return. Default `4096L`.

- n_vars:

  Integer. Number of variables read per tile. Default `1L`.

- overhead:

  Numeric. Multiplier for temporaries. Default `2.5`.

## Value

A single integer: recommended tile side length in pixels.

## Details

Formula: bytes_per_tile = tile_size^2 \* n_layers \* n_vars \*
bytes_per_val \* overhead total_bytes = bytes_per_tile \* n_workers

The result is clamped to \[min_tile, max_tile\] so extreme inputs
produce a usable value rather than an error.

## Examples

``` r
# 36 dekadal layers, 2 workers, 8 GB RAM budget
wapor_suggest_tile_size(n_layers = 36L, n_workers = 2L, target_ram_mb = 8192)
#> wapor_suggest_tile_size: 2442 px (n_layers=36, n_vars=1, n_workers=2, budget=8192 MB, 4094.7 MB/tile)
#> [1] 2442
```
