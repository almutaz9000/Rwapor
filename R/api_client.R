#' Collect Responses from GISMGR API with Pagination
#'
#' Internal function to paginate through FAO GISMGR API responses
#' and collect all items across multiple pages.
#'
#' @param url The base URL to fetch
#' @param info Fields to extract from items (default: "downloadUrl")
#'
#' @return List of extracted items from all pages
#'
#' @importFrom httr2 request req_perform resp_body_json req_timeout req_retry
#' @importFrom purrr map
#' @keywords internal
#' @noRd
collect_responses <- function(url, info = "downloadUrl") {
  if (!is.character(url) || length(url) != 1 || nchar(url) == 0) {
    stop("'url' must be a non-empty character string", call. = FALSE)
  }

  all_items <- list()
  next_url  <- url

  while (!is.null(next_url)) {
    resp <- tryCatch({
      httr2::request(next_url) |>
        httr2::req_timeout(60) |>
        httr2::req_retry(max_tries = 3, backoff = ~ 2) |>
        httr2::req_perform() |>
        httr2::resp_body_json()
    }, error = function(e) {
      stop(
        sprintf("API request failed for URL '%s': %s", next_url, e$message),
        call. = FALSE
      )
    })

    data <- resp$response

    if (is.null(data)) {
      warning("Empty response from API", call. = FALSE)
      break
    }

    if (!is.null(data$items)) {
      items <- data$items
      if (!is.null(info)) {
        extracted <- purrr::map(items, function(x) {
          if (length(info) == 1) return(x[[info]])
          x[info]
        })
        all_items <- c(all_items, extracted)
      } else {
        all_items <- c(all_items, items)
      }
    }

    # Check for next link (pagination)
    links <- data$links
    next_link <- NULL
    if (!is.null(links)) {
      for (link in links) {
        if (link$rel == "next") {
          next_link <- link$href
          break
        }
      }
    }
    next_url <- next_link
  }

  return(all_items)
}

wapor_generate_urls_internal <- function(variable, l3_region = NULL, period = NULL) {
  # Input validation
  if (!is.character(variable) || length(variable) != 1) {
    stop("'variable' must be a single character string", call. = FALSE)
  }

  parts <- strsplit(variable, "-")[[1]]
  if (length(parts) < 2) {
    stop(
      sprintf("Invalid variable format '%s'. Expected format: 'LEVEL-VAR-TRES' (e.g., 'L1-AETI-D')", variable),
      call. = FALSE
    )
  }

  level <- parts[1]

  # Validate period format if provided
  if (!is.null(period)) {
    if (!is.character(period) || length(period) != 2) {
      stop("'period' must be a character vector of length 2: c(start_date, end_date)", call. = FALSE)
    }
    # Validate date format
    tryCatch({
      as.Date(period[1])
      as.Date(period[2])
    }, error = function(e) {
      stop("'period' dates must be in 'YYYY-MM-DD' format", call. = FALSE)
    })
    if (as.Date(period[1]) > as.Date(period[2])) {
      stop("Start date must be before or equal to end date", call. = FALSE)
    }
  }

  # Determine base URL based on level
  if (level %in% c("L1", "L2")) {
    base_url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets"
    mapset_id <- variable
    
    # Fallback to L1 for variables that don't exist at L2 (RET, PCP)
    if (level == "L2" && grepl("-(RET|PCP)-", variable)) {
      mapset_id <- sub("^L2-", "L1-", variable)
    }
  } else if (level == "L3") {
    base_url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets"
    mapset_id <- variable
    
    # Fallback to L1 for variables that don't exist at L3 (RET, PCP)
    if (grepl("-(RET|PCP)-", variable)) {
      base_url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets"
      mapset_id <- sub("^L3-", "L1-", variable)
    }
    if (is.null(l3_region)) {
      warning("L3 variable specified without l3_region - results may include all regions", call. = FALSE)
    }
  } else if (level == "AGERA5") {
    base_url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/C3S/mapsets"
    # Special case: AgERA5 daily variables don't have -E suffix in mapset ID
    mapset_id <- if (grepl("-E$", variable)) sub("-E$", "", variable) else variable
  } else {
    stop(
      sprintf("Invalid level '%s'. Must be one of: L1, L2, L3, AGERA5", level),
      call. = FALSE
    )
  }

  url <- paste0(base_url, "/", mapset_id, "/rasters?filter=")

  if (!is.null(l3_region) && level == "L3") {
    if (!is.character(l3_region) || nchar(l3_region) == 0) {
      stop("'l3_region' must be a non-empty character string", call. = FALSE)
    }
    url <- paste0(url, "code:CONTAINS:", l3_region, ";")
  }

  if (!is.null(period)) {
    url <- paste0(url, "time:OVERLAPS:", period[1], ":", period[2], ";")
  }

  urls <- collect_responses(url, info = "downloadUrl")

  if (length(urls) == 0) {
    warning(
      sprintf("No data found for variable '%s' with the specified parameters", variable),
      call. = FALSE
    )
    return(character(0))
  }

  urls <- unlist(urls)

  # Filter by L3 region if specified (ensures strict matching)
  if (!is.null(l3_region) && level == "L3") {
    urls <- grep(paste0("\\.", l3_region, "\\."), urls, value = TRUE)
  }

  return(sort(as.character(urls)))
}

#' @title Generate URLs for WaPOR/AgERA5 Resources
#' @name wapor_generate_urls
#' @description
#' Generates download URLs for WaPOR or AgERA5 raster data from the
#' FAO GISMGR API based on variable name, region, and time period.
#'
#' @param variable Character. Variable name following WaPOR/AgERA5 naming
#'   convention (e.g., "L1-AETI-D", "L2-NPP-M", "AGERA5-ET0-E").
#'   The format is `{Level}-{Variable}-{TemporalResolution}` where:
#'   * Level: L1, L2, L3 (WaPOR) or AGERA5
#'   * Variable: AETI, E, I, NPP, PCP, T, GBWP, NBWP, ET0, TMIN, TMAX, etc.
#'   * Temporal: D (dekadal), M (monthly), A (annual), E (daily)
#' @param l3_region Character. Optional L3 region code for Level 3 data
#'   (e.g., "AWA" for Awash Basin). Only applicable for L3 variables.
#' @param period Character vector of length 2. Optional date range as
#'   `c(start_date, end_date)` in "YYYY-MM-DD" format.
#'
#' @return Character vector of download URLs, sorted chronologically.
#'
#' @details
#' Results are cached using memoization so that repeated calls with
#' identical arguments within the same session avoid redundant API requests.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Get URLs for dekadal evapotranspiration in January 2023
#' urls <- wapor_generate_urls(
#'   variable = "L1-AETI-D",
#'   period = c("2023-01-01", "2023-01-31")
#' )
#'
#' # Get URLs for L3 data in Awash Basin
#' urls <- wapor_generate_urls(
#'   variable = "L3-AETI-D",
#'   l3_region = "AWA",
#'   period = c("2023-01-01", "2023-03-31")
#' )
#'
#' # Get AgERA5 reference evapotranspiration
#' urls <- wapor_generate_urls(
#'   variable = "AGERA5-ET0-E",
#'   period = c("2023-06-01", "2023-06-30")
#' )
#' }
wapor_generate_urls <- memoise::memoise(wapor_generate_urls_internal)
