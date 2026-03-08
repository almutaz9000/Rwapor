#' Parse Region Argument
#'
#' Parses various region input formats into a standardized structure
#' for use in other package functions.
#'
#' @param region One of:
#'   * Character path to a vector file (shapefile, GeoJSON, GeoPackage, etc.)
#'   * Character L3 region code (3 uppercase letters, e.g., "AWA")
#'   * Numeric vector of length 4 representing bounding box: `c(xmin, ymin, xmax, ymax)` in WGS84 (EPSG:4326)
#'
#' @return A list with components:
#'   * `type`: One of "l3_code", "vector", or "bbox"
#'   * `value`: The parsed region object (character code, sf object, or st_bbox)
#'
#' @export
#'
#' @importFrom sf st_read st_bbox st_crs st_transform
#'
#' @examples
#' # Parse a bounding box (xmin, ymin, xmax, ymax)
#' region_info <- parse_region(c(35.0, 33.0, 36.0, 34.0))
#' region_info$type
#' # [1] "bbox"
#'
#' # Parse an L3 region code
#' region_info <- parse_region("AWA")
#' region_info$type
#' # [1] "l3_code"
#'
#' \dontrun{
#' # Parse a shapefile
#' region_info <- parse_region("path/to/region.shp")
#' region_info$type
#' # [1] "vector"
#' }
parse_region <- function(region) {
  if (is.null(region)) {
    stop("'region' cannot be NULL", call. = FALSE)
  }

  if (inherits(region, c("sf", "sfc", "Spatial"))) {
    if (inherits(region, "Spatial")) {
      region <- sf::st_as_sf(region)
    }
    if (nrow(region) == 0) {
      stop("Vector object contains no features", call. = FALSE)
    }
    return(list(type = "vector", value = region))
  }

  if (is.character(region)) {
    if (length(region) != 1) {
      stop("'region' must be a single character string when providing a file path or L3 code", call. = FALSE)
    }

    # Check if it's an L3 code (3 uppercase letters)
    if (nchar(region) == 3 && toupper(region) == region && grepl("^[A-Z]{3}$", region)) {
      return(list(type = "l3_code", value = region))
    } else if (file.exists(region)) {
      # Vector file
      vect <- tryCatch({
        sf::st_read(region, quiet = TRUE)
      }, error = function(e) {
        stop(
          sprintf("Failed to read vector file '%s': %s", region, e$message),
          call. = FALSE
        )
      })

      if (nrow(vect) == 0) {
        stop(sprintf("Vector file '%s' contains no features", region), call. = FALSE)
      }

      return(list(type = "vector", value = vect))
    } else {
      stop(
        sprintf("Region '%s' is neither a valid file path nor a 3-letter L3 code", region),
        call. = FALSE
      )
    }
  } else if (is.numeric(region)) {
    if (length(region) != 4) {
      stop("Numeric 'region' must have exactly 4 elements: c(xmin, ymin, xmax, ymax)", call. = FALSE)
    }

    # Validate bounding box values
    xmin <- region[1]
    ymin <- region[2]
    xmax <- region[3]
    ymax <- region[4]

    if (xmin >= xmax) {
      stop("Invalid bounding box: xmin must be less than xmax", call. = FALSE)
    }
    if (ymin >= ymax) {
      stop("Invalid bounding box: ymin must be less than ymax", call. = FALSE)
    }
    if (xmin < -180 || xmax > 180) {
      stop("Invalid bounding box: longitude must be between -180 and 180", call. = FALSE)
    }
    if (ymin < -90 || ymax > 90) {
      stop("Invalid bounding box: latitude must be between -90 and 90", call. = FALSE)
    }

    bb <- sf::st_bbox(c(xmin = xmin, ymin = ymin, xmax = xmax, ymax = ymax), crs = 4326)
    return(list(type = "bbox", value = bb))
  } else {
    stop(
      sprintf("Invalid 'region' type '%s'. Expected character (file path or L3 code) or numeric (bounding box)", class(region)[1]),
      call. = FALSE
    )
  }
}

