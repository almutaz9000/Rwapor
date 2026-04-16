#' WaPOR v3 Variable Metadata
#'
#' A named list containing metadata for WaPOR version 3 variables including
#' Level 1 (L1), Level 2 (L2), and Level 3 (L3) products. Each entry contains
#' the variable's long name, measurement units, and scale factor.
#'
#' @format A named list where each element is a list with:
#' \describe{
#'   \item{long_name}{Character. Full descriptive name of the variable}
#'   \item{units}{Character. Measurement units (e.g., "mm/day", "kg/m3")}
#'   \item{scale}{Numeric. Scale factor to convert raw values to physical units.
#'     Note: WaPOR GeoTIFFs include scale/offset in their raster metadata, so
#'     \code{terra::rast()} automatically applies the scale factor when reading
#'     pixel values. The scale values here are retained for reference and for
#'     contexts where raw integer values are used directly.}
#' }
#'
#' @details
#' Variable naming convention: `{Level}-{Variable}-{TemporalResolution}`
#'
#' **Levels:**
#' * L1: Continental scale (~250m resolution for Africa and Near East)
#' * L2: Country/regional scale (~100m resolution)
#' * L3: Sub-national / irrigation scheme scale (~10-20m resolution)
#'
#' **Temporal Resolutions:**
#' * A: Annual
#' * M: Monthly
#' * D: Dekadal (10-day periods)
#' * E: Daily
#'
#' @examples
#' # Get metadata for dekadal ET
#' WAPOR3_VARS[["L1-AETI-D"]]
#'
#' # List all available variables
#' names(WAPOR3_VARS)
#'
#' # List L3 variables only
#' grep("^L3-", names(WAPOR3_VARS), value = TRUE)
#'
#' @seealso [AGERA5_VARS] for climate variables, [L3_REGIONS] for L3 region
#'   codes, [wapor_variable_metadata()] for dynamic metadata fetching
#'
#' @export
WAPOR3_VARS <- list(
  # ---- Level 1 (L1) - Continental scale (~250m) ----------------------------
  "L1-AETI-A" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/year", scale = 0.1),
  "L1-AETI-D" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/day", scale = 0.1),
  "L1-AETI-M" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/month", scale = 0.1),
  "L1-E-A"    = list(long_name = "Evaporation", units = "mm/year", scale = 0.1),
  "L1-E-D"    = list(long_name = "Evaporation", units = "mm/day", scale = 0.1),
  "L1-GBWP-A" = list(long_name = "Gross Biomass Water Productivity", units = "kg/m\u00b3", scale = 0.001),
  "L1-I-A"    = list(long_name = "Interception", units = "mm/year", scale = 0.1),
  "L1-I-D"    = list(long_name = "Interception", units = "mm/day", scale = 0.1),
  "L1-NBWP-A" = list(long_name = "Net Biomass Water Productivity", units = "kg/m\u00b3", scale = 0.001),
  "L1-NPP-D"  = list(long_name = "Net Primary Production", units = "gC/m\u00b2/day", scale = 0.001),
  "L1-NPP-M"  = list(long_name = "Net Primary Production", units = "gC/m\u00b2/month", scale = 0.001),
  "L1-PCP-A"  = list(long_name = "Precipitation", units = "mm/year", scale = 0.1),
  "L1-PCP-D"  = list(long_name = "Precipitation", units = "mm/day", scale = 0.1),
  "L1-PCP-E"  = list(long_name = "Precipitation", units = "mm/day", scale = 0.1),
  "L1-PCP-M"  = list(long_name = "Precipitation", units = "mm/month", scale = 0.1),
  "L1-RET-D"  = list(long_name = "Reference Evapotranspiration", units = "mm/day", scale = 0.1),
  "L1-RET-E"  = list(long_name = "Reference Evapotranspiration", units = "mm/day", scale = 0.1),
  "L1-RSM-D"  = list(long_name = "Relative Soil Moisture", units = "%", scale = 0.001),
  "L1-T-A"    = list(long_name = "Transpiration", units = "mm/year", scale = 0.1),
  "L1-T-D"    = list(long_name = "Transpiration", units = "mm/day", scale = 0.1),
  "L1-TBP-A"  = list(long_name = "Total Biomass Production", units = "kg/ha", scale = 1.0),

  # ---- Level 2 (L2) - Country/regional scale (~100m) ----------------------
  "L2-AETI-A" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/year", scale = 0.1),
  "L2-AETI-D" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/day", scale = 0.1),
  "L2-AETI-M" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/month", scale = 0.1),
  "L2-E-A"    = list(long_name = "Evaporation", units = "mm/year", scale = 0.1),
  "L2-E-D"    = list(long_name = "Evaporation", units = "mm/day", scale = 0.1),
  "L2-GBWP-A" = list(long_name = "Gross Biomass Water Productivity", units = "kg/m\u00b3", scale = 0.001),
  "L2-I-A"    = list(long_name = "Interception", units = "mm/year", scale = 0.1),
  "L2-I-D"    = list(long_name = "Interception", units = "mm/day", scale = 0.1),
  "L2-NBWP-A" = list(long_name = "Net Biomass Water Productivity", units = "kg/m\u00b3", scale = 0.001),
  "L2-NPP-D"  = list(long_name = "Net Primary Production", units = "gC/m\u00b2/day", scale = 0.001),
  "L2-NPP-M"  = list(long_name = "Net Primary Production", units = "gC/m\u00b2/month", scale = 0.001),
  "L2-RSM-D"  = list(long_name = "Relative Soil Moisture", units = "%", scale = 0.001),
  "L2-T-A"    = list(long_name = "Transpiration", units = "mm/year", scale = 0.1),
  "L2-T-D"    = list(long_name = "Transpiration", units = "mm/day", scale = 0.1),
  "L2-TBP-A"  = list(long_name = "Total Biomass Production", units = "kg/ha", scale = 1.0),

  # ---- Level 3 (L3) - Irrigation scheme scale (~10-20m) --------------------
  "L3-AETI-A" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/year", scale = 0.1),
  "L3-AETI-D" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/day", scale = 0.1),
  "L3-AETI-M" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/month", scale = 0.1),
  "L3-AETI-E" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/day", scale = 0.1),
  "L3-E-A"    = list(long_name = "Evaporation", units = "mm/year", scale = 0.1),
  "L3-E-D"    = list(long_name = "Evaporation", units = "mm/day", scale = 0.1),
  "L3-E-E"    = list(long_name = "Evaporation", units = "mm/day", scale = 0.1),
  "L3-GBWP-A" = list(long_name = "Gross Biomass Water Productivity", units = "kg/m\u00b3", scale = 0.001),
  "L3-I-E"    = list(long_name = "Interception", units = "mm/day", scale = 0.1),
  "L3-NPP-D"  = list(long_name = "Net Primary Production", units = "gC/m\u00b2/day", scale = 0.001),
  "L3-NPP-M"  = list(long_name = "Net Primary Production", units = "gC/m\u00b2/month", scale = 0.001),
  "L3-NPP-E"  = list(long_name = "Net Primary Production", units = "gC/m\u00b2/day", scale = 0.001),
  "L3-RSM-D"  = list(long_name = "Relative Soil Moisture", units = "%", scale = 0.001),
  "L3-RSM-E"  = list(long_name = "Relative Soil Moisture", units = "%", scale = 0.001),
  "L3-T-A"    = list(long_name = "Transpiration", units = "mm/year", scale = 0.1),
  "L3-T-D"    = list(long_name = "Transpiration", units = "mm/day", scale = 0.1),
  "L3-T-E"    = list(long_name = "Transpiration", units = "mm/day", scale = 0.1),
  "L3-TBP-A"  = list(long_name = "Total Biomass Production", units = "kg/ha", scale = 1.0)
)

