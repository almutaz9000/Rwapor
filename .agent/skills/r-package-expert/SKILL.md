---
name: r-package-expert
description: R package maintenance for Rwapor
---

# R Package Expert - Rwapor Context

## Package Structure
```
R/                  # Core functions (stable)
inst/shiny/         # Shiny modules (in-development)
tests/testthat/     # Unit tests
man/                # Auto-generated docs (Roxygen2)
```

## Core Rules
- **terra** over raster (always)
- `@export` tag required for public functions
- Never edit `NAMESPACE` manually
- Run `devtools::document()` after any R/ changes

## Key Exports (66 total)
Primary: `wapor_map()`, `wapor_ts()`, `run_wapor()`
Analysis: `rwapor_load_crop_mask()`, `rwapor_harmonize_to_template()`, `rwapor_extract_crop_classes()`, `rwapor_build_kc_by_class()`

## Dependencies
| Package | Purpose |
|---------|---------|
| terra | Raster ops |
| sf | Vector ops |
| httr2 | API calls |
| exactextractr | Zonal stats |
| future.apply | Parallelism |

## Commands
```powershell
Rscript -e "devtools::document()"  # After R/ changes
Rscript -e "devtools::test()"      # Before commits
Rscript -e "devtools::check()"     # Full package check
```

## Common Patterns
```r
# Safe CRS handling (from analysis.R)
if (!nzchar(terra::crs(r))) {
  ext_r <- terra::ext(r)
  if (ext_r$xmin >= -180 && ext_r$xmax <= 180) {
    suppressWarnings(terra::crs(r) <- "EPSG:4326")
  }
}

# Raster harmonization
rwapor_harmonize_to_template(x, template, method = "near")
```