#' Calculate Conversion Factor for Temporal Units
#'
#' Internal helper function to calculate the conversion factor between
#' different temporal units.
#'
#' @param source_time Source temporal unit ("day", "dekad", "month", "year")
#' @param target_unit Target temporal unit ("day", "dekad", "month", "year")
#' @param num_days Number of days in the source period
#' @param days_in_month Number of days in the month
#'
#' @return Numeric conversion factor
#'
#' @keywords internal
#' @noRd
calculate_conversion_factor <- function(source_time, target_unit, num_days, days_in_month) {
  if (source_time == target_unit) {
    return(1)
  }

  # Conversion matrix logic
  factor <- switch(
    source_time,
    "day" = switch(
      target_unit,
      "day" = 1,
      "dekad" = num_days,
      "month" = days_in_month,
      "year" = 365,
      stop(sprintf("Unknown target unit: %s", target_unit), call. = FALSE)
    ),
    "dekad" = switch(
      target_unit,
      "day" = 1 / num_days,
      "dekad" = 1,
      "month" = 3,
      "year" = 36,
      stop(sprintf("Unknown target unit: %s", target_unit), call. = FALSE)
    ),
    "month" = switch(
      target_unit,
      "day" = 1 / days_in_month,
      "dekad" = 1 / 3,
      "month" = 1,
      "year" = 12,
      stop(sprintf("Unknown target unit: %s", target_unit), call. = FALSE)
    ),
    "year" = switch(
      target_unit,
      "day" = 1 / 365,
      "dekad" = 1 / 36,
      "month" = 1 / 12,
      "year" = 1,
      stop(sprintf("Unknown target unit: %s", target_unit), call. = FALSE)
    ),
    stop(sprintf("Unknown source unit: %s", source_time), call. = FALSE)
  )

  return(factor)
}

#' Extract Date Information from URL
#'
#' Parses WaPOR or AgERA5 raster filenames to extract date information
#' including start date, end date, and period duration.
#'
#' @param url Character. Resource URL or filename containing date information.
#' @param tres Character. Temporal resolution code:
#'   * "D" = Dekadal (10-day periods)
#'   * "M" = Monthly
#'   * "A" = Annual
#'   * "E" = Daily
#'
#' @return A list with components:
#'   * `start_date`: Character date string in "YYYY-MM-DD" format
#'   * `end_date`: Character date string in "YYYY-MM-DD" format
#'   * `number_of_days`: Integer number of days in the period
#'
#' @export
#'
#' @importFrom lubridate days_in_month ymd
#'
#' @examples
#' # Parse dekadal data URL (WaPOR format: WAPOR-3.L1-AETI-D.YYYY-MM-DX.tif)
#' date_info <- get_date_info(
#'   "https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-01-D1.tif",
#'   tres = "D"
#' )
#' date_info$start_date
#' # [1] "2023-01-01"
#' date_info$number_of_days
#' # [1] 10
#'
#' # Parse monthly data URL (WaPOR format: WAPOR-3.L1-AETI-M.YYYY-MM.tif)
#' date_info <- get_date_info(
#'   "https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-M/WAPOR-3.L1-AETI-M.2023-06.tif",
#'   tres = "M"
#' )
#' date_info$start_date
#' # [1] "2023-06-01"
get_date_info <- function(url, tres) {
  # Input validation
  if (!is.character(url) || length(url) != 1) {
    stop("'url' must be a single character string", call. = FALSE)
  }
  if (!is.character(tres) || length(tres) != 1) {
    stop("'tres' must be a single character string", call. = FALSE)
  }
  if (!tres %in% c("D", "M", "A", "E")) {
    stop(
      sprintf("Invalid temporal resolution '%s'. Must be one of: D, M, A, E", tres),
      call. = FALSE
    )
  }

  filename <- basename(url)
  base <- tools::file_path_sans_ext(filename)

  # WaPOR URL format: WAPOR-3.L1-AETI-D.2018-01-D1.tif
  # The date component is the last dot-separated part before extension
  # Split by "." first to isolate the date component
  dot_parts <- strsplit(base, "\\.")[[1]]
  date_component <- dot_parts[length(dot_parts)]

  # Now split the date component by "-"
  parts <- strsplit(date_component, "-")[[1]]

  if (tres == "D") {
    # Dekadal format: YYYY-MM-DX (e.g., 2018-01-D1)
    if (length(parts) < 3) {
      stop(sprintf("Cannot parse date from URL for Dekadal data: %s", filename), call. = FALSE)
    }
    year_str <- parts[1]
    month_str <- parts[2]
    dekad_str <- parts[3]

    dekad_map <- list("D1" = "01", "D2" = "11", "D3" = "21",
                      "1" = "01", "2" = "11", "3" = "21")

    if (!dekad_str %in% names(dekad_map)) {
      stop(sprintf("Unknown dekad format: %s", dekad_str), call. = FALSE)
    }

    start_day <- dekad_map[[dekad_str]]
    start_date <- paste(year_str, month_str, start_day, sep = "-")

    # Calculate end date based on dekad
    if (dekad_str %in% c("D1", "1")) {
      end_date <- paste(year_str, month_str, "10", sep = "-")
    } else if (dekad_str %in% c("D2", "2")) {
      end_date <- paste(year_str, month_str, "20", sep = "-")
    } else {
      # Third dekad ends on last day of month
      date_obj <- lubridate::ymd(start_date)
      end_day <- lubridate::days_in_month(date_obj)
      end_date <- paste(year_str, month_str, end_day, sep = "-")
    }

  } else if (tres == "M") {
    # Monthly format: YYYY-MM (e.g., 2018-01)
    if (length(parts) < 2) {
      stop(sprintf("Cannot parse date from URL for Monthly data: %s", filename), call. = FALSE)
    }
    year_str <- parts[1]
    month_str <- parts[2]
    start_date <- paste(year_str, month_str, "01", sep = "-")
    date_obj <- lubridate::ymd(start_date)
    end_date <- paste(year_str, month_str, lubridate::days_in_month(date_obj), sep = "-")

  } else if (tres == "A") {
    # Annual format: YYYY (e.g., 2018)
    year_str <- parts[1]
    start_date <- paste(year_str, "01", "01", sep = "-")
    end_date <- paste(year_str, "12", "31", sep = "-")

  } else if (tres == "E") {
    # Daily format: YYYY-MM-DD (e.g., 2018-01-15)
    if (length(parts) < 3) {
      stop(sprintf("Cannot parse date from URL for Daily data: %s", filename), call. = FALSE)
    }
    year_str <- parts[1]
    month_str <- parts[2]
    day_str <- parts[3]
    start_date <- paste(year_str, month_str, day_str, sep = "-")
    end_date <- start_date
  }

  # Validate parsed dates
  tryCatch({
    start_dt <- lubridate::ymd(start_date)
    end_dt <- lubridate::ymd(end_date)
  }, error = function(e) {
    stop(sprintf("Failed to parse date from URL '%s': invalid date components", url), call. = FALSE)
  })

  ndays <- as.numeric(difftime(lubridate::ymd(end_date), lubridate::ymd(start_date), units = "days")) + 1

  return(list(
    start_date = start_date,
    end_date = end_date,
    number_of_days = ndays
  ))
}


