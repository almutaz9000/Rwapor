# Convert Raster Values Between Temporal Units

Converts raster layer values from one temporal unit to another. Each
layer is converted individually based on its date information.

## Usage

``` r
wapor_convert_raster(r, variable, urls, unit_conversion)
```

## Arguments

- r:

  A `SpatRaster` object from the terra package.

- variable:

  Character. Variable name to determine temporal resolution (e.g.,
  "L1-AETI-D" where "D" indicates dekadal data).

- urls:

  Character vector. URLs corresponding to each raster layer, used to
  extract date information for conversion factors.

- unit_conversion:

  Character. Target temporal unit. One of:

  - "none": No conversion (returns input unchanged)

  - "day": Convert to daily rate

  - "dekad": Convert to 10-day total

  - "month": Convert to monthly total

  - "year": Convert to annual total

## Value

The input `SpatRaster` with converted values.

## Details

The function determines the source temporal unit from the variable name:

- "D" suffix -\> dekadal source

- "M" suffix -\> monthly source

- "A" suffix -\> annual source

- "E" suffix -\> daily source

## Examples

``` r
if (FALSE) { # \dontrun{
# Load raster and convert dekadal to monthly
r <- terra::rast(urls)
r_monthly <- wapor_convert_raster(
  r,
  variable = "L1-AETI-D",
  urls = urls,
  unit_conversion = "month"
)
} # }
```
