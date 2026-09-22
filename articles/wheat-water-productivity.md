# Worked Example: Wheat Seasonal & Multi-Season Water Productivity

This is an applied, end-to-end case study for a single crop: building a
wheat mask from a crop-type/land-cover raster, defining wheat’s crop
coefficients, and running the full indicator chain — seasonal $`AETI`$,
$`ET_c`$, Water Adequacy, and Crop/Biomass Water Productivity
($`CWP`$/$`BWP`$) — for both a single wheat season and a multi-year
batch of wheat seasons. It builds on the concepts in
[`vignette("advanced-analysis")`](https://almutaz9000.github.io/Rwapor/articles/advanced-analysis.md);
read that first if you haven’t.

------------------------------------------------------------------------

## 1. Build a Wheat-Only Crop Mask

`Rwapor`’s seasonal engine expects a `crop_mask` raster whose pixel
values are class codes matching `class_value` in your crop parameters
table. If you already have a crop-type or land-cover raster (e.g. from a
national crop inventory, ESA WorldCover, or a classified Sentinel-2
mosaic), isolate wheat by keeping only its class code and setting
everything else to `NA`:

``` r

library(Rwapor)
library(terra)

# Any classified crop-type/land-cover raster aligned to your AOI
crop_type <- rast("crop_type_classified.tif")

# Example: wheat is class code 11 in this classification
wheat_mask <- classify(
  crop_type,
  rcl = matrix(c(11, 1), ncol = 2, byrow = TRUE),
  othersNA = TRUE
)
```

`wheat_mask` now has value `1` on wheat pixels and `NA` everywhere else
— exactly what
[`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md)
expects in `rasters$crop_mask`.

If you only have a **field-boundary vector** (e.g. a shapefile of wheat
parcels) rather than a classified raster, rasterize it onto the same
grid as your WaPOR data instead:

``` r

wheat_fields <- vect("wheat_parcels.geojson")
template     <- rast("L2-AETI-D_sample.tif")  # any downloaded WaPOR raster for the grid/CRS

wheat_mask <- rasterize(wheat_fields, template, field = 1, background = NA)
```

------------------------------------------------------------------------

## 2. Define Wheat’s Crop Coefficients

Override the FAO default **Winter Wheat** profile for your local
variety, or build one from scratch with
[`wapor_create_crop_params()`](https://almutaz9000.github.io/Rwapor/reference/wapor_create_crop_params.md)
as shown in
[`vignette("advanced-analysis")`](https://almutaz9000.github.io/Rwapor/articles/advanced-analysis.md):

``` r

wheat_params <- wapor_custom_crop(
  base_crop   = "Winter Wheat",
  class_value = 1L,            # matches the value used in wheat_mask above
  crop_name   = "Irrigated Winter Wheat",
  kc_ini      = 0.35,
  kc_mid      = 1.15,
  kc_end      = 0.30,
  HI          = 0.45,          # Harvest Index
  MC          = 0.13           # Moisture Content
)
```

------------------------------------------------------------------------

## 3. Single-Season Wheat Analysis

A typical winter wheat season runs from sowing in autumn to harvest the
following spring. Set `config$period` to that single season’s start/end
dates and point `rasters$crop_mask` at the wheat mask built in Step 1:

``` r

config <- list(
  period        = c("2023-10-15", "2024-05-31"),  # single-season start/end
  ref_year      = 1970,           # baseline year for internal day-of-year math;
                                   # leave as-is unless you need calendar-year-aligned output
  aeti_var      = "L2-AETI-D",    # or "L1-AETI-D" (~300 m, global) / "L3-AETI-D"
                                   # (~20 m, Level 3 irrigation schemes only) -- see vignette("data-catalog")
  ret_var       = "L1-RET-D",     # RET is only published at Level 1 (~30 km, reanalysis-based)
  precip_var    = "L1-PCP-D",     # PCP is only published at Level 1 (~5 km, gridded precipitation)
  npp_var       = "L2-NPP-D",     # or "L1-NPP-D" (~300 m, global)
  t_var         = "L2-T-D",       # or "L1-T-D" (~300 m, global)
  data_source   = "local",        # or "api" to stream directly from the WaPOR API
                                   # instead of reading files already downloaded into `folder`
  folder        = "wapor_data",   # local directory for data_source = "local";
                                   # ignored when data_source = "api"
  area_weighted = TRUE,           # or FALSE for simple unweighted pixel means; TRUE
                                   # corrects for latitude-dependent pixel-area distortion
                                   # on geographic (EPSG:4326) grids
  indicators    = c(
    "agg_aeti", "agg_t", "etc", "adequacy_etc", "peff", "cwp_bwp", "beneficial_fraction"
    # other available indicator codes (see wapor_list_indicator_steps() for the
    # full, always-current list):
    #   "agg_ret", "agg_pcp", "agg_npp"                 -- raw seasonal aggregates
    #   "adequacy_p95"                                  -- adequacy vs. the 95th
    #                                                       percentile AETI instead of ETc
    #   "green_water", "blue_water"                     -- water-source partitioning
    #   "yield_npp", "agg_biomass_kg", "agg_biomass_t"  -- yield/biomass from NPP
    #   "variability", "cv_aeti", "theil_aeti"          -- spatial uniformity/inequality,
    #                                                       used by wapor_compare_seasons()
  )
)

rasters <- list(crop_mask = wheat_mask)

wheat_season <- wapor_run_seasonal_analysis(
  config      = config,
  crop_params = wheat_params,
  rasters     = rasters
)

# Export seasonal rasters, dekadal stacks, and CSV summaries (incl. CWP/BWP)
wapor_export_analysis_outputs(
  results      = wheat_season,
  folder       = "outputs/Wheat_Winter2023",
  indicators   = config$indicators,
  season_label = "Wheat_Winter2023"
)
```

`wheat_season` includes seasonal $`AETI`$, $`ET_c`$, Water Adequacy,
Beneficial Fraction, and — because `"cwp_bwp"` is in `indicators` — both
**Crop Water Productivity** and **Biomass Water Productivity** rasters
and zonal summaries for the wheat-masked area only.

------------------------------------------------------------------------

## 4. Per-Pixel Season Start/End Masks (Optional)

`config$period` gives every pixel the *same* season window. Real wheat
fields don’t always sow/harvest on the same calendar day — soil type,
irrigation scheduling, or elevation can shift timing by days to weeks
across one AOI. For that, pass **per-pixel** `season_start`/`season_end`
rasters instead: each pixel stores its own start/end day, as a
“continuous Julian day” count from `config$ref_year` (day 1 = Jan 1 of
`ref_year`).

``` r

# Build per-pixel start/end rasters (values are days-from-ref_year, matching
# wapor_continuous_julian()). Here two zones sow 20 days apart -- replace
# with your own field-survey or remote-sensing-derived phenology data.
season_start <- classify(
  wheat_mask,           # any raster on the same grid as wheat_mask
  rcl = matrix(c(1, 288), ncol = 2, byrow = TRUE)  # e.g. Oct 15, ref_year = 2023
)
season_end <- classify(
  wheat_mask,
  rcl = matrix(c(1, 517), ncol = 2, byrow = TRUE)  # e.g. May 31, 2024 (day 517 from 2023-01-01)
)

config$use_season_rasters <- TRUE   # or FALSE (default) to use config$period for every pixel instead

wheat_season_custom_dates <- wapor_run_seasonal_analysis(
  config      = config,
  crop_params = wheat_params,
  rasters     = list(
    crop_mask    = wheat_mask,
    season_start = season_start,
    season_end   = season_end
  )
)
```

I verified this against the package source and a live test run
(`R/analysis_engine.R`): setting `config$use_season_rasters = TRUE` and
providing per-pixel `season_start`/`season_end` measurably changes the
seasonal aggregation window per pixel — a shortened per-pixel season
produces a proportionally smaller seasonal $`AETI`$ than the full
`config$period` window, exactly as expected.

------------------------------------------------------------------------

## 5. Multi-Season Wheat Analysis

To track wheat water productivity across several years, pass a **named
list** of season start/end pairs instead of a single vector — the same
`wheat_mask` and `wheat_params` apply to every season:

``` r

wheat_periods <- list(
  "Wheat_Winter2021" = c("2020-10-15", "2021-05-31"),
  "Wheat_Winter2022" = c("2021-10-15", "2022-05-31"),
  "Wheat_Winter2023" = c("2022-10-15", "2023-05-31")
)

config$period <- wheat_periods

wheat_all_seasons <- wapor_run_seasonal_analysis(
  config      = config,
  crop_params = wheat_params,
  rasters     = rasters
)
```

`wheat_all_seasons` is a named list of per-season results (same
structure as Step 3’s single-season output), ready for year-over-year
comparison with `wapor_compare_seasons()` — see
[`vignette("advanced-analysis")`](https://almutaz9000.github.io/Rwapor/articles/advanced-analysis.md)
for spatial uniformity ($`CV`$, Theil Index) and anomaly-detection
functions that work directly on this multi-season output.

------------------------------------------------------------------------

## 6. A Different Wheat Mask (and Start/End Dates) per Season

The wheat-growing area often changes year to year — crop rotation, newly
irrigated land, or a shrinking/expanding scheme. Rather than reusing one
`wheat_mask` for every season,
[`wapor_run_seasonal_analysis()`](https://almutaz9000.github.io/Rwapor/reference/wapor_run_seasonal_analysis.md)
will automatically look for **season-specific** files: for every season
name in `config$period`, it checks `config$folder/seasonal_masks/` (or
`config$folder` directly) for files named `<SeasonName>_mask.tif`,
`<SeasonName>_start.tif`, and `<SeasonName>_end.tif`, where
`<SeasonName>` matches the list name exactly. A season with a matching
file uses it in place of the shared `rasters` value; a season with no
file falls back to whatever you passed in `rasters` — you don’t need a
file for every season.

``` r

# Directory layout expected by this "Smart-Linking" (season names below
# match the config$period names used in wheat_periods from Step 5):
# wapor_data/
#   L2-AETI-D/ ...                     (downloaded WaPOR rasters, as before)
#   seasonal_masks/
#     Wheat_Winter2021_mask.tif        # wheat extent that actually grew in 2021
#     Wheat_Winter2022_mask.tif        # wheat extent that actually grew in 2022
#     # Wheat_Winter2023: no file here -> falls back to rasters$crop_mask below

wheat_by_season_mask <- wapor_run_seasonal_analysis(
  config      = config,   # config$period already set to wheat_periods (Step 5)
  crop_params = wheat_params,
  # rasters$crop_mask here is only the FALLBACK for seasons without their
  # own *_mask.tif (Wheat_Winter2023 in this example)
  rasters     = list(crop_mask = wheat_mask)
)
```

I verified this “Smart-Linking” behavior directly
(`R/analysis_engine.R`) with a synthetic multi-season test: two seasons
were given non-overlapping masks (one covering the left half of the
grid, one the right half) via this exact `seasonal_masks/` convention,
and each season’s result correctly used only its own mask — a third
season with no season-specific file correctly fell back to the shared
mask passed in `rasters`. The same convention applies to
`<SeasonName>_start.tif`/`<SeasonName>_end.tif`: a season-specific file
overrides `config$use_season_rasters` to `TRUE` for that season alone,
even when the global config default is `FALSE`.

------------------------------------------------------------------------

## 7. Summarize Results

``` r

# Seasonal CWP/BWP zonal summary for a single season
wheat_season$summary_table

# CWP trend across all wheat seasons
sapply(wheat_all_seasons, function(s) s$summary_table$cwp_bwp_mean)
```
