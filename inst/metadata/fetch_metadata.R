## fetch_metadata.R
## Standalone script to fetch WaPOR v3 variable metadata from the FAO GISMGR
## API and write three JSON files:
##   inst/metadata/wapor_L1.json
##   inst/metadata/wapor_L2.json
##   inst/metadata/wapor_L3.json
##
## Run with:
##   /c/Program Files/R/R-4.5.2/bin/Rscript inst/metadata/fetch_metadata.R
##
## API field names (confirmed from live API inspection):
##   Top-level item fields: code, caption, measureCaption, measureUnit,
##   scale, offset, tags, links
##   Pagination: response.links[] with rel="next" / href
##   No spatialExtent or bbox in list responses.
## ---------------------------------------------------------------------------

## ---- 0. Dependencies -------------------------------------------------------
if (!requireNamespace("httr2",    quietly = TRUE)) install.packages("httr2")
if (!requireNamespace("jsonlite", quietly = TRUE)) install.packages("jsonlite")

library(httr2)
library(jsonlite)

## ---- 1. Resolve output directory -------------------------------------------
## Works whether called via Rscript --file=... or sourced interactively.
script_dir <- tryCatch({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/"))
  } else {
    ## Sourced interactively: fall back to package inst/metadata
    normalizePath(
      file.path("c:/Users/almut/OneDrive/Documents/Bitbucket/wapordl/Rwapor",
                "inst", "metadata"),
      winslash = "/", mustWork = FALSE
    )
  }
}, error = function(e) {
  normalizePath(
    file.path("c:/Users/almut/OneDrive/Documents/Bitbucket/wapordl/Rwapor",
              "inst", "metadata"),
    winslash = "/", mustWork = FALSE
  )
})

out_dir <- script_dir
message("Output directory: ", out_dir)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

## ---- 2. HTTP helpers -------------------------------------------------------

safe_get <- function(url, timeout = 60, max_tries = 3) {
  for (attempt in seq_len(max_tries)) {
    result <- tryCatch({
      httr2::request(url) |>
        httr2::req_timeout(timeout) |>
        httr2::req_error(is_error = function(resp) FALSE) |>
        httr2::req_perform() |>
        httr2::resp_body_json()
    }, error = function(e) {
      message("  [attempt ", attempt, "/", max_tries, "] Error: ", e$message)
      NULL
    })
    if (!is.null(result)) return(result)
    if (attempt < max_tries) Sys.sleep(2)
  }
  NULL
}

## Paginate through all items for a given base URL.
## The API wraps items in resp$response$items and pagination links in
## resp$response$links[].
fetch_all_items <- function(base_url) {
  all_items <- list()
  next_url  <- base_url

  while (!is.null(next_url)) {
    message("  Fetching: ", next_url)
    resp <- safe_get(next_url)

    if (is.null(resp)) {
      message("  Could not fetch URL, stopping pagination.")
      break
    }

    data <- resp$response
    if (is.null(data)) {
      message("  Empty response$response, stopping.")
      break
    }

    if (!is.null(data$items) && length(data$items) > 0) {
      all_items <- c(all_items, data$items)
    }

    ## Look for rel="next" link for pagination
    next_url <- NULL
    if (!is.null(data$links)) {
      for (lnk in data$links) {
        if (identical(lnk$rel, "next")) {
          next_url <- lnk$href
          break
        }
      }
    }
  }

  all_items
}

## ---- 3. Parse a single item into the standard record format ----------------
## API item fields (confirmed): code, caption, measureCaption, measureUnit,
## scale, offset, tags, links  (no info/properties, no spatialExtent/bbox)

parse_item <- function(item, level) {
  code <- item$code
  if (is.null(code) || !grepl(paste0("^", level, "-"), code)) return(NULL)

  ## Long name: prefer measureCaption, fall back to caption, then code
  long_name <- item$measureCaption %||% item$caption %||% code

  ## Units
  units <- item$measureUnit %||% "unknown"

  ## Scale
  scale_val <- if (!is.null(item$scale)) as.numeric(item$scale) else 1.0

  ## Temporal resolution: last segment of code after final "-"
  parts <- strsplit(code, "-")[[1]]
  temporal_resolution <- if (length(parts) >= 3) tail(parts, 1) else "unknown"

  list(
    code                = code,
    long_name           = long_name,
    units               = units,
    scale               = scale_val,
    temporal_resolution = temporal_resolution,
    spatial_extent      = NULL,
    level               = level
  )
}