#' Safe Terra Projection Wrapper
#'
#' Eliminates PROJ database collisions on some Windows environments
#' when projecting between WGS84 and UTM.
#'
#' @param x SpatVector or SpatRaster
#' @param y target CRS
#' @return SpatVector or SpatRaster
#' @keywords internal
#' @noRd
safe_project <- function(x, y) {
  y_crs <- y
  if (is.character(y) && grepl("ID\\[\"EPSG\"", y)) {
    m <- regmatches(y, regexpr("ID\\[\"EPSG\",\\s*([0-9]+)\\]\\]$", y))
    if (length(m) > 0) {
      epsg_num <- gsub("[^0-9]", "", m)
      y_crs <- as.integer(epsg_num)
    }
  }

  if (inherits(x, "SpatVector")) {
    x_sf <- sf::st_as_sf(x)
  } else {
    x_sf <- x
  }
  
  res_sf <- tryCatch(suppressWarnings(sf::st_transform(x_sf, y_crs)), error=function(e) {
      stop(sprintf("safe_project sf projection failed: %s", e$message), call. = FALSE)
  })
  
  if (inherits(x, "SpatVector")) {
    return(suppressWarnings(terra::vect(res_sf)))
  }
  return(res_sf)
}

#' Guess L3 Region from Spatial Intersection
#'
#' @param variable Character. The WaPOR variable name (e.g., L3-AETI-D)
#' @param reg_info List from parse_region()
#' @param period Date period vector
#' @return Character vector of intersecting L3 regions, or NULL
#' @importFrom terra rast ext as.polygons is.related crs project vect
#' @keywords internal
#' @noRd
guess_l3_region <- function(variable, reg_info, period) {
  # Temporarily suppress the warning from wapor_generate_urls
  urls <- suppressWarnings(wapor_generate_urls(variable, period = c(period[1], period[1])))
  
  if (length(urls) == 0) {
    urls <- suppressWarnings(wapor_generate_urls(variable, period = period))
  }
  
  if (length(urls) == 0) return(NULL)
  
  extracted_codes <- character()
  unique_urls <- character()
  
  # Extract distinct L3 codes from the filenames
  for (u in urls) {
    fname <- tools::file_path_sans_ext(basename(u))
    parts <- strsplit(fname, "\\.")[[1]]
    if (length(parts) >= 4) {
      code <- parts[3]
      if (!code %in% extracted_codes && nchar(code) == 3 && toupper(code) == code) {
        extracted_codes <- c(extracted_codes, code)
        unique_urls <- c(unique_urls, u)
      }
    }
  }
  
  if (length(unique_urls) == 0) return(NULL)
  
  message("Dynamically scanning L3 regions for spatial intersection...")
  intersecting_codes <- character()
  
  for (i in seq_along(unique_urls)) {
    u <- unique_urls[i]
    code <- extracted_codes[i]
    vsi_url <- paste0("/vsicurl/", u)
    
    r <- tryCatch(suppressWarnings(terra::rast(vsi_url)), error = function(e) NULL)
    if (is.null(r)) next
    
    r_ext <- terra::ext(r)
    r_poly <- terra::as.polygons(r_ext, crs=terra::crs(r))
    r_poly_4326 <- safe_project(r_poly, 4326)
    
    intersects <- FALSE
    if (reg_info$type == "vector") {
      v <- suppressWarnings(terra::vect(reg_info$value))
      v_ext <- terra::ext(v)
      v_bb_poly <- terra::as.polygons(v_ext, crs=terra::crs(v))
      v_bb_4326 <- safe_project(v_bb_poly, 4326)
      
      intersects <- any(suppressWarnings(terra::is.related(r_poly_4326, v_bb_4326, "intersects")))
    } else if (reg_info$type == "bbox") {
      bbox <- reg_info$value
      bb_ext <- terra::ext(bbox[c("xmin", "xmax", "ymin", "ymax")])
      bb_poly <- terra::as.polygons(bb_ext, crs="EPSG:4326")
      
      intersects <- any(suppressWarnings(terra::is.related(r_poly_4326, bb_poly, "intersects")))
    }
    
    if (intersects) {
      intersecting_codes <- c(intersecting_codes, code)
    }
  }
  
  if (length(intersecting_codes) > 0) {
    message(sprintf("Found intersecting L3 regions: %s", paste(intersecting_codes, collapse = ", ")))
    return(intersecting_codes)
  }
  
  return(NULL)
}


