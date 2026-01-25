#' WaPOR Variable Descriptions
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

#' AGERA5 Variable Descriptions
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

#' Get Variable Metadata (Static + Dynamic) - Internal
#'
#' @param variable Variable code (e.g. "L1-AETI-D")
#' @return List with long_name, units, scale
#' @importFrom httr2 request req_perform resp_body_json
#' @keywords internal
get_variable_metadata_internal <- function(variable) {
  # 1. Try metadata from static lists
  if (variable %in% names(WAPOR3_VARS)) return(WAPOR3_VARS[[variable]])
  if (variable %in% names(AGERA5_VARS)) return(AGERA5_VARS[[variable]])
  
  # 2. Dynamic Fetch from API
  message("Variable '", variable, "' not in static list. Fetching metadata from API...")
  
  parts <- strsplit(variable, "-")[[1]]
  level <- parts[1]
  
  if (level %in% c("L1", "L2")) {
    base_url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets"
  } else if (level == "L3") {
    base_url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets"
  } else if (level == "AGERA5") {
    base_url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/C3S/mapsets"
  } else {
    warning("Unknown level for variable: ", variable)
    return(NULL)
  }
  
  url <- paste0(base_url, "/", variable)
  
  tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    
    data <- resp$response
    
    # Extract metadata
    meta <- list(
      long_name = if(!is.null(data$measureCaption)) data$measureCaption else "Unknown",
      units = if(!is.null(data$measureUnit)) data$measureUnit else "unknown",
      scale = if(!is.null(data$scale)) as.numeric(data$scale) else 1.0
    )
    
    return(meta)
    
  }, error = function(e) {
    warning("Failed to fetch metadata for ", variable, ": ", e$message)
    return(NULL)
  })
}

#' Get Variable Metadata (Static + Dynamic) - Memoised
#'
#' @param variable Variable code (e.g. "L1-AETI-D")
#' @return List with long_name, units, scale
#' @importFrom memoise memoise
#' @export
get_variable_metadata <- memoise::memoise(get_variable_metadata_internal)
