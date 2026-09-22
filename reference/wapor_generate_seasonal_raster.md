# Generate seasonal aggregate raster from DuckDB dekadal blobs

Generate seasonal aggregate raster from DuckDB dekadal blobs

## Usage

``` r
wapor_generate_seasonal_raster(
  con,
  farm_id,
  farm_geom,
  variable,
  start_date,
  end_date
)
```

## Arguments

- con:

  DuckDB connection

- farm_id:

  Farm identifier

- farm_geom:

  sf object for the farm

- variable:

  WaPOR variable

- start_date:

  Seasonal start date

- end_date:

  Seasonal end date

## Value

terra SpatRaster aggregate or NULL
