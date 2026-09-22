# Per-pixel area in hectares

For geographic (lon/lat) grids, area varies with latitude: a 2-D raster
is returned with one value per cell. For projected grids a constant cell
area is used. Matches the waporbox `pixel_area_ha` convention
(`111320 m/deg * cos(lat)`).

## Usage

``` r
wapor_pixel_area_ha(x)
```

## Arguments

- x:

  SpatRaster. Template whose geometry defines the area raster.

## Value

A SpatRaster of per-pixel area in hectares.
