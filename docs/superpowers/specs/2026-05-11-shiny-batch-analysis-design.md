# Shiny Batch Analysis And Script Generation Design

_Date: 2026-05-11_
_Project: Rwapor_
_Status: Draft approved in chat; written for repo review_

## Goal

Keep the current Shiny analysis workflow, but make batch mode a first-class path from configuration through validation, execution, and script generation.

The result should be:

- stable multi-season analysis when using local downloaded rasters
- no Shiny session disconnect caused by batch-mode server logic
- reproducible R script output that matches the current user configuration for both single-season and multi-season runs

## Problem

The current analysis dashboard supports batch mode in the UI, but the underlying server flow is still largely built around a single `period`.

This creates three user-visible failures:

- multi-season analysis with local rasters can break the Shiny session because parts of the server logic still assume a single period
- validation, local data checks, and run configuration are assembled through different code paths and can drift
- the R code preview is not a reliable export of the current analysis configuration, especially for batch mode

The user expectation is straightforward: configure the analysis once in the dashboard, run it, and keep a reusable script that reproduces the same setup later without reopening Shiny.

## Decision Summary

Adopt one canonical Shiny-side analysis configuration builder and make every downstream path consume it:

- input validation
- missing-data diagnostics
- analysis execution
- code preview
- script export

Batch mode remains in the existing UI. The implementation does not redesign the dashboard. It upgrades the current behavior so batch mode is treated as a normal supported mode instead of a partial overlay on top of single-season logic.

## Scope

In scope:

- single-season and multi-season analysis configuration assembly
- local-raster batch validation and execution stability
- generated script preview and download/export behavior
- regression tests for batch configuration and script output

Out of scope:

- redesigning the Shiny layout
- changing the core seasonal analysis engine behavior unless required for correctness
- new analysis features beyond fixing batch-mode stability and reproducibility
- large-scale Shiny module decomposition

## User Outcomes

### Single Season

When the user configures one season:

- validation uses that exact configuration
- run uses that exact configuration
- script preview shows a standalone single-season script matching the current settings
- script export saves the same script to an `.R` file

### Multiple Seasons

When the user enables batch mode and provides multiple seasons:

- the batch list is parsed into a named list of periods once
- validation checks every configured season instead of falling back to a single-period assumption
- local data coverage diagnostics report missing variables and dates in a season-aware way
- run passes the named season list into `wapor_run_seasonal_analysis()`
- script preview shows a standalone multi-season script matching the configured batch analysis
- script export saves that script for reuse outside Shiny

## Current Root Causes

### 1. Split Config Assembly

The analysis module currently rebuilds configuration separately for:

- validate
- run
- code preview

This makes it easy for batch-mode fields to be included in one path and missed in another.

### 2. Single-Period Assumptions In Batch Mode

The server code creates `periods` for batch mode, but later logic still uses `period` in local coverage checks, L3 resolution, messages, and cache key generation.

That mismatch is a likely source of the Shiny disconnect during multi-season local analysis.

### 3. Script Preview Drift

The current code preview is split between:

- a dedicated script generator
- a generic `renderText()` fallback block

The preview therefore does not consistently reflect the actual run configuration, especially for batch mode and local-file workflows.

## Design

### 1. Canonical Config Builder

Add a focused helper that converts current UI state into a normalized analysis configuration object.

Suggested responsibilities:

- parse single-season or batch-season inputs
- return `config$period` in the shape expected by the engine:
  - single season: `c(start, end)`
  - batch mode: named list of `c(start, end)`
- collect indicators from aggregate and derived selections
- include all data-source and variable selections
- carry `use_crop_mask`, `use_season_rasters`, `ref_year`, `folder`, and `l3_code`
- return validation-friendly metadata such as parsed batch labels

Suggested output shape:

```r
list(
  config = list(
    period = list(
      Winter2018 = c("2018-10-01", "2019-05-31"),
      Winter2019 = c("2019-10-01", "2020-05-31")
    ),
    ref_year = NULL,
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    precip_var = "L1-PCP-D",
    npp_var = "L1-NPP-D",
    t_var = "",
    data_source = "local",
    l3_code = NULL,
    folder = "C:/data/wapor_project",
    indicators = c("agg_aeti", "etc", "adequacy_etc"),
    use_crop_mask = TRUE,
    use_season_rasters = TRUE,
    incremental = FALSE
  ),
  batch_mode = TRUE,
  season_labels = c("Winter2018", "Winter2019"),
  season_table = data.frame(
    label = c("Winter2018", "Winter2019"),
    start = c("2018-10-01", "2019-10-01"),
    end = c("2019-05-31", "2020-05-31")
  )
)
```

This helper becomes the only source for downstream configuration.

### 2. Batch List Parsing

Extract batch parsing into its own helper so the logic is testable outside the Shiny event handlers.

Expected format:

```text
Label, YYYY-MM-DD, YYYY-MM-DD
```

Rules:

- blank lines are ignored
- labels are required and must be unique after trimming
- dates must parse cleanly
- end date must not be earlier than start date
- invalid lines fail validation with a line-specific error message

This helper should return both:

- a named list for engine execution
- a tabular representation for diagnostics and script generation

### 3. Validation Flow

