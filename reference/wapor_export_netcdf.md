# Export Downloaded WaPOR Rasters as a NetCDF Cube

Reads per-date GeoTIFF files from a
[`wapor_download()`](https://almutaz9000.github.io/Rwapor/reference/wapor_download.md)
cache folder, stacks them in time order, and writes a single
CF-compliant NetCDF-4 file. The GeoTIFF cache is preserved unchanged;
this is an *additional* export for interchange with Python (xarray, CDO,
Panoply) or other climate tools.

## Usage

``` r
wapor_export_netcdf(
  folder,
  variable,
  period = NULL,
  output_dir = NULL,
  filename = NULL,
  overwrite = FALSE,
  compression = 4L,
  varname = NULL,
  longname = NULL,
  unit = NULL,
  add_time_bounds = TRUE
)
```

## Arguments

- folder:

  Character. Root download folder (same as the first argument of
  [`wapor_download()`](https://almutaz9000.github.io/Rwapor/reference/wapor_download.md)).

- variable:

  Character. Variable code (e.g. `"L1-AETI-D"`).

- period:

  Optional `c(start, end)` in `"YYYY-MM-DD"` to restrict the layers
  included. Default `NULL` uses all files found in the folder.

- output_dir:

  Optional override for the destination directory. Default is
  `<folder>/netcdf/<variable>/`.

- filename:

  Optional filename. Default is
  `<variable>.<first_date>_<last_date>.nc`.

- overwrite:

  Logical. Replace an existing file. Default `FALSE`.

- compression:

  Integer 1-9, or `NA` for no compression. Default `4`.

- varname:

  Character. NetCDF variable name. Default is the WaPOR variable code
  with hyphens replaced by underscores.

- longname:

  Character. Human-readable description written as the NetCDF
  `long_name` attribute. Default is derived from WaPOR metadata when
  available, otherwise the variable code.

- unit:

  Character. Physical unit string. Default is read from the first
  GeoTIFF's stored unit; pass explicitly to override.

- add_time_bounds:

  Logical. Write a CF `time_bnds` auxiliary coordinate variable encoding
  each dekad's start and end date. Default `TRUE`. This preserves the
  8-11 day last-dekad duration that is lost when only the start date is
  recorded.

## Value

Character. Path to the written `.nc` file, invisibly.

## Details

The output layout is:
`<folder>/netcdf/<variable>/<variable>.<start>_<end>.nc`

Existing files are overwritten only when `overwrite = TRUE`. Writes are
atomic: the file is written to a `.partial.nc` sibling and renamed on
success.

The function requires the ncdf4 package (a Suggests dependency of
terra). An informative error is raised when it is absent.

Values are written in `"float"` precision (32-bit), consistent with the
`FLT4S` GeoTIFFs written by
[`wapor_download()`](https://almutaz9000.github.io/Rwapor/reference/wapor_download.md).
Missing values are stored as `1e30` (the NetCDF default for float).

Time is encoded as days since the Unix epoch (`1970-01-01`) with
`calendar = "standard"`. When `add_time_bounds = TRUE` a `time_bnds`
variable with shape `(2, ntime)` records the start and end of every
dekad.

CF attributes written: `Conventions = "CF-1.6"`, `institution`,
`source = "FAO WaPOR v3"`, `created_by`, `created_date`.

## See also

[`wapor_download()`](https://almutaz9000.github.io/Rwapor/reference/wapor_download.md),
[`wapor_local_rasters()`](https://almutaz9000.github.io/Rwapor/reference/wapor_local_rasters.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# After downloading:
wapor_download("L1-AETI-D", region = my_aoi, period = c("2024-01-01","2024-12-31"),
               folder = "wapor_data")
nc <- wapor_export_netcdf("wapor_data", "L1-AETI-D")
# Open in Python: xr.open_dataset(nc)
} # }
```
