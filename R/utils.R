#' Null-Coalescing Helper
#'
#' @param x Primary value.
#' @param y Fallback value.
#' @return `x` when it is not `NULL`, otherwise `y`.
#' @keywords internal
#' @noRd
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

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
#' region_info <- wapor_parse_region(c(35.0, 33.0, 36.0, 34.0))
#' region_info$type
#' # [1] "bbox"
#'
#' # Parse an L3 region code
#' region_info <- wapor_parse_region("AWA")
#' region_info$type
#' # [1] "l3_code"
#'
#' \dontrun{
#' # Parse a shapefile
#' region_info <- wapor_parse_region("path/to/region.shp")
#' region_info$type
#' # [1] "vector"
#' }
wapor_parse_region <- function(region) {
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
      # Check if it's a raster or vector
      is_raster <- grepl("\\.(tif|tiff|grd|nc)$", region, ignore.case = TRUE)
      
      if (is_raster) {
        # Raster file - extract extent
        r <- tryCatch({
          terra::rast(region)
        }, error = function(e) stop(sprintf("Failed to read raster file '%s': %s", region, e$message), call. = FALSE))
        
        # Get WGS84 bbox
        r_ext <- terra::ext(r)
        r_crs <- terra::crs(r)
        
        if (!nzchar(r_crs)) {
           # Fallback for missing CRS: assume geographic if values look correct
           if (r_ext$xmin >= -180 && r_ext$xmax <= 180 && r_ext$ymin >= -90 && r_ext$ymax <= 90) {
             r_crs <- "EPSG:4326"
           } else {
             stop(sprintf("Raster file '%s' has no CRS and coordinates don't look geographic.", region), call. = FALSE)
           }
        }
        
        p <- terra::as.polygons(r_ext, crs = r_crs)
        # Clear NA attributes to prevent "row names contain missing values" error
        terra::values(p) <- NULL
        p4326 <- wapor_safe_project(p, 4326)
        ext_4326 <- terra::ext(p4326)
        
        # Simple named numeric vector returned as bbox
        bb <- sf::st_bbox(c(xmin = as.numeric(ext_4326$xmin), 
                           ymin = as.numeric(ext_4326$ymin), 
                           xmax = as.numeric(ext_4326$xmax), 
                           ymax = as.numeric(ext_4326$ymax)), crs = 4326)
        
        return(list(type = "bbox", value = bb))
        
      } else {
        # Assume Vector file
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
      }
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
calculate_conversion_factor <- function(source_time, target_unit, num_days, days_in_month, days_in_year = NULL) {
  if (source_time == target_unit) {
    return(rep(1, length(num_days)))
  }

  # Use actual year length when available, otherwise default to 365
  yr_days <- if (!is.null(days_in_year)) days_in_year else rep(365L, length(num_days))

  # Conversion matrix logic
  factor <- switch(
    source_time,
    "day" = switch(
      target_unit,
      "day" = rep(1, length(num_days)),
      "dekad" = num_days,
      "month" = days_in_month,
      "year" = yr_days,
      stop(sprintf("Unknown target unit: %s", target_unit), call. = FALSE)
    ),
    "dekad" = switch(
      target_unit,
      "day" = 1 / num_days,
      "dekad" = rep(1, length(num_days)),
      "month" = rep(3, length(num_days)),
      "year" = yr_days / num_days,
      stop(sprintf("Unknown target unit: %s", target_unit), call. = FALSE)
    ),
    "month" = switch(
      target_unit,
      "day" = 1 / days_in_month,
      "dekad" = rep(1 / 3, length(num_days)),
      "month" = rep(1, length(num_days)),
      "year" = rep(12, length(num_days)),
      stop(sprintf("Unknown target unit: %s", target_unit), call. = FALSE)
    ),
    "year" = switch(
      target_unit,
      "day" = 1 / yr_days,
      "dekad" = num_days / yr_days,
      "month" = rep(1 / 12, length(num_days)),
      "year" = rep(1, length(num_days)),
      stop(sprintf("Unknown target unit: %s", target_unit), call. = FALSE)
    ),
    stop(sprintf("Unknown source unit: %s", source_time), call. = FALSE)
  )

  return(factor)
}

#' Extract the Temporal Unit Encoded in Metadata Units
#'
#' @param units Character scalar such as `"mm/day"` or `"kg/ha"`.
#' @return One of `"day"`, `"dekad"`, `"month"`, `"year"`, or `NULL`.
#' @keywords internal
#' @noRd
extract_temporal_unit <- function(units) {
  if (!is.character(units) || length(units) != 1 || is.na(units)) {
    return(NULL)
  }

  match <- regexec("/(day|dekad|month|year)$", units)
  parts <- regmatches(units, match)[[1]]
  if (length(parts) < 2) {
    return(NULL)
  }

  parts[2]
}

#' Resolve Default Temporal Unit Conversion for Raster Outputs
#'
#' @param variable Character variable code.
#' @param unit_conversion User-supplied conversion or `NULL`.
#' @return Character conversion code.
#' @keywords internal
#' @noRd
resolve_output_unit_conversion <- function(variable, unit_conversion = NULL) {
  if (!is.null(unit_conversion)) {
    return(unit_conversion)
  }

  parts <- strsplit(variable, "-", fixed = TRUE)[[1]]
  tres <- parts[length(parts)]
  meta <- wapor_variable_metadata(variable)
  unit_time <- extract_temporal_unit(meta$units %||% NA_character_)

  if (identical(tres, "D") && identical(unit_time, "day")) {
    return("dekad")
  }

  "none"
}

#' Determine the Seasonal Aggregation Rule for a Variable
#'
#' @param variable Character variable code.
#' @return Either `"weighted_sum"` or `"weighted_mean"`.
#' @keywords internal
#' @noRd
get_seasonal_aggregation_rule <- function(variable) {
  parts <- strsplit(variable, "-", fixed = TRUE)[[1]]
  tres <- parts[length(parts)]
  meta <- wapor_variable_metadata(variable)
  unit_time <- extract_temporal_unit(meta$units %||% NA_character_)

  if (tres %in% c("D", "E") && is.null(unit_time)) {
    return("weighted_mean")
  }

  "weighted_sum"
}

#' Compute Seasonal Multipliers for Planned Raster Slices
#'
#' @param variable Character variable code for the slices being downloaded.
#' @param plan_rows Data frame rows from `wapor_plan_time_slices()`.
#' @param aggregation_rule Seasonal aggregation rule for the requested variable.
#' @return Numeric vector of per-layer multipliers.
#' @keywords internal
#' @noRd
get_seasonal_multiplier_values <- function(variable, plan_rows, aggregation_rule = get_seasonal_aggregation_rule(variable)) {
  if (!is.data.frame(plan_rows) || nrow(plan_rows) == 0) {
    return(numeric(0))
  }

  if (identical(aggregation_rule, "weighted_mean")) {
    return(plan_rows$overlap_days)
  }

  parts <- strsplit(variable, "-", fixed = TRUE)[[1]]
  tres <- parts[length(parts)]
  meta <- wapor_variable_metadata(variable)
  unit_time <- extract_temporal_unit(meta$units %||% NA_character_)

  if (tres %in% c("D", "E") && identical(unit_time, "day")) {
    return(plan_rows$overlap_days)
  }

  plan_rows$weight
}

#' Compute Analysis Multipliers for Time-Slice Rasters
#'
#' @param variable Character variable code for the loaded raster stack.
#' @param period_table Data frame with one row per loaded layer and an `n_days`
#'   column describing each time slice.
#' @return Numeric vector of per-layer multipliers.
#' @keywords internal
#' @noRd
get_analysis_layer_multipliers <- function(variable, period_table) {
  if (!is.data.frame(period_table) || nrow(period_table) == 0) {
    return(numeric(0))
  }

  parts <- strsplit(variable, "-", fixed = TRUE)[[1]]
  tres <- parts[length(parts)]
  meta <- wapor_variable_metadata(variable)
  unit_time <- extract_temporal_unit(meta$units %||% NA_character_)

  if (identical(tres, "D") && identical(unit_time, "day")) {
    return(period_table$n_days)
  }

  rep(1, nrow(period_table))
}

#' Resolve Units for Seasonal Outputs
#'
#' @param variable Character variable code.
#' @param aggregation_rule Seasonal aggregation rule.
#' @return Character units string for the seasonal result.
#' @keywords internal
#' @noRd
get_seasonal_output_units <- function(variable, aggregation_rule = get_seasonal_aggregation_rule(variable)) {
  meta <- wapor_variable_metadata(variable)
  if (is.null(meta) || is.null(meta$units)) {
    return(NULL)
  }

  result_units <- if (identical(aggregation_rule, "weighted_sum")) {
    sub("/(day|dekad|month|year)$", "", meta$units)
  } else {
    meta$units
  }
  
  # Handle temperature conversion (Kelvin to Celsius)
  if (grepl("^AGERA5-(TMIN|TMAX)-", variable, ignore.case = FALSE)) {
    result_units <- sub("^K$", "degC", result_units)
  }
  
  result_units
}

#' Vectorized Extraction of Date Information from URLs
#'
#' Parses multiple WaPOR or AgERA5 raster filenames to extract date information
#' including start date, end_date, and period duration in a single pass.
#'
#' @param urls Character vector. Resource URLs or filenames containing date information.
#' @param tres Character. Temporal resolution code: "D" (Dekadal), "M" (Monthly),
#'   "A" (Annual), "E" (Daily), or "Y" (Annual alias).
#'
#' @return A data.frame with columns:
#'   * `start_date`: Character date string in "YYYY-MM-DD" format
#'   * `end_date`: Character date string in "YYYY-MM-DD" format
#'   * `number_of_days`: Integer number of days in the period
#'   * `raw_date`: The raw date component extracted from the filename
#'
#' @export
#'
#' @importFrom lubridate days_in_month ymd
wapor_parse_dates <- function(urls, tres) {
  if (length(urls) == 0) {
    return(data.frame(
      start_date = character(0),
      end_date = character(0),
      number_of_days = integer(0),
      raw_date = character(0),
      stringsAsFactors = FALSE
    ))
  }

  if (!tres %in% c("D", "M", "A", "E", "Y")) {
    stop(sprintf("Invalid temporal resolution '%s'. Must be one of: D, M, A, E", tres), call. = FALSE)
  }

  filenames <- basename(urls)
  bases <- tools::file_path_sans_ext(filenames)

  # Extract date component (last dot-separated part)
  # This works for both "product.YYYY-MM-DX" and "product.YYYYMMDD"
  # Vectorized sub() is faster than strsplit() + vapply()
  date_components <- sub("^.*\\.", "", bases)

  # Default placeholders
  start_dates <- character(length(urls))
  end_dates   <- character(length(urls))

  if (tres == "D") {
    # Handles: YYYY-MM-DX, YYYY-MM-X, and compact YYYYMMDD
    is_compact <- nchar(date_components) == 8 & grepl("^\\d{8}$", date_components)

    # Compact format (e.g., 20180101)
    if (any(is_compact)) {
      idx <- which(is_compact)
      y <- substr(date_components[idx], 1, 4)
      m <- substr(date_components[idx], 5, 6)
      d_val <- as.integer(substr(date_components[idx], 7, 8))
      start_dates[idx] <- paste(y, m, sprintf("%02d", d_val), sep = "-")

      # Determine dekad for end date calculation
      d1_idx <- idx[d_val <= 10]
      d2_idx <- idx[d_val > 10 & d_val <= 20]
      d3_idx <- idx[d_val > 20]

      if (length(d1_idx)) end_dates[d1_idx] <- paste(substr(start_dates[d1_idx], 1, 7), "10", sep = "-")
      if (length(d2_idx)) end_dates[d2_idx] <- paste(substr(start_dates[d2_idx], 1, 7), "20", sep = "-")
      if (length(d3_idx)) {
        s_obj <- lubridate::ymd(start_dates[d3_idx])
        e_day <- lubridate::days_in_month(s_obj)
        end_dates[d3_idx] <- paste(substr(start_dates[d3_idx], 1, 7), e_day, sep = "-")
      }
    }

    # Standard format (e.g., 2018-01-D1)
    if (any(!is_compact)) {
      idx <- which(!is_compact)
      dash_parts <- strsplit(date_components[idx], "-")
      # Filter for valid parts (must have 3 parts for YYYY-MM-DX)
      # lengths() is a faster vectorized built-in
      valid_idx <- lengths(dash_parts) == 3

      if (any(valid_idx)) {
        v_idx <- idx[valid_idx]
        v_parts <- dash_parts[valid_idx]

        # Matrix transformation is faster than multiple vapply calls
        v_mat <- matrix(unlist(v_parts), ncol = 3, byrow = TRUE)
        y <- v_mat[, 1]
        m <- v_mat[, 2]
        d_str <- v_mat[, 3]

        dekad_map <- c("D1" = "01", "D2" = "11", "D3" = "21", "1" = "01", "2" = "11", "3" = "21")
        start_day <- dekad_map[d_str]

        # Further filter for known dekad strings
        final_valid <- !is.na(start_day)
        if (any(final_valid)) {
          fv_idx <- v_idx[final_valid]
          y <- y[final_valid]
          m <- m[final_valid]
          d_str <- d_str[final_valid]
          s_day <- start_day[final_valid]

          start_dates[fv_idx] <- paste(y, m, s_day, sep = "-")

          is_d1 <- d_str %in% c("D1", "1")
          is_d2 <- d_str %in% c("D2", "2")
          is_d3 <- d_str %in% c("D3", "3")

          if (any(is_d1)) end_dates[fv_idx[is_d1]] <- paste(y[is_d1], m[is_d1], "10", sep = "-")
          if (any(is_d2)) end_dates[fv_idx[is_d2]] <- paste(y[is_d2], m[is_d2], "20", sep = "-")
          if (any(is_d3)) {
            s_obj <- lubridate::ymd(start_dates[fv_idx[is_d3]])
            e_day <- lubridate::days_in_month(s_obj)
            end_dates[fv_idx[is_d3]] <- paste(y[is_d3], m[is_d3], e_day, sep = "-")
          }
        }
      }
    }

  } else if (tres == "M") {
    # Monthly format: YYYY-MM
    dash_parts <- strsplit(date_components, "-")
    valid_idx <- lengths(dash_parts) == 2
    if (any(valid_idx)) {
      m_mat <- matrix(unlist(dash_parts[valid_idx]), ncol = 2, byrow = TRUE)
      y <- m_mat[, 1]
      m <- m_mat[, 2]
      start_dates[valid_idx] <- paste(y, m, "01", sep = "-")
      s_obj <- lubridate::ymd(start_dates[valid_idx])
      end_dates[valid_idx] <- paste(y, m, lubridate::days_in_month(s_obj), sep = "-")
    }

  } else if (tres %in% c("A", "Y")) {
    # Annual format: YYYY
    valid_idx <- grepl("^\\d{4}$", date_components)
    if (any(valid_idx)) {
      start_dates[valid_idx] <- paste(date_components[valid_idx], "01", "01", sep = "-")
      end_dates[valid_idx]   <- paste(date_components[valid_idx], "12", "31", sep = "-")
    }

  } else if (tres == "E") {
    # Daily format: YYYY-MM-DD
    valid_idx <- grepl("^\\d{4}-\\d{2}-\\d{2}$", date_components)
    if (any(valid_idx)) {
      start_dates[valid_idx] <- date_components[valid_idx]
      end_dates[valid_idx]   <- date_components[valid_idx]
    }
  }

  # Final calculations: suppress warnings for unparseable components
  # These will result in NA which we handle downstream.
  s_dt <- suppressWarnings(lubridate::ymd(start_dates))
  e_dt <- suppressWarnings(lubridate::ymd(end_dates))
  ndays <- as.integer(difftime(e_dt, s_dt, units = "days")) + 1L

  # Standardize empty strings to NA
  start_dates[start_dates == ""] <- NA_character_
  end_dates[end_dates == ""]     <- NA_character_

  data.frame(
    start_date = start_dates,
    end_date = end_dates,
    number_of_days = ndays,
    raw_date = date_components,
    stringsAsFactors = FALSE
  )
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
#' date_info <- wapor_date_info(
#'   "https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-01-D1.tif",
#'   tres = "D"
#' )
#' date_info$start_date
#' # [1] "2023-01-01"
#' date_info$number_of_days
#' # [1] 10
#'
#' # Parse monthly data URL (WaPOR format: WAPOR-3.L1-AETI-M.YYYY-MM.tif)
#' date_info <- wapor_date_info(
#'   "https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-M/WAPOR-3.L1-AETI-M.2023-06.tif",
#'   tres = "M"
#' )
#' date_info$start_date
#' # [1] "2023-06-01"
wapor_date_info <- function(url, tres) {
  # Input validation
  if (!is.character(url) || length(url) != 1) {
    stop("'url' must be a single character string", call. = FALSE)
  }

  res <- wapor_parse_dates(url, tres)
  return(as.list(res[1, ]))
}


#' Safe Terra Projection Wrapper
#'
#' Eliminates PROJ database collisions on some Windows environments
#' when projecting between WGS84 and UTM.
#'
#' @param x SpatVector or SpatRaster
#' @param y target CRS
#' @return SpatVector or SpatRaster
#' @export
#' @keywords internal
wapor_safe_project <- function(x, y) {
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
      stop(sprintf("wapor_safe_project sf projection failed: %s", e$message), call. = FALSE)
  })
  
  if (inherits(x, "SpatVector")) {
    return(suppressWarnings(terra::vect(res_sf)))
  }
  return(res_sf)
}

