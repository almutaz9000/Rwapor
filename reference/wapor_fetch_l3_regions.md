# Fetch WaPOR Level 3 Regions

Dynamically retrieves the list of available WaPOR Level 3 (L3) regions
from the FAO GISMGR API. This ensures that newly added irrigation
schemes or study areas are available without updating the package.

## Usage

``` r
wapor_fetch_l3_regions()
```

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
back to the static `L3_REGIONS` list. Results are memoized.
