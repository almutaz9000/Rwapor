# Check for Local Raster Files

Given a set of WaPOR URLs and a local folder, checks which files exist
locally following the standard naming convention.

## Usage

``` r
wapor_check_local(urls, var, folder)
```

## Arguments

- urls:

  Character vector of WaPOR URLs.

- var:

  Character. WaPOR variable code (e.g., "L1-AETI-D").

- folder:

  Character. Path to the local analysis folder.

## Value

A list with components:

- optimized_paths:

  Character vector of paths to use in rast() (local paths or /vsicurl/
  URLs).

- missing_dates:

  Character vector of dates (YYYY-MM-DD) for missing dekads.

- found_count:

  Integer. Number of dekads found locally.