## Null-coalescing operator (like %||% in rlang)
`%||%` <- function(a, b) if (!is.null(a) && length(a) == 1 && !is.na(a)) a else b

## ---- 4. Fallback data from R/metadata.R ------------------------------------
## Hardcoded mirror of WAPOR3_VARS so the script needs no package loaded.
## Also includes variables discovered via live API that were absent from
## the static list (L1-RET-A, L1-RET-M, L3-I-A, L3-I-D, L3-NBWP-A).

WAPOR3_VARS_FALLBACK <- list(
  # Level 1
  "L1-AETI-A" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/year",          scale = 0.1),
  "L1-AETI-D" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/day",           scale = 0.1),
  "L1-AETI-M" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/month",         scale = 0.1),
  "L1-E-A"    = list(long_name = "Evaporation",                                units = "mm/year",          scale = 0.1),
  "L1-E-D"    = list(long_name = "Evaporation",                                units = "mm/day",           scale = 0.1),
  "L1-GBWP-A" = list(long_name = "Gross Biomass Water Productivity",           units = "kg/m\u00b3",       scale = 0.001),
  "L1-I-A"    = list(long_name = "Interception",                               units = "mm/year",          scale = 0.1),
  "L1-I-D"    = list(long_name = "Interception",                               units = "mm/day",           scale = 0.1),
  "L1-NBWP-A" = list(long_name = "Net Biomass Water Productivity",             units = "kg/m\u00b3",       scale = 0.001),
  "L1-NPP-D"  = list(long_name = "Net Primary Production",                     units = "gC/m\u00b2/day",   scale = 0.001),
  "L1-NPP-M"  = list(long_name = "Net Primary Production",                     units = "gC/m\u00b2/month", scale = 0.001),
  "L1-PCP-A"  = list(long_name = "Precipitation",                              units = "mm/year",          scale = 0.1),
  "L1-PCP-D"  = list(long_name = "Precipitation",                              units = "mm/day",           scale = 0.1),
  "L1-PCP-E"  = list(long_name = "Precipitation",                              units = "mm/day",           scale = 0.1),
  "L1-PCP-M"  = list(long_name = "Precipitation",                              units = "mm/month",         scale = 0.1),
  "L1-RET-A"  = list(long_name = "Reference Evapotranspiration",               units = "mm/year",          scale = 0.1),
  "L1-RET-D"  = list(long_name = "Reference Evapotranspiration",               units = "mm/day",           scale = 0.1),
  "L1-RET-E"  = list(long_name = "Reference Evapotranspiration",               units = "mm/day",           scale = 0.1),
  "L1-RET-M"  = list(long_name = "Reference Evapotranspiration",               units = "mm/month",         scale = 0.1),
  "L1-RSM-D"  = list(long_name = "Relative Soil Moisture",                     units = "%",                scale = 0.001),
  "L1-T-A"    = list(long_name = "Transpiration",                              units = "mm/year",          scale = 0.1),
  "L1-T-D"    = list(long_name = "Transpiration",                              units = "mm/day",           scale = 0.1),
  "L1-TBP-A"  = list(long_name = "Total Biomass Production",                   units = "kg/ha",            scale = 1.0),
  # Level 2
  "L2-AETI-A" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/year",          scale = 0.1),
  "L2-AETI-D" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/day",           scale = 0.1),
  "L2-AETI-M" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/month",         scale = 0.1),
  "L2-E-A"    = list(long_name = "Evaporation",                                units = "mm/year",          scale = 0.1),
  "L2-E-D"    = list(long_name = "Evaporation",                                units = "mm/day",           scale = 0.1),
  "L2-GBWP-A" = list(long_name = "Gross Biomass Water Productivity",           units = "kg/m\u00b3",       scale = 0.001),
  "L2-I-A"    = list(long_name = "Interception",                               units = "mm/year",          scale = 0.1),
  "L2-I-D"    = list(long_name = "Interception",                               units = "mm/day",           scale = 0.1),
  "L2-NBWP-A" = list(long_name = "Net Biomass Water Productivity",             units = "kg/m\u00b3",       scale = 0.001),
  "L2-NPP-D"  = list(long_name = "Net Primary Production",                     units = "gC/m\u00b2/day",   scale = 0.001),
  "L2-NPP-M"  = list(long_name = "Net Primary Production",                     units = "gC/m\u00b2/month", scale = 0.001),
  "L2-RSM-D"  = list(long_name = "Relative Soil Moisture",                     units = "%",                scale = 0.001),
  "L2-T-A"    = list(long_name = "Transpiration",                              units = "mm/year",          scale = 0.1),
  "L2-T-D"    = list(long_name = "Transpiration",                              units = "mm/day",           scale = 0.1),
  "L2-TBP-A"  = list(long_name = "Total Biomass Production",                   units = "kg/ha",            scale = 1.0),
  # Level 3
  "L3-AETI-A" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/year",          scale = 0.1),
  "L3-AETI-D" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/day",           scale = 0.1),
  "L3-AETI-M" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/month",         scale = 0.1),
  "L3-AETI-E" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/day",           scale = 0.1),
  "L3-E-A"    = list(long_name = "Evaporation",                                units = "mm/year",          scale = 0.1),
  "L3-E-D"    = list(long_name = "Evaporation",                                units = "mm/day",           scale = 0.1),
  "L3-E-E"    = list(long_name = "Evaporation",                                units = "mm/day",           scale = 0.1),
  "L3-GBWP-A" = list(long_name = "Gross Biomass Water Productivity",           units = "kg/m\u00b3",       scale = 0.001),
  "L3-I-A"    = list(long_name = "Interception",                               units = "mm/year",          scale = 0.1),
  "L3-I-D"    = list(long_name = "Interception",                               units = "mm/day",           scale = 0.1),
  "L3-I-E"    = list(long_name = "Interception",                               units = "mm/day",           scale = 0.1),
  "L3-NBWP-A" = list(long_name = "Net Biomass Water Productivity",             units = "kg/m\u00b3",       scale = 0.001),
  "L3-NPP-D"  = list(long_name = "Net Primary Production",                     units = "gC/m\u00b2/day",   scale = 0.001),
  "L3-NPP-M"  = list(long_name = "Net Primary Production",                     units = "gC/m\u00b2/month", scale = 0.001),
  "L3-NPP-E"  = list(long_name = "Net Primary Production",                     units = "gC/m\u00b2/day",   scale = 0.001),
  "L3-RSM-D"  = list(long_name = "Relative Soil Moisture",                     units = "%",                scale = 0.001),
  "L3-RSM-E"  = list(long_name = "Relative Soil Moisture",                     units = "%",                scale = 0.001),
  "L3-T-A"    = list(long_name = "Transpiration",                              units = "mm/year",          scale = 0.1),
  "L3-T-D"    = list(long_name = "Transpiration",                              units = "mm/day",           scale = 0.1),
  "L3-T-E"    = list(long_name = "Transpiration",                              units = "mm/day",           scale = 0.1),
  "L3-TBP-A"  = list(long_name = "Total Biomass Production",                   units = "kg/ha",            scale = 1.0)
)

