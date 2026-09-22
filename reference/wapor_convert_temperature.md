# Convert Temperature Raster from Kelvin to Celsius

Converts AgERA5 temperature rasters from Kelvin to degrees Celsius by
subtracting 273.15. This function is automatically applied to TMIN and
TMAX variables during download.

## Usage

``` r
wapor_convert_temperature(r, variable)
```

## Arguments

- r:

  A `SpatRaster` object from the terra package.

- variable:

  Character. Variable name to verify it's a temperature variable.

## Value

The input `SpatRaster` with values converted to Celsius, or the original
raster unchanged if not a temperature variable.

## Details

The conversion formula is: °C = K - 273.15

This conversion is automatically applied during download for:

- AGERA5-TMIN-E (Minimum Air Temperature)

- AGERA5-TMAX-E (Maximum Air Temperature)

## Examples

``` r
if (FALSE) { # \dontrun{
# Load temperature raster in Kelvin
r <- terra::rast("AGERA5-TMIN-E_2023-01-01.tif")

# Convert to Celsius
r_celsius <- wapor_convert_temperature(r, "AGERA5-TMIN-E")
} # }
```
