#' Download and Save a Raster Map
#'
#' Downloads WaPOR or AgERA5 raster data for a specified region and time period,
#' optionally crops/masks to the region boundary, and saves as a GeoTIFF file.
#'
#' @param region Region definition. One of:
#'   * Path to a vector file (shapefile, GeoJSON, GeoPackage)
#'   * L3 region code (3 uppercase letters, e.g., "AWA")
#'   * Numeric bounding box: `c(xmin, ymin, xmax, ymax)` in WGS84
#' @param variable Character. Variable name following WaPOR/AgERA5 naming
#'   convention (e.g., "L1-AETI-D", "L2-NPP-M", "AGERA5-ET0-E").
#' @param period Character vector of length 2. Date range as
#'   `c(start_date, end_date)` in "YYYY-MM-DD" format.
#' @param folder Character. Output directory path. Will be created if needed.
#' @param filename Character. Optional output filename. If NULL, a default
#'   name is generated based on region and variable.
#' @param unit_conversion Character. Target temporal unit for conversion.
#'   One of: "none", "day", "dekad", "month", "year".
#'   Default is NULL, which dynamically sets the default based on variable type:
#'   * "dekad" for Dekadal variables (files end in "D" but contain daily rates)
#'   * "none" for others
#'
#' @return Character. Path to the output GeoTIFF file.
#'
#' @details
#' The function performs the following steps:
#' 1. Generates download URLs for the specified variable and period
#' 2. Streams raster data using GDAL virtual file system (/vsicurl/)
#' 3. Crops to bounding box or masks to vector geometry
#' 4. Converts units if requested (e.g., mm/day -> mm/dekad)
#' 5. Writes output as a multi-band GeoTIFF (one band per time step) or separate files
#'
#' @export
#'
#' @importFrom terra rast crop mask writeRaster vect ext
#' @importFrom sf st_transform st_bbox st_crs
#'
#' @examples
#' \dontrun{
#' # Download dekadal ET for a bounding box (defaults to mm/dekad)
#' output_file <- wapor_map(
#'   region = c(35.0, 33.0, 36.0, 34.0),
#'   variable = "L1-AETI-D",
#'   period = c("2023-01-01", "2023-01-31"),
#'   folder = "output"
#' )
#'
#' # Download daily rates (mm/day)
#' output_file <- wapor_map(
#'   region = c(35.0, 33.0, 36.0, 34.0),
#'   variable = "L1-AETI-D",
#'   period = c("2023-01-01", "2023-01-31"),
#'   folder = "output",
#'   unit_conversion = "day"
#' )
#' }
wapor_map <- function(region, variable, period, folder, filename = NULL, separate_files = FALSE, unit_conversion = NULL) {
  # Input validation
  if (!is.character(variable) || length(variable) == 0) {
    stop("'variable' must be a character vector", call. = FALSE)
  }
  if (!is.character(period) || length(period) != 2) {
    stop("'period' must be a character vector of length 2: c(start_date, end_date)", call. = FALSE)
  }
  if (!is.character(folder) || length(folder) != 1) {
    stop("'folder' must be a single character string", call. = FALSE)
  }

  # Create base output directory
  if (!dir.exists(folder)) {
    dir.create(folder, recursive = TRUE)
  }

  # Parse region once
  reg_info <- parse_region(region)
  l3_code <- if (reg_info$type == "l3_code") reg_info$value else NULL

  # Helper function to process a single variable
  process_single_var <- function(var) {
    message(sprintf("Processing variable: %s", var))
    
    # Create variable-specific subdirectory
    var_folder <- file.path(folder, var)
    if (!dir.exists(var_folder)) {
      dir.create(var_folder, recursive = TRUE)
    }

    # Determine unit_conversion for this variable if NULL
    current_unit_conv <- unit_conversion
    if (is.null(current_unit_conv)) {
      if (grepl("-D$", var)) {
        current_unit_conv <- "dekad"
        message(sprintf("Variable %s is Dekadal. Defaulting unit_conversion to 'dekad'.", var))
      } else {
        current_unit_conv <- "none"
      }
    }

    # Get URLs
    urls <- wapor_generate_urls(var, l3_region = l3_code, period = period)
    message(sprintf("Found %d files for %s.", length(urls), var))

    if (length(urls) == 0) {
      warning(sprintf("No data found for %s in this period/region. Skipping.", var), call. = FALSE)
      return(NULL)
    }

    # Determine naming components
    base_fname <- basename(urls[1])
    parts <- strsplit(base_fname, "\\.")[[1]]
    if (length(parts) >= 3) {
      product_base <- paste(parts[1:(length(parts)-2)], collapse = ".")
    } else {
      product_base <- var 
    }
    
    prefix <- if (reg_info$type == "bbox") "bb_" else ""

    # Use GDAL virtual file system
    urls <- ifelse(grepl("^/vsicurl/", urls), urls, paste0("/vsicurl/", urls))
    
    # Load as SpatRaster
    r <- tryCatch({
      terra::rast(urls)
    }, error = function(e) {
      warning(sprintf("Failed to load raster data for %s: %s", var, e$message), call. = FALSE)
      return(NULL)
    })
    
    if (is.null(r)) return(NULL)

    # Crop/Mask
    if (reg_info$type == "vector") {
      vect <- reg_info$value
      vect_crs <- sf::st_crs(vect)
      if (!is.na(vect_crs) && vect_crs$epsg != 4326) {
        vect <- sf::st_transform(vect, 4326)
      }
      v <- terra::vect(vect)
      r <- terra::crop(r, v)
      r <- terra::mask(r, v)
    } else if (reg_info$type == "bbox") {
      ext <- terra::ext(reg_info$value[c("xmin", "xmax", "ymin", "ymax")])
      r <- terra::crop(r, ext)
    }

    # Unit Conversion
    if (current_unit_conv != "none") {
      message(sprintf("Converting units to '%s'...", current_unit_conv))
      r <- raster_unit_convertor(r, var, urls, current_unit_conv)
    }

    # Standardize Layer Names (Band Names)
    # terra uses source filenames by default (e.g. ...2021-01-D1)
    # We want standard dates (YYYY-MM-DD)
    layer_names <- character(length(urls))
    for (i in seq_along(urls)) {
      orig_url <- sub("^/vsicurl/", "", urls[i])
      date_info <- get_date_info(orig_url, tres = strsplit(var, "-")[[1]][3])
      layer_names[i] <- date_info$start_date
    }
    names(r) <- layer_names

    output_paths <- character()

    if (separate_files) {
      for (i in 1:terra::nlyr(r)) {
        # use the standardized name we just created
        date_str <- names(r)[i] 
        # ... or keep using get_date_info if we prefer safety, but names(r) is now consistent
        
        fname <- paste0(prefix, product_base, ".", date_str, ".tif")
        out_path <- file.path(var_folder, fname)
        
        terra::writeRaster(r[[i]], out_path, overwrite = TRUE)
        output_paths <- c(output_paths, out_path)
      }
    } else {
      # Single stack
      current_filename <- filename
      if (is.null(current_filename)) {
        start_date <- names(r)[1]
        end_date <- names(r)[terra::nlyr(r)]
        
        if (terra::nlyr(r) == 1) {
          date_part <- start_date
        } else {
          date_part <- paste0(start_date, "_", end_date)
        }
        
        current_filename <- paste0(prefix, product_base, ".", date_part, ".tif")
      }
      
      out_path <- file.path(var_folder, current_filename)
      terra::writeRaster(r, out_path, overwrite = TRUE)
      output_paths <- out_path
    }
    
    return(output_paths)
  }

  # Process all variables
  results <- lapply(variable, process_single_var)
  names(results) <- variable
  
  # Return just the path if it's a single variable (backward compatibility/simplicity)
  # But structured list is better if >1 variable.
  # User requested "processing list of variables", so list return is safer.
  if (length(variable) == 1) {
    return(results[[1]])
  } else {
    return(results)
  }
}
