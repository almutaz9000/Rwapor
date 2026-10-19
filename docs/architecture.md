# Rwapor Architecture & Indicator Specification

## Overview

`Rwapor` provides programmatic and interactive access to FAO WaPOR (v1, v2, v3) and AgERA5 data, seasonal crop water productivity analysis, and zonal extraction.

## Canonical Indicator Specification (`inst/spec/indicators.yaml`)

The single canonical machine-readable specification for all seasonal and biophysical indicators in `Rwapor` (and cross-validated with `waporbox`) lives at:

- [`inst/spec/indicators.yaml`](../inst/spec/indicators.yaml)

Every built-in indicator step registered in `R/analysis_registry.R` (`.wapor_builtin_indicator_steps()` and `wapor_list_indicator_steps()`) is documented in `inst/spec/indicators.yaml` with:

- `id`: Canonical indicator identifier (matching `wapor_list_indicator_steps()` and `.wapor_builtin_indicator_steps()`)
- `label` & `category`: Human-readable label and grouping (`evapotranspiration`, `water_balance`, `adequacy`, `biomass`, `water_productivity`, `uniformity`)
- `formula`: Exact mathematical definition
- `units_in` & `units_out`: Input and physical output units (`mm/day`, `mm/season`, `kg/ha`, `t/ha`, `kg/m3`, `1`)
- `dekad_rule`: Dekadal duration weighting (`multiply_by_dekad_days_once`) vs monthly/seasonal aggregation rules
- `inputs`: Upstream WaPOR variables and intermediate steps required
- `citation`: FAO WaPOR / FAO-56 / Molden (1997) citation
- `r_function` & `py_function`: Corresponding R (`Rwapor`) and Python (`waporbox`) entry points
- `status`: Implementation status (`implemented`)

Synchronization between `inst/spec/indicators.yaml` and `wapor_list_indicator_steps()` / `.wapor_builtin_indicator_steps()` is enforced in `tests/testthat/test-indicator-spec.R`.

## Processing Engines (`memory`, `stream`, `tiled`)

Seasonal analysis (`wapor_run_seasonal_analysis()`) dispatches through a shared window kernel (`R/processing_kernel.R`) across three execution modes:

1. `memory`: Loads aligned dekadal stacks in memory for small AOIs.
2. `stream`: Streams dekadal rasters layer-by-layer with disk-backed intermediate rasters.
3. `tiled`: Splits the AOI into spatial tiles (`wapor_tile_grid()`), runs the per-window kernel per tile with a resumable `manifest.json` (`config_hash` includes `indicators`), stitches seasonal rasters, and computes post-tile indicators (including exact out-of-core global class percentiles via `.wapor_zonal_quantile_exact()` for `adequacy_p95` and global spatial variability `cv_aeti` / `theil_aeti`).