#' AgERA5 Climate Variable Metadata
#'
#' A named list containing metadata for AgERA5 climate reanalysis variables.
#' AgERA5 provides climate data based on ERA5 reanalysis, tailored for
#' agricultural applications.
#'
#' @format A named list where each element is a list with:
#' \describe{
#'   \item{long_name}{Character. Full descriptive name of the variable}
#'   \item{units}{Character. Measurement units}
#'   \item{scale}{Numeric. Scale factor (typically 1.0 for AgERA5)}
#' }
#'
#' @details
#' Variable naming convention: `AGERA5-{Variable}-{TemporalResolution}`
#'
#' **Available Variables:**
#' * ET0: Reference Evapotranspiration (FAO Penman-Monteith)
#' * TMIN/TMAX: Minimum/Maximum Air Temperature at 2m
#' * SRF: Solar Radiation Flux
#' * WS: Wind Speed at 2m
#' * PF: Precipitation Flux
#'
#' @examples
#' # Get metadata for daily ET0
#' AGERA5_VARS[["AGERA5-ET0-E"]]
#'
#' # List all AgERA5 variables
#' names(AGERA5_VARS)
#'
#' @seealso [WAPOR3_VARS] for WaPOR variables
#'
#' @export
AGERA5_VARS <- list(
  "AGERA5-ET0-E"  = list(long_name = "Reference Evapotranspiration", units = "mm/day", scale = 1.0),
  "AGERA5-ET0-D"  = list(long_name = "Reference Evapotranspiration", units = "mm/dekad", scale = 1.0),
  "AGERA5-ET0-M"  = list(long_name = "Reference Evapotranspiration", units = "mm/month", scale = 1.0),
  "AGERA5-ET0-A"  = list(long_name = "Reference Evapotranspiration", units = "mm/year", scale = 1.0),
  "AGERA5-TMIN-E" = list(long_name = "Minimum Air Temperature (2m)", units = "K", scale = 1.0),
  "AGERA5-TMAX-E" = list(long_name = "Maximum Air Temperature (2m)", units = "K", scale = 1.0),
  "AGERA5-SRF-E"  = list(long_name = "Solar Radiation", units = "J/m2/day", scale = 1.0),
  "AGERA5-WS-E"   = list(long_name = "Wind Speed", units = "m/s", scale = 1.0),
  "AGERA5-PF-E"   = list(long_name = "Precipitation", units = "mm/day", scale = 1.0),
  "AGERA5-PF-D"   = list(long_name = "Precipitation", units = "mm/dekad", scale = 1.0),
  "AGERA5-PF-M"   = list(long_name = "Precipitation", units = "mm/month", scale = 1.0),
  "AGERA5-PF-A"   = list(long_name = "Precipitation", units = "mm/year", scale = 1.0),
  "AGERA5-RH06-E" = list(long_name = "Relative Humidity 06h", units = "0-1", scale = 1.0),
  "AGERA5-RH09-E" = list(long_name = "Relative Humidity 09h", units = "0-1", scale = 1.0),
  "AGERA5-RH12-E" = list(long_name = "Relative Humidity 12h", units = "0-1", scale = 1.0),
  "AGERA5-RH15-E" = list(long_name = "Relative Humidity 15h", units = "0-1", scale = 1.0),
  "AGERA5-RH18-E" = list(long_name = "Relative Humidity 18h", units = "0-1", scale = 1.0)
)