build_fallback_records <- function(level) {
  keys <- grep(paste0("^", level, "-"), names(WAPOR3_VARS_FALLBACK), value = TRUE)
  lapply(keys, function(k) {
    v     <- WAPOR3_VARS_FALLBACK[[k]]
    parts <- strsplit(k, "-")[[1]]
    tres  <- if (length(parts) >= 3) tail(parts, 1) else "unknown"
    list(
      code                = k,
      long_name           = v$long_name,
      units               = v$units,
      scale               = v$scale,
      temporal_resolution = tres,
      spatial_extent      = NULL,
      level               = level
    )
  })
}

## ---- 5. Merge API results with fallback ------------------------------------
## API results take precedence for units/scale if non-null/non-trivial.
## Fallback ensures all known variables are present and fills gaps.

merge_with_fallback <- function(api_records, level) {
  fallback <- build_fallback_records(level)
  api_codes <- vapply(api_records, `[[`, character(1), "code")

  for (fb in fallback) {
    if (!(fb$code %in% api_codes)) {
      ## Variable missing from API result - add from fallback
      api_records <- c(api_records, list(fb))
    } else {
      ## Variable present in API - patch from fallback where API is weak
      idx <- which(api_codes == fb$code)[1]
      rec <- api_records[[idx]]
      if (is.null(rec$units) || identical(rec$units, "unknown")) {
        api_records[[idx]]$units <- fb$units
      }
      if (is.null(rec$scale)) {
        api_records[[idx]]$scale <- fb$scale
      } else if (rec$scale == 1.0 && fb$scale != 1.0) {
        api_records[[idx]]$scale <- fb$scale
      }
      if (is.null(rec$long_name) || identical(rec$long_name, rec$code)) {
        api_records[[idx]]$long_name <- fb$long_name
      }
    }
  }

  ## Sort alphabetically by code
  codes <- vapply(api_records, `[[`, character(1), "code")
  api_records[order(codes)]
}

