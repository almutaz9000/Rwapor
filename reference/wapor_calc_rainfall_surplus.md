# Rainfall surplus

`rainfall_surplus = P - min(AETI, P)`, equivalently `max(P - AETI, 0)`
when both inputs are non-negative. This is leftover rain after actual ET
in the same period (potential runoff or recharge), not FAO AQUASTAT
IRWR.

## Usage

``` r
wapor_calc_rainfall_surplus(
  aeti,
  precip,
  resample_method = "bilinear",
  provenance = NULL,
  compatibility_mode = c("warn", "strict")
)
```

## Arguments

- aeti:

  SpatRaster or numeric. Actual evapotranspiration (mm).

- precip:

  SpatRaster or numeric. Gross precipitation (mm).

- resample_method:

  Character. Method for resampling `precip` onto the `aeti` grid when
  geometries differ. Default `"bilinear"`.

- provenance:

  Optional named provenance records for `aeti` and `precip`.

- compatibility_mode:

  Missing-metadata policy: `"warn"` or `"strict"`. Known
  incompatibilities always stop the calculation.

## Value

SpatRaster or numeric. Rainfall surplus (mm), on the `aeti` grid.

## Details

Apply on monthly (or dekadal) layers and sum. A seasonal min lets a wet
month offset a later dry month.

When `precip` is a SpatRaster at a different resolution or CRS than
`aeti` (e.g. L1 PCP at ~5 km vs L3 AETI at 20 m), `precip` is resampled
onto the `aeti` grid using bilinear interpolation before the arithmetic.
The stacks must have the same layer count. When dates can be read from
[`terra::time()`](https://rspatial.github.io/terra/reference/time.html)
or layer names, they must match in order; a mismatch stops with an
error. If dates cannot be established for both stacks, a warning is
issued and layers are paired by position. Pass
`resample_method = "near"` to override.

## Examples

``` r
wapor_calc_rainfall_surplus(350, 400)  # 50 mm leftover rain
#> [1] 50
```