#' Get Path to Persistent L3 Extent Cache
#'
#' Returns the path to the RDS file where L3 region extents are cached
#' persistently across sessions.
#'
#' @return Character. Path to the cache RDS file.
#' @keywords internal
#' @noRd
get_l3_cache_path <- function() {
  cache_dir <- tools::R_user_dir("Rwapor", which = "cache")
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }
  file.path(cache_dir, "l3_extents.rds")
}

#' Load Persistent L3 Extent Cache
#'
#' Reads the cached L3 extents from disk. Returns an empty named list
#' if no cache exists.
#'
#' @return A named list of extent vectors (xmin, ymin, xmax, ymax) keyed by region code.
#' @keywords internal
#' @noRd
load_l3_extent_cache <- function() {
  path <- get_l3_cache_path()
  if (file.exists(path)) {
    tryCatch(readRDS(path), error = function(e) list())
  } else {
    list()
  }
}

#' Save Persistent L3 Extent Cache
#'
#' @param cache Named list of extent vectors.
#' @keywords internal
#' @noRd
save_l3_extent_cache <- function(cache) {
  path <- get_l3_cache_path()
  tryCatch(saveRDS(cache, path), error = function(e) {
    warning("Could not save L3 extent cache: ", e$message, call. = FALSE)
  })
}

