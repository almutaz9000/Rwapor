# Climate normalisation factor f_norm = mean(RET) / RET

The mean is area-weighted over the masked area by default. Chukalla also
weights by field size and growing length; season-length weighting is the
caller's choice via per-season inputs.

## Usage

``` r
wapor_calc_climate_norm(
  ret,
  zones = NULL,
  id = NULL,
  weights = c("area", "none"),
  mask = NULL
)
```

## Source

Chukalla et al. (2022) Eq. 3.

## Arguments

- ret:

  SpatRaster of reference evapotranspiration.

- zones, id:

  Unused in pixel mode; reserved for a zonal mean.

- weights:

  `"area"` (default) or `"none"`.

- mask:

  Optional mask (NA outside).

## Value

A SpatRaster of f_norm.