#' WaPOR Level 3 Region Metadata
#'
#' A named list containing metadata for all available WaPOR Level 3 (L3) regions.
#' Each region represents an irrigation scheme, river basin, or study area at
#' high resolution (~10-20m). Region codes are 3-letter uppercase identifiers
#' used by the FAO GISMGR API.
#'
#' @format A named list where each element (keyed by 3-letter region code)
#'   is a list with:
#' \describe{
#'   \item{name}{Character. Full name of the region/study area}
#'   \item{country}{Character. Country where the region is located}
#' }
#'
#' @details
#' Sourced from the FAO GISMGR mosaicsets API (grid.tile.code and
#' grid.tile.caption fields). Not all regions are available for all L3
#' variables -- availability depends on the specific product.
#'
#' @examples
#' # Get region info for Awash Basin
#' L3_REGIONS[["AWA"]]
#'
#' # List all region codes
#' names(L3_REGIONS)
#'
#' # Get all regions in a specific country
#' Filter(function(r) r$country == "Kenya", L3_REGIONS)
#'
#' @seealso [WAPOR3_VARS] for variable metadata
#'
#' @export
L3_REGIONS <- list(
  # ---- Algeria -------------------------------------------------------------
  "MIT" = list(name = "Mitidja", country = "Algeria"),

  # ---- Colombia ------------------------------------------------------------
  "MAG" = list(name = "Magdalena", country = "Colombia"),
  "NDV" = list(name = "Valle del Cauca", country = "Colombia"),

  # ---- Egypt ---------------------------------------------------------------
  "ENO" = list(name = "Northern Egypt", country = "Egypt"),
  "ZAN" = list(name = "Zankalon", country = "Egypt"),

  # ---- Ethiopia ------------------------------------------------------------
  "AWA" = list(name = "Awash", country = "Ethiopia"),
  "KOG" = list(name = "Koga", country = "Ethiopia"),

  # ---- Iraq ----------------------------------------------------------------
  "ERB" = list(name = "Erbil", country = "Iraq"),
  "GAR" = list(name = "West Gharraf", country = "Iraq"),
  "NAJ" = list(name = "Najaf", country = "Iraq"),

  # ---- Jordan --------------------------------------------------------------
  "JAF" = list(name = "Jafr-Shoubak", country = "Jordan"),
  "JVA" = list(name = "North Jordan Valley", country = "Jordan"),

  # ---- Kenya ---------------------------------------------------------------
  "BUS" = list(name = "Busia", country = "Kenya"),
  "KMW" = list(name = "Mwea", country = "Kenya"),
  "KTB" = list(name = "Tana and Bura", country = "Kenya"),

  # ---- Lebanon -------------------------------------------------------------
  "BKA" = list(name = "Bekaa", country = "Lebanon"),

  # ---- Libya ---------------------------------------------------------------
  "LCE" = list(name = "Fezzan", country = "Libya"),
  "LDA" = list(name = "Waddan", country = "Libya"),
  "LOT" = list(name = "Tarhona", country = "Libya"),

  # ---- Mali ----------------------------------------------------------------
  "ODN" = list(name = "Office du Niger", country = "Mali"),

  # ---- Morocco -------------------------------------------------------------
  "LOU" = list(name = "Moulay Bousselham", country = "Morocco"),

  # ---- Mozambique ----------------------------------------------------------
  "LAM" = list(name = "Lamego", country = "Mozambique"),
  "MBL" = list(name = "Baixo Limpopo", country = "Mozambique"),

  # ---- Pakistan ------------------------------------------------------------
  "KWL" = list(name = "Khanewal", country = "Pakistan"),
  "SNG" = list(name = "Sanghar", country = "Pakistan"),

  # ---- Palestine -----------------------------------------------------------
  "PAL" = list(name = "Jericho", country = "Palestine"),

  # ---- Rwanda --------------------------------------------------------------
  "LAK" = list(name = "Lower Akagera", country = "Rwanda"),
  "MUV" = list(name = "Muvumba catchment", country = "Rwanda"),
  "YAN" = list(name = "Yanze catchment", country = "Rwanda"),

  # ---- Senegal -------------------------------------------------------------
  "SED" = list(name = "Senegal Delta", country = "Senegal"),

  # ---- Sri Lanka -----------------------------------------------------------
  "MAL" = list(name = "Malwathu Oya West Sub Catchment", country = "Sri Lanka"),

  # ---- Sudan ---------------------------------------------------------------
  "GEZ" = list(name = "Gezira", country = "Sudan"),

  # ---- Tunisia -------------------------------------------------------------
  "JEN" = list(name = "Jendouba", country = "Tunisia"),
  "KAI" = list(name = "Kairouan", country = "Tunisia"),
  "THR" = list(name = "High-resolution experimental area", country = "Tunisia"),

  # ---- Vietnam -------------------------------------------------------------
  "VTM" = list(name = "Tay Nguyen", country = "Vietnam"),

  # ---- Yemen ---------------------------------------------------------------
  "SAN" = list(name = "Sanaa basin", country = "Yemen")
)