#' Get L3 Raster Extent (Internal Helper)
#'
#' @param url Character. Download URL for the raster.
#' @param code Character. 3-letter L3 region code used as cache key.
#' @param cache Named list of extent vectors.
#' @return A list with components `poly` (SpatVector) and `cache` (updated list).
#' @keywords internal
#' @noRd
.wapor_l3_extent_internal <- function(url, code, cache) {
  # Check cache first
  if (code %in% names(cache)) {
    ext_vec <- cache[[code]]
    bb_ext <- terra::ext(ext_vec[1], ext_vec[3], ext_vec[2], ext_vec[4])
    poly <- terra::as.polygons(bb_ext, crs = "EPSG:4326")
    terra::values(poly) <- NULL  # Clear NA attributes
    return(list(poly = poly, cache = cache))
  }

  # Fetch from remote
  vsi_url <- paste0("/vsicurl/", url)
  r <- tryCatch({
    suppressWarnings(terra::rast(vsi_url))
  }, error = function(e) NULL)
  
  if (is.null(r) || terra::nlyr(r) == 0) return(list(poly = NULL, cache = cache))

  r_ext <- tryCatch(terra::ext(r), error = function(e) NULL)
  if (is.null(r_ext)) return(list(poly = NULL, cache = cache))
  r_poly <- terra::as.polygons(r_ext, crs = terra::crs(r))
  terra::values(r_poly) <- NULL  # Clear NA attributes
  r_poly_4326 <- wapor_safe_project(r_poly, 4326)

  # Update cache
  ext_4326 <- terra::ext(r_poly_4326)
  cache[[code]] <- c(xmin = ext_4326$xmin, ymin = ext_4326$ymin,
                     xmax = ext_4326$xmax, ymax = ext_4326$ymax)

  list(poly = r_poly_4326, cache = cache)
}

