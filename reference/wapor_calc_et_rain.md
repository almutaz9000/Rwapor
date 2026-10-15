# ET from rainfall

`ET_rain = min(AETI, P)`: the portion of actual evapotranspiration that
cannot exceed gross precipitation in the same period. This is the
green-water split with precipitation instead of USDA-SCS Peff.

## Usage

``` r
wapor_calc_et_rain(
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
  geometries differ. Default `"bilinear"` (appropriate for the
  continuous PCP flux). Use `"near"` only for pre-classified rasters.

- provenance:

  Optional named provenance records for `aeti` and `precip`.

- compatibility_mode:

  Missing-metadata policy: `"warn"` or `"strict"`. Known
  incompatibilities always stop the calculation.

## Value

SpatRaster or numeric. ET from rainfall (mm), on the `aeti` grid.

## Details

When `precip` is a SpatRaster at a different resolution or CRS than
`aeti` (e.g. L1 PCP at ~5 km vs L3 AETI at 20 m), `precip` is resampled
onto the `aeti` grid using bilinear interpolation before the comparison.
The stacks must have the same layer count. When dates can be read from
[`terra::time()`](https://rspatial.github.io/terra/reference/time.html)
or layer names, they must match in order; a mismatch stops with an
error. If dates cannot be established for both stacks, a warning is
issued and layers are paired by position. Pass
`resample_method = "near"` to override.

## Examples

``` r
wapor_calc_et_rain(350, 400)  # 350 mm AETI, 400 mm P -> 350 mm
#> [1] 350
```
