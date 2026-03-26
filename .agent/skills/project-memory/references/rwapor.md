# Project: Rwapor
_Last updated: 2026-03-26_

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

## ❌ Failed / Avoid

- **[Hardcoded Variable Strings]**: Using `L1-NPP-D` instead of a reactive or user-supplied variable code.
  _Error or reason: Caused file-not-found warnings in early analysis module versions._

- **[Date Mismatch]**: Discrepancy between date-string formatting in the file downloader vs the local file checker (e.g. YYYYMMDD vs YYYY-MM-DD).
  _Error or reason: Resulted in the system asking to re-download files that were already on disk._

- **[Mixing terra/raster]**: Attempting to pass a `terra` SpatRaster to a function expecting a `raster` Layer (or vice-versa).
  _Error or reason: Immediate R error or unexpected NULL results._

## 📝 Open Questions / Undecided

- **[Parallel Processing]**: Evaluating if `future.apply` should be the default for all zonal stats, or only for multi-region extractions.
- **[Kc Automation]**: Planning to add automatic Kc retrieval from a remote database.
