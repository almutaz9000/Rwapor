# Suggest a safe tile size for the tiled seasonal analysis engine

Computes the largest square tile (in pixels) that fits within
`target_ram_mb` of working memory, given the number of raster layers and
parallel workers. Use the returned value as the `tile_size` argument of
[`wapor_run_seasonal_analysis_tiled()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis_tiled.md).

## Usage

``` r
wapor_suggest_tile_size(
  n_layers,
  n_workers = 1L,
  bytes_per_val = 4L,
  target_ram_mb = 4096,
  min_tile = 64L,
  max_tile = 4096L
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

  Integer. Bytes per raster cell. Float32 COGs = 4. Default `4L`.

- target_ram_mb:

  Numeric. RAM budget in megabytes. Default `4096` (4 GB).

- min_tile:

  Integer. Minimum tile size to return. Default `64L`.

- max_tile:

  Integer. Maximum tile size to return. Default `4096L`.

## Value

A single integer: recommended tile side length in pixels.

## Details

Formula: bytes_per_tile = tile_size^2 \* n_layers \* bytes_per_val
total_bytes = bytes_per_tile \* n_workers max_tile_size =
floor(sqrt(target_ram_mb \* 1024^2 / (n_layers \* bytes_per_val \*
n_workers)))

The result is clamped to \[min_tile, max_tile\] so extreme inputs
produce a usable value rather than an error.

## Examples

``` r
# 36 dekadal layers, 2 workers, 8 GB RAM budget
wapor_suggest_tile_size(n_layers = 36L, n_workers = 2L, target_ram_mb = 8192)
#> wapor_suggest_tile_size: 4096 px (n_layers=36, n_workers=2, budget=8192 MB, 2304.0 MB/tile)
#> [1] 4096
```
