# Generate Seasonal Timing Rasters from Vector and CSV

Creates "Start of Season" and "End of Season" rasters by rasterizing
polygon-specific dates onto a reference template. Polygons are grouped
by season name. This is useful for regions with heterogeneous planting
dates across different districts or farm plots.

## Usage

``` r
wapor_vector_to_season_rasters(
  vector_path,
  csv_path,
  template_r,
  vector_id_col = "id",
  csv_id_col = "id",
  season_col = "season_name",
  start_col = "start_date",
  end_col = "end_date",
  crop_col = NULL,
  ref_year = 1970,
  output_folder = "seasonal_masks"
)
```

## Arguments

- vector_path:

  Character. Path to vector file (e.g., .geojson, .shp).

- csv_path:

  Character. Path to CSV file with dates.

- template_r:

  SpatRaster. Template for extent, resolution, and CRS.

- vector_id_col:

  Character. Name of the polygon ID column in the vector layer.

- csv_id_col:

  Character. Name of the matching ID column in the CSV table.

- season_col:

  Character. Column name for the season identifier.

- start_col:

  Character. Column name for the start dates (YYYY-MM-DD).

- end_col:

  Character. Column name for the end dates (YYYY-MM-DD).

- crop_col:

  Character. Optional column name for crop class labels.

- ref_year:

  Integer. Reference year for Julian day calculation.

- output_folder:

  Character. Where to save the generated rasters.

## Value

A data.frame mapping season names to their generated raster paths.