#' Crop (and Optionally Mask) a Raster to a Parsed Region
#'
#' Internal helper that handles CRS alignment, cropping, and optional masking
#' for vector or bounding-box regions. Eliminates duplicated crop/mask logic
#' across wapor_map, wapor_ts, and seasonal_download.
#'
#' @param r SpatRaster to crop.
#' @param reg_info List from \code{parse_region()} with \code{$type} and \code{$value}.
#' @param do_mask Logical. If TRUE, also mask to vector geometry (not just crop).
#' @return Cropped (and optionally masked) SpatRaster.
#' @keywords internal
#' @noRd
crop_to_region <- function(r, reg_info, do_mask = FALSE) {
  if (reg_info$type == "vector") {
    vect_data <- reg_info$value
    vect_crs <- sf::st_crs(vect_data)
    if (!is.na(vect_crs) && vect_crs$epsg != 4326) {
      vect_data <- sf::st_transform(vect_data, 4326)
    }
    v <- suppressWarnings(terra::vect(vect_data))
    if (terra::crs(v) != terra::crs(r)) {
      v <- safe_project(v, terra::crs(r))
    }
    r <- suppressWarnings(terra::crop(r, v))
    if (do_mask) {
      r <- suppressWarnings(terra::mask(r, v))
    }
  } else if (reg_info$type == "bbox") {
    ext <- terra::ext(reg_info$value[c("xmin", "xmax", "ymin", "ymax")])
    bb_poly <- terra::as.polygons(ext, crs = "EPSG:4326")
    if (terra::crs(bb_poly) != terra::crs(r)) {
      bb_poly <- safe_project(bb_poly, terra::crs(r))
    }
    r <- suppressWarnings(terra::crop(r, bb_poly))
  }
  r
}
