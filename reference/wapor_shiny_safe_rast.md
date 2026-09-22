# Lazy raster guard for Shiny

Checks that a SpatRaster stored in a reactiveVal still has valid layers
(temp-file pointers can go stale between upload and use).

## Usage

``` r
wapor_shiny_safe_rast(
  rv,
  label = "raster",
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- rv:

  A reactiveVal containing a SpatRaster.

- label:

  Character. Label for the notification.

- session:

  Shiny session object for notifications.

## Value

The SpatRaster if valid, otherwise NULL.
