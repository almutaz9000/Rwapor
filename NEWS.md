# Rwapor 0.1.0

## Initial Release

This is the first release of Rwapor, an R package for downloading and processing
WaPOR and AgERA5 data from the FAO GIS Manager API.
### New Features

* `wapor_map()`: Download and save raster maps for specified regions and time periods. Now supports optional batching and parallel chunk processing.
* `wapor_ts()`: Extract time series with zonal statistics for polygons. Now supports parallel batching and custom polygon identifiers.
* `run_dashboard()`: Launch an interactive Shiny application for data selection and visualization.
* `wapor_fix_proj()`: Automatically resolve `PROJ_LIB` environment variable conflicts on Windows.
* `wapor_generate_urls()`: Generate download URLs for WaPOR/AgERA5 resources (memoized).
* `parse_region()`: Parse region inputs (bounding box, vector file, or L3 code).
* `get_date_info()`: Extract date information from WaPOR URL filenames.
* `df_unit_convertor()`: Convert DataFrame values between temporal units.
* `raster_unit_convertor()`: Convert raster values between temporal units.
* `get_variable_metadata()`: Retrieve variable metadata with memoization.

### Data Support

* WaPOR Level 1 (L1) variables: AETI, E, I, NPP, PCP, GBWP, NBWP
* WaPOR Level 2 (L2) variables: AETI, E, I, NPP, T, GBWP, NBWP
* WaPOR Level 3 (L3) regional data support
* AgERA5 climate variables: ET0, TMIN, TMAX, SRF, WS, PF

### Temporal Resolutions

* Daily (E)
* Dekadal (D) - 10-day periods
* Monthly (M)
* Annual (A)

### Infrastructure

* Parallel download support via `furrr` package
* Progress reporting via `progressr` package
* API response caching via `memoise` package
* Unit conversion between day/dekad/month/year
