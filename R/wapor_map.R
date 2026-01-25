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
  if (!is.character(variable) || length(variable) != 1) {
    stop("'variable' must be a single character string", call. = FALSE)
  }
  if (!is.character(period) || length(period) != 2) {
    stop("'period' must be a character vector of length 2: c(start_date, end_date)", call. = FALSE)
  }
  if (!is.character(folder) || length(folder) != 1) {
    stop("'folder' must be a single character string", call. = FALSE)
  }

  # Determine default unit_conversion if NULL
  if (is.null(unit_conversion)) {
    if (grepl("-D$", variable)) {
      unit_conversion <- "dekad"
      message("Variable is Dekadal (stored as mm/day). Defaulting unit_conversion to 'dekad' (mm/dekad).")
    } else {
      unit_conversion <- "none"
    }
  }

  # Create output directory
  if (!dir.exists(folder)) {
    dir.create(folder, recursive = TRUE)
  }

  # Parse region
  reg_info <- parse_region(region)
  l3_code <- if (reg_info$type == "l3_code") reg_info$value else NULL

  # Get URLs
  urls <- wapor_generate_urls(variable, l3_region = l3_code, period = period)
  message(sprintf("Found %d files for %s.", length(urls), variable))

  if (length(urls) == 0) {
    stop("No data found for this period/region.", call. = FALSE)
  }

  # Determine naming components
  # Base name from first file (e.g., WAPOR-3.L1-AETI-D)
  base_fname <- basename(urls[1])
  # Remove date and extension to get invariant part
  # Assumes format: {Base}.{Date}.tif
  # Split by dots
  parts <- strsplit(base_fname, "\\.")[[1]]
  # The product base is usually everything except the last 2 parts (Date, Extension)
  # But simpler: we know variable is L1-AETI-D, so we can use "WAPOR-3.L1-AETI-D" if standard
  # Let's derive it from the filename to be safe
  if (length(parts) >= 3) {
    product_base <- paste(parts[1:(length(parts)-2)], collapse = ".")
  } else {
    product_base <- variable # Fallback
  }
  
  prefix <- if (reg_info$type == "bbox") "bb_" else ""

  # Use GDAL virtual file system for efficient streaming
  urls <- ifelse(grepl("^/vsicurl/", urls), urls, paste0("/vsicurl/", urls))
  message("Streaming data using GDAL virtual file system (/vsicurl/)...")

  # Load as SpatRaster
  r <- tryCatch({
    terra::rast(urls)
  }, error = function(e) {
    stop(sprintf("Failed to load raster data: %s", e$message), call. = FALSE)
  })

  # Crop/Mask based on region type
  if (reg_info$type == "vector") {
    vect <- reg_info$value
    # Transform vector to raster CRS if needed (WaPOR uses EPSG:4326)
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

  # Apply unit conversion if requested
  if (unit_conversion != "none") {
    message(sprintf("Converting units to '%s'...", unit_conversion))
    r <- raster_unit_convertor(r, variable, urls, unit_conversion)
  }

  output_paths <- character()

  if (separate_files) {
    # Save each layer individually
    for (i in 1:terra::nlyr(r)) {
      # Extract date for this layer
      # Re-parsing date from original URLs (assuming mapped 1:1)
      # This is safer than relying on terra layer names
      # remove /vsicurl/ prefix for parsing
      orig_url <- sub("^/vsicurl/", "", urls[i])
      date_info <- get_date_info(orig_url, tres = strsplit(variable, "-")[[1]][3])
      date_str <- date_info$start_date # YYYY-MM-DD
      
      fname <- paste0(prefix, product_base, ".", date_str, ".tif")
      out_path <- file.path(folder, fname)
      
      terra::writeRaster(r[[i]], out_path, overwrite = TRUE)
      output_paths <- c(output_paths, out_path)
    }
    message(sprintf("Saved %d raster files to: %s", length(output_paths), folder))
    return(output_paths)
    
  } else {
    # Save as single stack
    if (is.null(filename)) {
      # Construct range name
      start_url <- sub("^/vsicurl/", "", urls[1])
      end_url <- sub("^/vsicurl/", "", urls[length(urls)])
      
      start_info <- get_date_info(start_url, tres = strsplit(variable, "-")[[1]][3])
      end_info <- get_date_info(end_url, tres = strsplit(variable, "-")[[1]][3])
      
      if (length(urls) == 1) {
        date_part <- start_info$start_date
      } else {
        date_part <- paste0(start_info$start_date, "_", end_info$end_date)
      }
      
      filename <- paste0(prefix, product_base, ".", date_part, ".tif")
    }
    
    out_path <- file.path(folder, filename)
    
    tryCatch({
      terra::writeRaster(r, out_path, overwrite = TRUE)
    }, error = function(e) {
      stop(sprintf("Failed to write raster to '%s': %s", out_path, e$message), call. = FALSE)
    })
    
    message(sprintf("Saved raster to: %s", out_path))
    return(out_path)
  }
}
