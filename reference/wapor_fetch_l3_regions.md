# Fetch WaPOR Level 3 Regions

Dynamically retrieves the list of available WaPOR Level 3 (L3) regions
from the FAO GISMGR API. This ensures that newly added irrigation
schemes or study areas are available without updating the package.

## Usage

``` r
wapor_fetch_l3_regions(timeout = 60, retry = TRUE)
```

## Arguments

- timeout:

  Numeric. Request timeout in seconds. Default `60`.

- retry:

  Logical. If `TRUE` (default), transient failures are retried with
  exponential backoff (up to about 30 seconds in total). Set `FALSE` to
  fall back to the static list after a single failed request.

## Value

A data.frame with columns:

- code:

  3-letter region code (e.g., "AWA")

- name:

  Full name of the region (e.g., "Awash")

- country:

  Country name extracted from the API caption

- caption:

  Original full caption from the API

## Details

Queries the `L3-GRID/tiles` endpoint. If the API request fails, it falls
back to the static `L3_REGIONS` list. Successful responses are cached on
disk for the time set by `options(Rwapor.cache_ttl)` (default 24 hours).