## ---- 6. Fetch from API -----------------------------------------------------

L1L2_BASE <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets"
L3_BASE    <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets"

message("=== Fetching L1/L2 mapsets ===")
l1l2_items <- tryCatch(
  fetch_all_items(L1L2_BASE),
  error = function(e) { message("  API error: ", e$message); list() }
)
message("  Raw items returned: ", length(l1l2_items))

## Filter: only L1/L2 codes, exclude UTM variants and quality/QUAL layers
is_core <- function(code, level) {
  grepl(paste0("^", level, "-"), code) &
    !grepl("-UTM-", code) &
    !grepl("-QUAL-", code)
}

l1_api <- Filter(function(x) !is.null(x$code) && is_core(x$code, "L1"), l1l2_items)
l2_api <- Filter(function(x) !is.null(x$code) && is_core(x$code, "L2"), l1l2_items)
message("  After filtering - L1: ", length(l1_api), "  L2: ", length(l2_api))

message("=== Fetching L3 mosaicsets ===")
l3_items <- tryCatch(
  fetch_all_items(L3_BASE),
  error = function(e) { message("  API error: ", e$message); list() }
)
message("  Raw items returned: ", length(l3_items))
l3_api <- Filter(function(x) !is.null(x$code) && is_core(x$code, "L3"), l3_items)
message("  After filtering - L3: ", length(l3_api))

## Parse each item
parse_list <- function(items, level) {
  records <- lapply(items, parse_item, level = level)
  Filter(Negate(is.null), records)
}

l1_records <- parse_list(l1_api, "L1")
l2_records <- parse_list(l2_api, "L2")
l3_records <- parse_list(l3_api, "L3")

if (length(l1_records) + length(l2_records) + length(l3_records) == 0) {
  message("WARNING: API returned no parseable items. Using fallback data only.")
}

## Merge with fallback
l1_final <- merge_with_fallback(l1_records, "L1")
l2_final <- merge_with_fallback(l2_records, "L2")
l3_final <- merge_with_fallback(l3_records, "L3")

## ---- 7. Write JSON files ---------------------------------------------------

write_json_file <- function(records, path) {
  json <- jsonlite::toJSON(records, pretty = TRUE, auto_unbox = TRUE, null = "null")
  writeLines(json, con = path, useBytes = FALSE)
  message("  Written: ", path, "  (", length(records), " records)")
}

message("=== Writing JSON files ===")
write_json_file(l1_final, file.path(out_dir, "wapor_L1.json"))
write_json_file(l2_final, file.path(out_dir, "wapor_L2.json"))
write_json_file(l3_final, file.path(out_dir, "wapor_L3.json"))

## ---- 8. Summary ------------------------------------------------------------
message("\n=== Summary ===")
message("  L1 variables: ", length(l1_final))
message("  L2 variables: ", length(l2_final))
message("  L3 variables: ", length(l3_final))
message("  Total:        ", length(l1_final) + length(l2_final) + length(l3_final))

invisible(NULL)