#' Fetch WaPOR Level 3 Regions
#'
#' Dynamically retrieves the list of available WaPOR Level 3 (L3) regions
#' from the FAO GISMGR API. This ensures that newly added irrigation
#' schemes or study areas are available without updating the package.
#'
#' @return A data.frame with columns:
#' \describe{
#'   \item{code}{3-letter region code (e.g., "AWA")}
#'   \item{name}{Full name of the region (e.g., "Awash")}
#'   \item{country}{Country name extracted from the API caption}
#'   \item{caption}{Original full caption from the API}
#' }
#'
#' @details
#' Queries the \code{L3-GRID/tiles} endpoint. If the API request fails,
#' it falls back to the static \code{L3_REGIONS} list. Results are memoized.
#'
#' @export
#' @importFrom httr2 request req_perform resp_body_json req_timeout
wapor_fetch_l3_regions <- function() {
  url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/grids/L3-GRID/tiles"
  
  tryCatch({
    # Use the internal collector to handle pagination if many regions are added
    items <- collect_responses(url, info = NULL)
    
    if (length(items) == 0) return(wapor_l3_regions_to_df(L3_REGIONS))
    
    df <- do.call(rbind, lapply(items, function(x) {
      caption_parts <- strsplit(x$caption, ",")[[1]]
      data.frame(
        code    = x$code,
        name    = trimws(caption_parts[1]),
        country = if (length(caption_parts) > 1) trimws(caption_parts[2]) else "Unknown",
        caption = x$caption,
        stringsAsFactors = FALSE
      )
    }))
    
    return(df[order(df$country, df$name), ])
    
  }, error = function(e) {
    warning("Failed to fetch L3 regions from API, falling back to static list: ", e$message)
    return(wapor_l3_regions_to_df(L3_REGIONS))
  })
}

