---
name: geospatial-raster-scaling
description: >
  Procedural patterns for latitude-aware area weighting, reference-layer
  alignment/resampling, and the tiled/windowed raster engine in Rwapor. Use
  when implementing or reviewing anything in R/analysis_tiled.R,
  R/analysis_engine.R, R/analysis_utils.R, or when a raster operation needs to
  scale past what fits comfortably in memory. Primarily used by
  geospatial-engineer and bigdata-engineer.
---

# Geospatial Raster Scaling Patterns

## 1. Latitude-aware pixel area

On an EPSG:4326 (or any geographic, non-equal-area) grid, pixel area in
hectares is **not** constant across rows — it shrinks toward the poles by
`cos(latitude)`. A scalar area derived from one row (e.g. `ymin`) and
multiplied by pixel count biases any area-weighted statistic.

```r
# Pattern (matches wapor_pixel_area_ha() in R/analysis_utils.R)
wapor_pixel_area_ha <- function(x) {
  # x: SpatRaster with known resolution and geographic CRS
  lat <- terra::yFromRow(x, seq_len(terra::nrow(x)))
  res_deg <- terra::res(x)
  # meters per degree latitude is ~constant; meters per degree longitude
  # scales by cos(lat)
  m_per_deg_lat <- 111320
  height_m <- res_deg[2] * m_per_deg_lat
  width_m  <- res_deg[1] * m_per_deg_lat * cos(lat * pi / 180)
  area_ha_by_row <- (height_m * width_m) / 10000
  # broadcast to a full-grid raster of per-pixel area
}
```

**Verification pattern**: build two same-size template grids at different
latitudes (e.g. 30°N and 40°N per `tests/testthat/test-pixel-area.R`'s
existing approach), compute the mean of a *constant* input raster using
your area-weighted function, and confirm the result is identical
regardless of latitude — a latitude-dependent bug will bias only the
weighted mean, not a naive one, so a naive test won't catch it.

## 2. Reference-layer alignment

Never let alignment be implicit ("everything gets warped to whatever grid
happened to load first"). Make the reference layer an explicit parameter:

```r
reference_layer <- c("aeti", "crop_mask", "ret", "pcp", "npp", "template")
resampling_method <- c(aeti = "bilinear", ret = "bilinear", pcp = "bilinear",
                        npp = "bilinear", crop_mask = "near", template = "near")
```

Rule: **categorical rasters (class IDs, crop masks) always resample with
`near`**; bilinear/cubic resampling on categorical data invents
non-existent class values at boundaries, which then silently corrupts
every downstream class-mean and CWP/BWP calculation. Continuous rasters
(AETI, RET, NPP, precipitation) use `bilinear` by default.

Validate extent overlap explicitly before warping — raise an error naming
both extents (region AOI and dataset), not a generic "extents differ".

## 3. Tiled/windowed engine

Goal: process L1-global-scale stacks (~5.6 billion pixels/layer) without
materializing a full `(time, y, x)` SpatRaster in memory.

Two-pass structure (mirrors `IMPROVEMENT_PLAN.md` §1.4):

- **Pass 1** — stream lightweight per-tile summaries needed globally
  before per-tile math can run (e.g. a global per-class median season
  length via a histogram accumulated tile-by-tile).
- **Pass 2** — for each tile window: read the window from each aligned
  input (via `terra::rast(..., vrt = TRUE)` lazy reprojection, or a COG
  `/vsicurl/` windowed read — see the `cog-api-streaming` skill), run the
  *pure-R* indicator math (not terra-wrapped — see `indicators_math.R`'s
  existing pattern) on the tile's plain arrays, write the tile block with
  `terra::writeRaster(..., window = ...)`, and accumulate any running
  class sums/weights online (don't buffer per-tile results in memory for
  a final combine unless the accumulator itself is small).

**Do not assume `terra::rast(vrt = TRUE)` lazy reprojection is
pixel-identical to GDAL's `WarpedVRT`** used by reference implementations
(e.g. waporbox in Python) without checking. Before trusting the tiled
path for anything scientific:

1. Run one tile through both the tiled path and the non-tiled
   (full-materialization) path on the same small input.
2. Diff the two rasters pixel-by-pixel (`terra::diff` or direct array
   comparison), not just visually.
3. If they diverge, the divergence is almost always at tile boundaries or
   in resampling-method mismatches (see §2) — check those first.

Memory verification: peak memory during a tiled run should scale with
`tile_size² × n_layers`, not with the full grid size. A regression here
(tile size no longer bounding memory) is a silent, hard-to-notice
correctness-adjacent bug — add it to
`tests/testthat/test-memory-scaling.R` once that file exists (Improvement
Plan §2.3), and gate on it, don't just eyeball a `bench::mark()` run once.

## 4. GDAL/PROJ environment issues (Windows)

`PROJ_LIB` conflicts (multiple GDAL/PROJ installs on the same Windows
machine, common when both a system GDAL and an R-bundled GDAL exist) are
a recurring real issue for this package — see
`dev-tools/scripts/debug/check_env_windows.R` and
`R/gdal_config.R`'s `wapor_fix_proj()`. When debugging a
reprojection/CRS failure that only reproduces on Windows, check this
before assuming a code bug.
