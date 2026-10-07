# Compute P95 of AETI Within Crop Class

Extracts the 95th percentile of seasonal AETI for each crop class. In
remote-sensing water accounting, the 95th percentile of AETI across
homogeneous agro-ecological zones or crop classes serves as an empirical
estimate of target (non-water-limited) crop evapotranspiration (ETx),
filtering out localized extreme outliers.

## Usage

``` r
wapor_calc_p95_aeti(aeti_seasonal, crop_mask, min_pixels = 30L)
```

## Arguments

- aeti_seasonal:

  SpatRaster. Seasonal AETI raster.

- crop_mask:

  SpatRaster. Crop mask with integer class values.

- min_pixels:

  Integer. Minimum pixel count to compute P95. Classes with fewer pixels
  return NA. Default 30.

## Value

A data.frame with columns: class_value, p95_aeti, n_pixels, valid.

## References

Bastiaanssen, W. G., & Bos, M. G. (1999). Irrigation performance
indicators based on satellite remote sensing. Irrigation and Drainage
Systems, 13(1), 3-36.

de Bie, C. A., Khan, M. R., Smaling, E. M., Hirosawa, K., & Knox, J. W.
(2011). Analysis of the variation in water productivity for irrigated
wheat in Egypt. Agricultural Water Management, 102(1), 58-69.
