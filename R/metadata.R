#' WaPOR v3 Variable Metadata
#'
#' A named list containing metadata for WaPOR version 3 variables including
#' Level 1 (L1) and Level 2 (L2) products. Each entry contains the variable's
#' long name, measurement units, and scale factor.
#'
#' @format A named list where each element is a list with:
#' \describe{
#'   \item{long_name}{Character. Full descriptive name of the variable}
#'   \item{units}{Character. Measurement units (e.g., "mm/day", "kg/m3")}
#'   \item{scale}{Numeric. Scale factor to convert raw values to physical units}
#' }
#'
#' @details
#' Variable naming convention: `{Level}-{Variable}-{TemporalResolution}`
#'
#' **Levels:**
#' * L1: Continental scale (~250m resolution for Africa and Near East)
#' * L2: Country/regional scale (~100m resolution)
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
#' @seealso [AGERA5_VARS] for climate variables, [get_variable_metadata()] for
#'   dynamic metadata fetching
#'
#' @export
WAPOR3_VARS <- list(
  "L1-AETI-A" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/year", scale = 0.1),
  "L1-AETI-D" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/day", scale = 0.1),
  "L1-AETI-M" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/month", scale = 0.1),
  "L1-E-A" = list(long_name = "Evaporation", units = "mm/year", scale = 0.1),
  "L1-E-D" = list(long_name = "Evaporation", units = "mm/day", scale = 0.1),
  "L1-GBWP-A" = list(long_name = "Gross Biomass Water Productivity", units = "kg/m\u00b3", scale = 0.001),
  "L1-I-A" = list(long_name = "Interception", units = "mm/year", scale = 0.1),
  "L1-I-D" = list(long_name = "Interception", units = "mm/day", scale = 0.1),
  "L1-NBWP-A" = list(long_name = "Net Biomass Water Productivity", units = "kg/m\u00b3", scale = 0.001),
  "L1-NPP-D" = list(long_name = "Net Primary Production", units = "gC/m\u00b2/day", scale = 0.001),
  "L1-NPP-M" = list(long_name = "Net Primary Production", units = "gC/m\u00b2/month", scale = 0.001),
  "L1-PCP-A" = list(long_name = "Precipitation", units = "mm/year", scale = 0.1),
  "L1-PCP-D" = list(long_name = "Precipitation", units = "mm/day", scale = 0.1),
  "L1-PCP-E" = list(long_name = "Precipitation", units = "mm/day", scale = 0.1),
  "L1-PCP-M" = list(long_name = "Precipitation", units = "mm/month", scale = 0.1),
  "L2-AETI-A" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/year", scale = 0.1),
  "L2-AETI-D" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/day", scale = 0.1),
  "L2-AETI-M" = list(long_name = "Actual EvapoTranspiration and Interception", units = "mm/month", scale = 0.1),
  "L2-E-A" = list(long_name = "Evaporation", units = "mm/year", scale = 0.1),
  "L2-E-D" = list(long_name = "Evaporation", units = "mm/day", scale = 0.1),
  "L2-GBWP-A" = list(long_name = "Gross Biomass Water Productivity", units = "kg/m\u00b3", scale = 0.001),
  "L2-I-A" = list(long_name = "Interception", units = "mm/year", scale = 0.1),
  "L2-I-D" = list(long_name = "Interception", units = "mm/day", scale = 0.1),
  "L2-NBWP-A" = list(long_name = "Net Biomass Water Productivity", units = "kg/m\u00b3", scale = 0.001),
  "L2-NPP-D" = list(long_name = "Net Primary Production", units = "gC/m\u00b2/day", scale = 0.001),
  "L2-NPP-M" = list(long_name = "Net Primary Production", units = "gC/m\u00b2/month", scale = 0.001),
  "L2-T-A" = list(long_name = "Transpiration", units = "mm/year", scale = 0.1),
  "L2-T-D" = list(long_name = "Transpiration", units = "mm/day", scale = 0.1)
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
  "AGERA5-ET0-E" = list(long_name = "Reference Evapotranspiration", units = "mm/day", scale = 1.0),
  "AGERA5-ET0-D" = list(long_name = "Reference Evapotranspiration", units = "mm/dekad", scale = 1.0),
  "AGERA5-ET0-M" = list(long_name = "Reference Evapotranspiration", units = "mm/month", scale = 1.0),
  "AGERA5-ET0-A" = list(long_name = "Reference Evapotranspiration", units = "mm/year", scale = 1.0),
  "AGERA5-TMIN-E" = list(long_name = "Minimum Air Temperature (2m)", units = "K", scale = 1.0),
  "AGERA5-TMAX-E" = list(long_name = "Maximum Air Temperature (2m)", units = "K", scale = 1.0),
  "AGERA5-SRF-E" = list(long_name = "Solar Radiation", units = "J/m2/day", scale = 1.0),
  "AGERA5-WS-E" = list(long_name = "Wind Speed", units = "m/s", scale = 1.0),
  "AGERA5-PF-E" = list(long_name = "Precipitation", units = "mm/day", scale = 1.0),
  "AGERA5-PF-D" = list(long_name = "Precipitation", units = "mm/dekad", scale = 1.0),
  "AGERA5-PF-M" = list(long_name = "Precipitation", units = "mm/month", scale = 1.0),
  "AGERA5-PF-A" = list(long_name = "Precipitation", units = "mm/year", scale = 1.0)
)

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

  # 2. Dynamic fetch from API
  message("Variable '", variable, "' not in static list. Fetching metadata from API...")

  parts <- strsplit(variable, "-")[[1]]
  if (length(parts) < 2) {
    warning("Invalid variable format: ", variable, call. = FALSE)
    return(NULL)
  }

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

  url <- paste0(base_url, "/", variable)

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
#' for all common WaPOR (L1, L2) and AgERA5 variables.
#'
#' @export
#'
#' @importFrom memoise memoise
#'
#' @examples
#' # Get metadata for a WaPOR variable
#' meta <- get_variable_metadata("L1-AETI-D")
#' meta$long_name
#' # [1] "Actual EvapoTranspiration and Interception"
#' meta$units
#' # [1] "mm/day"
#'
#' # Get metadata for an AgERA5 variable
#' meta <- get_variable_metadata("AGERA5-ET0-E")
#' meta$units
#' # [1] "mm/day"
#'
#' \dontrun{
#' # Dynamic fetch for L3 or unknown variables
#' meta <- get_variable_metadata("L3-AETI-D")
#' }
get_variable_metadata <- memoise::memoise(get_variable_metadata_internal)
