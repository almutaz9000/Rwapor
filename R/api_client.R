#' Collect responses from GISMGR API
#'
#' @param url The URL to fetch
#' @param info Fields to extracting from items
#' @return List of items
#' @importFrom httr2 request req_perform resp_body_json
#' @importFrom purrr map
#' @noRd
collect_responses <- function(url, info = "downloadUrl") {
  all_items <- list()
  next_url <- url
  
  while (!is.null(next_url)) {
    resp <- httr2::request(next_url) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    
    data <- resp$response
    
    if (!is.null(data$items)) {
      items <- data$items
      if (!is.null(info)) {
        # Extract specific fields
        extracted <- purrr::map(items, function(x) {
          if (length(info) == 1) return(x[[info]])
          x[info]
        })
        all_items <- c(all_items, extracted)
      } else {
        all_items <- c(all_items, items)
      }
    }
    
    # Check for next link
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

#' Generate URLs for WaPOR resource
#'
#' @param variable Variable name (e.g., "L1-AETI-D")
#' @param l3_region L3 region code if applicable
#' @param period (Optional) c(start_date, end_date)
#' @return Character vector of URLs
#' @export
wapor_generate_urls <- function(variable, l3_region = NULL, period = NULL) {
  parts <- strsplit(variable, "-")[[1]]
  level <- parts[1]
  
  if (level %in% c("L1", "L2")) {
    base_url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets"
  } else if (level == "L3") {
    base_url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets"
  } else if (level == "AGERA5") {
    names_part <- "C3S" # check this
    base_url <- "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/C3S/mapsets"
  } else {
    stop("Invalid level: ", level)
  }
  
  url <- paste0(base_url, "/", variable, "/rasters?filter=")
  
  if (!is.null(l3_region)) {
    url <- paste0(url, "code:CONTAINS:", l3_region, ";")
  }
  
  if (!is.null(period)) {
    # Period should be formatted YYYY-MM-DD
    url <- paste0(url, "time:OVERLAPS:", period[1], ":", period[2], ";")
  }
  
  urls <- collect_responses(url, info = "downloadUrl")
  return(sort(unlist(urls)))
}
