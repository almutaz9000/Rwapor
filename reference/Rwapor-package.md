# Rwapor: Download WaPOR and AgERA5 Data

Downloads and processes WaPOR (Water Productivity Open-access portal)
and AgERA5 raster data from the FAO GIS Manager API. Provides functions
for extracting time series, calculating zonal statistics for regions and
polygons, downloading raster maps, unit conversion, and seasonal crop
water productivity analysis. Supports WaPOR Level 1, Level 2, Level 3
data products and AgERA5 climate variables. Includes an interactive
Shiny dashboard for data exploration and analysis with crop mask
integration and seasonal indicator computation.

## Options

- `Rwapor.verbose`:

  Print progress messages (default `TRUE`). Warnings are always shown.

- `Rwapor.disk_check`:

  Check free disk space before file-backed processing (default `TRUE`).

- `Rwapor.memory_budget_mb`:

  Memory budget in MB for processing; by default half of available
  memory is used.

- `Rwapor.cache_ttl`:

  URL metadata cache lifetime in seconds (default `86400`).

- `Rwapor.remote_fallback`:

  Remote-read fallback mode (default `"stream"`; use `"download"` for
  the local cache).

- `Rwapor.configure_gdal`:

  Configure GDAL on package load when needed (default `TRUE`).

- `Rwapor.max_season_profiles`:

  Maximum number of per-pixel season profiles (default `64`).

- `Rwapor.plan_thresholds`:

  Optional named processing-mode thresholds; defaults are calculated
  from the memory budget.

- `Rwapor.remote_cache_dir`:

  Directory for cached remote rasters; by default the R user cache
  directory is used.

## See also

Useful links:

- <https://github.com/almutaz9000/Rwapor>

- Report bugs at <https://github.com/almutaz9000/Rwapor/issues>

## Author

**Maintainer**: Almutaz Mohammed <almutaz.mohammed@fao.org>

Authors:

- WaPOR-DL Contributors <wapor@fao.org>

Other contributors:

- FAO \[copyright holder\]
