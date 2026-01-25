#' Parse Region Argument
#'
#' @param region Path to vector file, bounding box (numeric vector of 4), or L3 code
#' @return List with type and object
#' @importFrom sf st_read st_bbox st_crs st_transform
#' @export
parse_region <- function(region) {
  if (is.character(region)) {
    if (nchar(region) == 3 && toupper(region) == region) {
      # L3 Code
      return(list(type = "l3_code", value = region))
    } else if (file.exists(region)) {
      # Vector file
      vect <- sf::st_read(region, quiet = TRUE)
      return(list(type = "vector", value = vect))
    } else {
      stop("Region is string but not a valid file or L3 code.")
    }
  } else if (is.numeric(region) && length(region) == 4) {
    # Bounding box: xmin, ymin, xmax, ymax
    # Create sf bbox
    bb <- sf::st_bbox(c(xmin = region[1], ymin = region[2], xmax = region[3], ymax = region[4]), crs = 4326)
    return(list(type = "bbox", value = bb))
  } else {
    stop("Invalid region format.")
  }
}

#' Extract Date Information from URL
#'
#' @param url Resource URL
#' @param tres Temporal resolution (D, M, A, E)
#' @return List with start_date, end_date, number_of_days
#' @importFrom lubridate days_in_month ymd
#' @export
get_date_info <- function(url, tres) {
  filename <- basename(url)
  # Expected format ..._YYYY-MM-DD.tif or similar, but Python split looks like:
  # ...split(".")[-2].split("-")
  # Let's try to extract based on typical WaPOR URL patterns
  # e.g. L1_AETI_D_2021-01-D1.tif (hypothetically)
  # Python code: year, month, dekad = os.path.split(url)[-1].split(".")[-2].split("-")
  
  # Remove extension
  base <- tools::file_path_sans_ext(filename)
  parts <- strsplit(base, "-")[[1]]
  
  if (tres == "D") {
    # Expected: ...-YYYY-MM-DX
    if (length(parts) < 3) stop("Cannot parse date from URL for Dekadal data")
    dekad_str <- parts[length(parts)]
    month_str <- parts[length(parts)-1]
    year_str <- parts[length(parts)-2]
    
    dekad_map <- list("D1" = "01", "D2" = "11", "D3" = "21", 
                      "1" = "01", "2" = "11", "3" = "21")
    
    if (!dekad_str %in% names(dekad_map)) {
        # Fallback for simple numbering if possible or error
        # Some URLs might differ. Let's assume standard WaPOR format.
        stop(paste("Unknown dekad format:", dekad_str))
    }
    
    start_day <- dekad_map[[dekad_str]]
    start_date <- paste(year_str, month_str, start_day, sep = "-")
    
    # Calculate end date
    if (dekad_str %in% c("D1", "1")) {
      end_day <- "10"
      end_date <- paste(year_str, month_str, end_day, sep = "-")
    } else if (dekad_str %in% c("D2", "2")) {
      end_day <- "20"
      end_date <- paste(year_str, month_str, end_day, sep = "-")
    } else {
      # End of month
      date_obj <- lubridate::ymd(start_date)
      end_day <- lubridate::days_in_month(date_obj)
      end_date <- paste(year_str, month_str, end_day, sep = "-")
    }
    
  } else if (tres == "M") {
    # ...-YYYY-MM
    month_str <- parts[length(parts)]
    year_str <- parts[length(parts)-1]
    start_date <- paste(year_str, month_str, "01", sep = "-")
    date_obj <- lubridate::ymd(start_date)
    end_date <- paste(year_str, month_str, lubridate::days_in_month(date_obj), sep = "-")
    
  } else if (tres == "A") {
    # ...-YYYY
    year_str <- parts[length(parts)]
    start_date <- paste(year_str, "01", "01", sep = "-")
    end_date <- paste(year_str, "12", "31", sep = "-")
    
  } else if (tres == "E") {
    # ...-YYYY-MM-DD
    day_str <- parts[length(parts)]
    month_str <- parts[length(parts)-1]
    year_str <- parts[length(parts)-2]
    start_date <- paste(year_str, month_str, day_str, sep = "-")
    end_date <- start_date
  } else {
    stop("Unknown temporal resolution")
  }
  
  ndays <- as.numeric(difftime(lubridate::ymd(end_date), lubridate::ymd(start_date), units = "days")) + 1
  
  return(list(
    start_date = start_date,
    end_date = end_date,
    number_of_days = ndays
  ))
}

#' Download URLs in Parallel
#'
#' @param urls List of URLs to download
#' @param folder Output directory
#' @return Vector of local file paths
#' @importFrom furrr future_map_chr
#' @importFrom progressr with_progress progressor
#' @importFrom httr2 request req_perform
#' @export
download_urls_parallel <- function(urls, folder) {
  if (!dir.exists(folder)) dir.create(folder, recursive = TRUE)
  
  progressr::with_progress({
    p <- progressr::progressor(steps = length(urls))
    
    dl_one <- function(url) {
        fn <- file.path(folder, basename(url))
        if (!file.exists(fn)) {
            tryCatch({
                req <- httr2::request(url)
                httr2::req_perform(req, path = fn)
            }, error = function(e) {
                warning('Failed to download: ', url)
            })
        }
        p()
        return(fn)
    }
    
    local_paths <- furrr::future_map_chr(urls, dl_one)
  })
  
  return(file.path(folder, basename(urls)))
}