Validation should call the canonical config builder first, then run shared checks.

### Single Season

Reuse existing preflight behavior.

### Batch Mode

Validation should:

- validate the batch list itself
- validate required indicators and crop parameters once
- validate local data coverage per season when `data_source == "local"`
- aggregate warnings/errors into a readable season-aware summary

For local batch coverage, the implementation should avoid assuming one global `period`. Instead it should iterate over the parsed seasons and check required variables season by season.

This can be done either by:

- extending `wapor_preflight_check()` to accept multi-period configs, or
- keeping batch-specific orchestration in Shiny and calling lower-level validation helpers per season

Recommendation:

- keep the engine API stable
- add lightweight shared helpers where needed
- let the Shiny module orchestrate batch validation summaries

### 4. Run Path Stability

The run button should use the same canonical config object used by validation.

Key corrections:

- remove stale single-period references from batch-mode local checks
- ensure L3-region resolution uses the correct current period context
- build batch-aware missing-data messages instead of interpolating one `period`
- make cache-key creation resilient when batch mode is active
- pass the normalized `config` directly into `wapor_run_seasonal_analysis()`

The existing engine already supports named multi-period input and season-specific mask auto-linking. That behavior should be preserved.

### 5. Script Generation

Script generation must be based on the same canonical config consumed by validation and run.

### Single Season Script

The script should:

- define one `period`
- load local or API data according to the configured source
- reflect the selected variables and indicators
- include crop parameters
- include crop-mask and season-raster loading placeholders or configured usage paths as appropriate
- run `wapor_run_seasonal_analysis()` once

### Batch Script

The script should:

- define a named `periods` list
- assign `config$period <- periods`
- preserve local or API data-source logic
- include the same selected indicators and crop parameters
- call `wapor_run_seasonal_analysis()` once for the full batch
- show how to save multi-season outputs

### Preview And Export

Replace the split preview implementation with one source:

- `wapor_generate_shiny_script()` returns the script string
- the Ace editor displays that string
- a new download/export handler writes the same string to an `.R` file

This removes preview drift and ensures what the user sees is what gets exported.

### 6. UI Behavior

The current Shiny workflow stays intact.

Recommended small behavior improvements:

- keep the existing toggleable code preview
- populate the preview after successful validation
- refresh the preview again after a successful run
- add an explicit `Download R Script` button in the reproducibility/export card

No layout redesign is required.

### 7. Files Likely To Change

Primary:

- `inst/shiny/mod_analysis.R`
- `inst/shiny/mod_analysis_ui_body.R`
- `R/analysis_utils.R`

Possible shared validation support:

- `R/analysis_validation.R`

Tests:

- `tests/testthat/test-analysis.R`
- a new focused test file if the new parsing/generation helpers deserve isolated coverage

Documentation touch-up if needed after code changes:

- `vignettes/shiny-dashboard.Rmd`
- `README.md`

## Implementation Notes

### Helper Placement

Prefer moving reusable parsing and script-generation helpers into `R/analysis_utils.R` or a closely related shared file rather than leaving batch parsing embedded inside the Shiny observer.

### Engine Compatibility

Do not redesign `wapor_run_seasonal_analysis()` unless the fix proves impossible without it. The engine already accepts named multi-period input and should remain the execution backend.

### Local Raster Coverage

Batch-mode local coverage checks should report missing data by:

- season label
- variable
- missing timesteps or missing range

This keeps the failure actionable for users who already have partial downloads on disk.

### Session Safety

Use explicit early returns and clear error handling in the run path so malformed batch input or missing local data produces a notification or modal rather than destabilizing the Shiny session.

## Testing Plan

Add regression coverage for the behaviors that failed.

### Unit-Level

- batch-list parser accepts valid lines and returns named season periods
- batch-list parser rejects malformed lines with useful messages
- script generator returns correct single-season script structure
- script generator returns correct batch-mode script structure

### Engine/Workflow-Level

- `wapor_run_seasonal_analysis()` continues to accept named multi-period configs
- local multi-season config reaches the engine without single-period errors
- multi-season script output includes the configured season labels and local-folder logic

### Manual Verification

In Shiny:

1. configure a single-season local analysis and validate
2. confirm code preview matches configuration
3. export the script and confirm it is a runnable `.R` file template
4. configure a batch local analysis with two or more seasons
5. validate without session disconnect
6. run without Shiny session loss
7. confirm exported script contains the named season list and matching analysis settings

## Risks

- batch-mode support currently crosses Shiny, validation, and script-generation layers, so partial fixes can leave hidden drift behind
- if the old generic `renderText()` preview remains in place, it can silently override the intended generated script
- local-data diagnostics may become noisy if all missing data is dumped without season grouping

## Mitigations

- use one canonical config builder
- use one script-generation source
- keep batch parsing isolated and tested
- keep error messages grouped by season and variable

## Exit Criteria

The work is complete when:

- single-season analysis still behaves as before
- multi-season local analysis no longer disconnects the Shiny session due to server-side batch logic
- validation, run, and script preview all consume the same normalized configuration
- users can export a reusable `.R` script that matches either the single-season or multi-season dashboard configuration
- regression tests cover the batch parsing and script-generation paths