#' Get L3 Raster Extent (Persistently Cached)
#'
#' Fetches the extent of a remote raster and returns it as a WGS84 polygon.
#' Results are cached to disk so they persist across R sessions, eliminating
#' expensive remote raster opens on subsequent calls.
#'
#' @param url Character. Download URL for the raster.
#' @param code Character. 3-letter L3 region code used as cache key.
#' @return A SpatVector polygon in EPSG:4326, or NULL on failure.
#' @importFrom terra rast ext as.polygons crs
#' @export
#' @keywords internal
wapor_l3_extent <- function(url, code) {
  cache <- load_l3_extent_cache()
  old_len <- length(cache)

  res <- .wapor_l3_extent_internal(url, code, cache)

  # Only save if the cache was actually updated
  if (length(res$cache) > old_len) {
    save_l3_extent_cache(res$cache)
  }

  res$poly
}

#' Guess L3 Region from Spatial Intersection
#'
#' @param variable Character. The WaPOR variable name (e.g., L3-AETI-D)
#' @param reg_info List from wapor_parse_region()
#' @param period Date period vector
#' @return Character vector of intersecting L3 regions, or NULL
#' @importFrom terra rast ext as.polygons is.related crs project vect
#' @export
#' @keywords internal
wapor_guess_region <- function(variable, reg_info, period) {
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

  # Build the user region polygon once (outside the loop)
  user_poly <- NULL
  if (is.null(reg_info)) {
     # No region info provided
  } else if (reg_info$type == "vector") {
    v <- suppressWarnings(terra::vect(reg_info$value))
    v_ext <- terra::ext(v)
    v_bb_poly <- terra::as.polygons(v_ext, crs = terra::crs(v))
    terra::values(v_bb_poly) <- NULL  # Clear NA attributes
    user_poly <- wapor_safe_project(v_bb_poly, 4326)
  } else if (reg_info$type == "bbox") {
    bbox <- reg_info$value
    # Ensure correct order for terra::ext
    bb_ext <- terra::ext(as.numeric(bbox[c("xmin", "xmax", "ymin", "ymax")]))
    user_poly <- terra::as.polygons(bb_ext, crs = "EPSG:4326")
    terra::values(user_poly) <- NULL  # Clear NA attributes
  }

  intersecting_codes <- character()

  # Load cache once before loop to avoid repeated disk I/O
  cache <- load_l3_extent_cache()
  old_len <- length(cache)

  for (i in seq_along(unique_urls)) {
    code <- extracted_codes[i]

    # Use internal helper with the pre-loaded cache
    res <- tryCatch(.wapor_l3_extent_internal(unique_urls[i], code, cache), error = function(e) NULL)
    if (is.null(res) || is.null(res$poly)) next

    # Update local cache to pass to next iteration
    cache <- res$cache

    if (!is.null(user_poly) &&
        any(suppressWarnings(terra::is.related(res$poly, user_poly, "intersects")))) {
      intersecting_codes <- c(intersecting_codes, code)
    }
  }

  # Save cache once after loop if any new extents were added
  if (length(cache) > old_len) {
    save_l3_extent_cache(cache)
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
#' @param reg_info List from \code{wapor_parse_region()} with \code{$type} and \code{$value}.
#' @param do_mask Logical. If TRUE, also mask to vector geometry (not just crop).
#' @return Cropped (and optionally masked) SpatRaster.
#' @keywords internal
#' @export
wapor_crop_to_region <- function(r, reg_info, do_mask = FALSE) {
  r_crs <- terra::crs(r)
  
  # Handle empty CRS (common if PROJ DB is misconfigured or metadata is missing)
  if (!nzchar(r_crs)) {
    ext_r <- terra::ext(r)
    # If the extent looks like geographic coordinates (decimal degrees), assume WGS84
    if (ext_r$xmin >= -180 && ext_r$xmax <= 180 && ext_r$ymin >= -90 && ext_r$ymax <= 90) {
      suppressWarnings(terra::crs(r) <- "EPSG:4326")
      r_crs <- terra::crs(r)
    }
  }
  
  has_r_crs <- nzchar(r_crs)

  if (reg_info$type == "vector") {
    vect_data <- reg_info$value
    vect_crs <- sf::st_crs(vect_data)
    if (!is.na(vect_crs) && vect_crs$epsg != 4326) {
      vect_data <- sf::st_transform(vect_data, 4326)
    }
    v <- suppressWarnings(terra::vect(vect_data))
    v_crs <- terra::crs(v)
    if (has_r_crs && nzchar(v_crs) && v_crs != r_crs) {
      v <- wapor_safe_project(v, r_crs)
    }
    r <- suppressWarnings(terra::crop(r, v, snap = "out"))
    if (do_mask) {
      r <- suppressWarnings(terra::mask(r, v, touches = TRUE))
    }
  } else if (reg_info$type == "bbox") {
    # Use sf to build the polygon to avoid terra PROJ collisions during CRS setting
    bb_sf <- sf::st_as_sfc(sf::st_bbox(reg_info$value))
    bb_poly <- suppressWarnings(terra::vect(bb_sf))
    bb_crs <- terra::crs(bb_poly)
    
    # Project if CRS differs or if one is lonlat and the other isn't
    needs_proj <- FALSE
    if (has_r_crs) {
      r_is_ll <- isTRUE(terra::is.lonlat(r))
      bb_is_ll <- isTRUE(terra::is.lonlat(bb_poly))
      
      if (bb_crs != r_crs) needs_proj <- TRUE
      if (r_is_ll != bb_is_ll) needs_proj <- TRUE
    }
    
    if (needs_proj) {
      bb_poly <- wapor_safe_project(bb_poly, r_crs)
    }
    
    r <- suppressWarnings(terra::crop(r, bb_poly, snap = "out"))
  }
  r
}

#' Get URL Chunks for Batching
#'
#' Internal helper to split a vector of URLs into chunks for batch processing.
#'
#' @param urls Character vector of URLs.
#' @param batching Logical. If TRUE, splits URLs into chunks. If FALSE, returns all in one chunk.
#' @param batch_size Integer. Maximum number of URLs per chunk.
#'
#' @return A list of character vectors.
#' @keywords internal
#' @noRd
get_url_chunks <- function(urls, batching = TRUE, batch_size = 12L) {
  if (!batching || length(urls) <= batch_size) {
    return(list(urls))
  }
  
  split(urls, ceiling(seq_along(urls) / batch_size))
}

#' Log Message with Timestamp
#' @param ... Passed to paste()
#' @keywords internal
#' @noRd
log_msg <- function(...) {
  msg <- paste(...)
  message(sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), msg))
}

