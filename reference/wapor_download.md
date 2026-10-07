# Download WaPOR Rasters Once for Local or Offline Analysis

Saves one GeoTIFF per time step for an area, in the layout
[`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md)
reads with `data_source = "local"`:
`<folder>/<variable>/<provider>.<variable>.<date>.tif`. Files that are
already there are not downloaded again, so the call can be repeated to
complete or extend a period, and it works without internet once the
files exist.

## Usage

``` r
wapor_download(
  variable,
  region,
  period,
  folder,
  l3_region = NULL,
  mask = FALSE,
  overwrite = FALSE
)
```

## Arguments

- variable:

  Character vector of variable codes (for example
  `c("L3-AETI-D", "L1-RET-D")`).

- region:

  Area to download: a vector file path, an `sf` object, a bounding box
  `c(xmin, ymin, xmax, ymax)` in WGS84, or an L3 region code.

- period:

  `c(start_date, end_date)` in `"YYYY-MM-DD"` format.

- folder:

  Folder that holds one sub-folder per variable. Created if needed.

- l3_region:

  Optional L3 region code for Level 3 variables.

- mask:

  Logical. `FALSE` (default) keeps every pixel of the bounding box of
  `region`. `TRUE` sets pixels outside a polygon region to `NA`; do not
  use it for coarse Level 1 variables, where one pixel covers many
  fields.

- overwrite:

  Logical. Download the files of `period` again and replace them (for
  the same area). Default `FALSE`.

## Value

Invisibly, the paths of the files for the period: a character vector for
one variable, a named list for several. Each vector carries an attribute
`"wapor_status"` with the number of files downloaded, already present,
and whether the server was reachable.

## Details

Since version 1.0.6 streaming from the server is about as fast as
reading local files, so this is for work without a connection (field
work, training rooms) and for analyses that are repeated many times on
the same area.

Values are stored in the unit of the source (for example mm/day for
dekadal evapotranspiration): the scale factor of the WaPOR files is
applied exactly once and no temporal conversion is made, which is what
the seasonal analysis expects from local files. AgERA5 temperatures are
converted to degrees Celsius.

Each file is written under a temporary name and renamed when complete,
so an interrupted download never leaves a partial file that a later call
would skip.

A folder belongs to one area. The first download writes the area into
`<folder>/<variable>/.wapor_download.json`; a later call for an area
that is not inside it (or with a different `mask`) stops instead of
mixing extents, also with `overwrite = TRUE`. Use another folder for
another area.

Without a connection the function returns the files already saved for
the period and warns that it could not check whether the period is
complete. It stops when there are none.

## See also

[`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md)
(`config$cache_dir` calls this function for the variables an analysis
needs),
[`wapor_map()`](https://almutaz9000.github.io/Rwapor/reference/wapor_map.md).

## Examples

``` r
if (FALSE) { # \dontrun{
files <- wapor_download(
  variable = c("L3-AETI-D", "L1-RET-D"),
  region   = "citrus_fields.geojson",
  period   = c("2024-03-01", "2025-02-28"),
  folder   = "wapor_data",
  l3_region = "JVA"
)
attr(files[["L3-AETI-D"]], "wapor_status")
} # }
```