#' Convert L3_REGIONS list to data.frame
#' @keywords internal
#' @export
wapor_l3_regions_to_df <- function(reg_list) {
  df <- do.call(rbind, lapply(names(reg_list), function(n) {
    data.frame(
      code    = n,
      name    = reg_list[[n]]$name,
      country = reg_list[[n]]$country,
      caption = paste0(reg_list[[n]]$name, ", ", reg_list[[n]]$country),
      stringsAsFactors = FALSE
    )
  }))
  df[order(df$country, df$name), ]
}

#' Get Variable Metadata (Internal)
#'
#' Internal function that retrieves variable metadata from static lists
#' or dynamically from the FAO GISMGR API.
#'
#' @param variable Character. Variable code (e.g., "L1-AETI-D").
#'
#' @return A list with components:
#'   * `long_name`: Full descriptive name
#'   * `units`: Measurement units
#'   * `scale`: Scale factor
#'
#'   Returns NULL if metadata cannot be retrieved.
#'
#' @importFrom httr2 request req_perform resp_body_json req_timeout
#' @keywords internal
#' @noRd
get_variable_metadata_internal <- function(variable) {
  if (!is.character(variable) || length(variable) != 1) {
    stop("'variable' must be a single character string", call. = FALSE)
  }

  # 1. Try metadata from static lists
  if (variable %in% names(WAPOR3_VARS)) {
    return(WAPOR3_VARS[[variable]])
  }
  if (variable %in% names(AGERA5_VARS)) {
    return(AGERA5_VARS[[variable]])
  }

  # 2. Level-based Fallback (ETa/RET and PCP are only L1 at dekadal scale)
  # Check for L2/L3 variables that we know must use L1 sources
  parts <- strsplit(variable, "-")[[1]]
  if (length(parts) >= 2) {
    level <- parts[1]
    if (level %in% c("L2", "L3") && grepl("-(RET|PCP)-", variable)) {
      fallback_var <- sub("^L[23]-", "L1-", variable)
      # Check if fallback is already in static list
      if (fallback_var %in% names(WAPOR3_VARS)) {
         return(WAPOR3_VARS[[fallback_var]])
      }
      # If not in static list, continue to fetch from API - BUT for the L1 version
      variable <- fallback_var
    }
  }

  # 3. Dynamic fetch from API
  message("Variable '", variable, "' not in static list. Fetching metadata from API...")

  level <- parts[1]
  base_url <- if (level %in% c("L1", "L2")) {
    "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets"
  } else if (level == "L3") {
    "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets"
  } else if (level == "AGERA5") {
    "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/C3S/mapsets"
  } else {
    warning("Unknown level for variable: ", variable, call. = FALSE)
    return(NULL)
  }

  mapset_id <- if (level == "AGERA5" && grepl("-E$", variable)) sub("-E$", "", variable) else variable
  url <- paste0(base_url, "/", mapset_id)

  tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_timeout(30) |>
      httr2::req_perform() |>
      httr2::resp_body_json()

    data <- resp$response

    meta <- list(
      long_name = if (!is.null(data$measureCaption)) data$measureCaption else "Unknown",
      units = if (!is.null(data$measureUnit)) data$measureUnit else "unknown",
      scale = if (!is.null(data$scale)) as.numeric(data$scale) else 1.0
    )

    return(meta)

  }, error = function(e) {
    warning("Failed to fetch metadata for ", variable, ": ", e$message, call. = FALSE)
    return(NULL)
  })
}