#' Internal Geometry Comparison Wrapper
#' @param x SpatRaster
#' @param y SpatRaster
#' @keywords internal
#' @noRd
compare_geom <- function(x, y) {
  # Robust comparison that handles floating point extent differences
  tryCatch(terra::compareGeom(x, y, stopOnError = FALSE, messages = FALSE), 
           error = function(e) FALSE)
}

#' Assign Metadata to Raster Layers
#'
#' @param r SpatRaster
#' @param variable Character. Variable code.
#' @param unit_conversion Character.
#' @param units_override Optional explicit units string.
#' @return SpatRaster with updated units and long names.
#' @keywords internal
#' @noRd
assign_raster_metadata <- function(r, variable, unit_conversion = "none", units_override = NULL) {
  # Safety check: ensure r is a SpatRaster and not empty
  if (!inherits(r, "SpatRaster") || terra::nlyr(r) == 0) return(r)

  meta <- wapor_variable_metadata(variable)
  if (is.null(meta)) return(r)

  # Determine units
  res_units <- units_override %||% meta$units
  
  # Handle temperature conversion (Kelvin to Celsius)
  if (grepl("^AGERA5-(TMIN|TMAX)-", variable, ignore.case = FALSE)) {
    res_units <- sub("^K$", "degC", res_units)
  }
  
  if (is.null(units_override) && !is.null(unit_conversion) && unit_conversion != "none") {
    # If converted, update the time part of the unit string
    # e.g., mm/day -> mm/dekad
    parts <- strsplit(res_units, "/")[[1]]
    if (length(parts) > 1) {
      res_units <- paste0(paste(parts[-length(parts)], collapse = "/"), "/", unit_conversion)
    }
  }

  # Assign metadata using try to prevent fatal errors during check (metags can fail on some platforms)
  try({
    # Assign units
    terra::units(r) <- res_units
    
    # Assign long name to both layers and GDAL metadata for maximum compatibility
    if (!is.null(meta$long_name)) {
      # Try setting longnames (layer descriptions)
      try(terra::longnames(r) <- rep(as.character(meta$long_name), terra::nlyr(r)), silent = TRUE)
      # Try setting GDAL metadata (LongName)
      try(terra::metags(r) <- c(long_name = as.character(meta$long_name)), silent = TRUE)
    }
  }, silent = TRUE)
  
  return(r)
}
