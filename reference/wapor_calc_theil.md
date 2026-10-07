# Spatial Theil T inequality index

Computes Theil's T index of spatial inequality / uniformity: \$\$T =
\frac{1}{N} \sum\_{i=1}^N \frac{x_i}{\bar{x}}
\ln\left(\frac{x_i}{\bar{x}}\right)\$\$ for positive finite values.
Computed from block-wise sums so large rasters are not read into R. The
area-weighted form used by
[`wapor_zonal_stats()`](https://almutaz9000.github.io/Rwapor/reference/wapor_zonal_stats.md)
is \\\sum w (x/\mu) \ln(x/\mu) / \sum w\\.

## Usage

``` r
wapor_calc_theil(r, crop_mask = NULL)
```

## Arguments

- r:

  SpatRaster.

- crop_mask:

  Optional SpatRaster mask / class raster.

## Value

List with `overall` Theil T and optional `by_class` table.

## References

Theil, H. (1967). Economics and Information Theory. North-Holland
Publishing Company, Amsterdam.

Sampath, R. K. (1988). Equity measures for irrigation performance
evaluation. Water International, 13(1), 25-32.

## Examples

``` r
if (FALSE) { # \dontrun{
wapor_calc_theil(aeti, crop_mask)
} # }
```