#' Get Variable Metadata
#'
#' Retrieves metadata for WaPOR or AgERA5 variables. First checks the
#' built-in static metadata lists, then falls back to querying the
#' FAO GISMGR API for unknown variables. Results are cached using
#' memoization for performance.
#'
#' @param variable Character. Variable code following the naming convention
#'   `{Level}-{Variable}-{TemporalResolution}` (e.g., "L1-AETI-D", "AGERA5-ET0-E").
#'
#' @return A list with components:
#'   * `long_name`: Full descriptive name of the variable
#'   * `units`: Measurement units (e.g., "mm/day", "K")
#'   * `scale`: Scale factor to convert raw values to physical units
#'
#'   Returns NULL if the variable is not found and API lookup fails.
#'
#' @details
#' The function uses memoization to cache API responses, so repeated
#' calls for the same variable are fast. Static metadata is available
#' for all WaPOR (L1, L2, L3) and AgERA5 variables.
#'
#' @export
#'
#' @importFrom memoise memoise
#'
#' @examples
#' # Get metadata for a WaPOR variable
#' meta <- wapor_variable_metadata("L1-AETI-D")
#' meta$long_name
#' # [1] "Actual EvapoTranspiration and Interception"
#' meta$units
#' # [1] "mm/day"
#'
#' # Get metadata for an AgERA5 variable
#' meta <- wapor_variable_metadata("AGERA5-ET0-E")
#' meta$units
#' # [1] "mm/day"
#'
#' # Get metadata for L3 variable (now in static list)
#' meta <- wapor_variable_metadata("L3-AETI-D")
#' meta$units
#' # [1] "mm/day"
wapor_variable_metadata <- memoise::memoise(get_variable_metadata_internal)
