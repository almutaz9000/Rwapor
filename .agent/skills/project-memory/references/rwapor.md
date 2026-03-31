# Project: Rwapor
_Last updated: 2026-03-31_

## ✅ Confirmed / Working

- **[terra + sf]**: Use `terra::rast()` and `terra::vect()` throughout. Avoid `raster` and `sp` packages.
  _Context: Established codebase baseline._

- **[exactextractr]**: Preferred for fast, pixel-weighted zonal statistics.
  _Context: Used in wapor_ts and analysis modules for performance._

- **[safe_project]**: Helper function in `utils.R` to prevent PROJ database crashes on Windows during CRS transformation.
  _Context: Added after multiple reports of session crashes on user machines._

- **[memoise]**: API URL generation is memoized to reduce latency in repeated downloads or analysis.
  _Context: Integral to api_client.R performance._

- **[shinyvalidate]**: Standard for all module input validation.
  _Context: Implemented in mod_download.R._

- **[Metadata-Driven Aggregation]**: Variable behavior (sum vs mean) is determined by checking if units contain temporal component (`extract_temporal_unit()`). Variables with no temporal unit (e.g., "K" for temperature) use weighted_mean; flux variables with "/day" use weighted_sum.
  _Context: Core design pattern in utils.R functions: `get_seasonal_aggregation_rule()`, `get_seasonal_multiplier_values()`._
  _Session: 2026-03-31 - User questioned why temperature aggregates differently than precipitation._

- **[Automatic Dekadal Conversion]**: Dekadal variables (suffix "-D") with "/day" units automatically convert to dekadal totals by default unless user explicitly overrides. This is the expected behavior for WaPOR dekadal data.
  _Context: Implemented in `resolve_output_unit_conversion()` - returns "dekad" for L1/L2/L3 "-D" variables._
  _Session: 2026-03-31 - Confirmed as correct default behavior for user workflows._

- **[Terra Auto-Scales]**: Scale factors in metadata are reference-only. `terra::rast()` automatically applies embedded scale/offset from GeoTIFF metadata. Package does NOT manually apply scale factors.
  _Context: Critical for understanding NPP values. Raw integer 5000 with scale=0.001 → terra returns 5.0 gC/m²/day automatically._
  _Session: 2026-03-31 - User questioned why NPP values seemed low._

- **[Kelvin to Celsius Conversion]**: Automatic conversion for AGERA5-TMIN-E and AGERA5-TMAX-E variables. Applied via `wapor_convert_temperature()` in all download paths (wapor_map, wapor_ts, seasonal_download). Metadata units automatically updated from "K" to "degC".
  _Context: Added in v0.9.2 - conversion formula: °C = K - 273.15._
  _Session: 2026-03-31 - User requested automatic temperature conversion._

- **[New Aggregation Logic Skill]**: Created comprehensive skill documenting metadata-driven aggregation, unit conversion, multipliers, and temperature handling at `.agent/skills/rwapor-aggregation-logic/SKILL.md`.
  _Context: 50+ section reference covering all edge cases and debugging workflows for seasonal aggregation._
  _Session: 2026-03-31 - Improves agent understanding of complex aggregation logic._

## ❌ Failed / Avoid

- **[Hardcoded Variable Strings]**: Using `L1-NPP-D` instead of a reactive or user-supplied variable code.
  _Error or reason: Caused file-not-found warnings in early analysis module versions._

- **[Date Mismatch]**: Discrepancy between date-string formatting in the file downloader vs the local file checker (e.g. YYYYMMDD vs YYYY-MM-DD).
  _Error or reason: Resulted in the system asking to re-download files that were already on disk._

- **[Mixing terra/raster]**: Attempting to pass a `terra` SpatRaster to a function expecting a `raster` Layer (or vice-versa).
  _Error or reason: Immediate R error or unexpected NULL results._

- **[Manual Scale Factor Application]**: Applying scale factors manually (e.g., `r * 0.001`) when terra already applied them during read.
  _Error or reason: Results in double-scaling (e.g., NPP values 1000x too small). Terra auto-applies scales from GeoTIFF metadata._
  _Session: 2026-03-31 - Confirmed that package correctly relies on terra's automatic scaling._

## 📝 Open Questions / Undecided

- **[Parallel Processing]**: Evaluating if `future.apply` should be the default for all zonal stats, or only for multi-region extractions.
- **[Kc Automation]**: Planning to add automatic Kc retrieval from a remote database.

## 🎯 Completed Tasks (v0.9.2)

- **[Temperature Conversion Feature]**: Added automatic K→°C conversion for AGERA5 temperature variables.
  _Files modified: R/unit_convertor.R (new function), R/wapor_map.R, R/wapor_ts.R, R/seasonal_download.R, R/utils.R_
  _Completed: 2026-03-31_

- **[Documentation Update]**: Updated CLAUDE.md with key behaviors section documenting dekadal defaults, temperature conversion, metadata-driven aggregation, and terra auto-scaling.
  _Completed: 2026-03-31_

- **[Aggregation Logic Documentation]**: Created comprehensive skill file documenting all aggregation rules, multiplier calculation, unit conversion logic, and common pitfalls.
  _Location: .agent/skills/rwapor-aggregation-logic/SKILL.md_
  _Completed: 2026-03-31_

## 🔄 Pending Tasks

- **[Testing Temperature Conversion]**: Run full test suite to validate temperature conversion doesn't break existing tests.
  _Command: `devtools::test()`_
  _Priority: HIGH - should be done before next commit_

- **[User Documentation]**: Update README.md and vignettes to document automatic temperature conversion and dekadal defaults.
  _Priority: MEDIUM - for next release notes_

- **[Example Updates]**: Add examples showing temperature conversion and seasonal temperature aggregation to function documentation.
  _Priority: LOW - improve discoverability_

## 💡 Key Insights

- **Metadata is the Source of Truth**: Never hardcode aggregation logic. Always check variable metadata (units, temporal resolution) to determine behavior.

- **User Expectations vs. File Format**: WaPOR dekadal files store daily rates (mm/day) but users expect dekadal totals (mm/dekad). Default conversion handles this mismatch automatically.

- **Temperature is Special**: Unlike flux variables, temperature is an intensive property. It must be averaged (weighted_mean), not summed, during seasonal aggregation.

- **Scale Factors are Transparent**: Users never need to think about scale factors. Terra handles them automatically during raster reads.

- **Four Key Decision Functions**: Understanding aggregation behavior requires knowing:
  1. `extract_temporal_unit()` - Parse temporal unit from metadata
  2. `get_seasonal_aggregation_rule()` - Decide sum vs mean
  3. `resolve_output_unit_conversion()` - Set default conversion
  4. `get_seasonal_multiplier_values()` - Calculate per-layer multipliers
