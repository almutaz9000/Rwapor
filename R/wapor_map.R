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
#' @param download_locally Logical. If TRUE, downloads files to local cache
#'   using parallel processing before reading. Useful for slow connections
#'   or when processing large time series. Default is FALSE.
#'
#' @return Character. Path to the output GeoTIFF file.
#'
#' @details
#' The function performs the following steps:
#' 1
#' . Generates download URLs for the specified variable and period
#' 2. Loads raster data (remotely or locally depending on `download_locally`)
#' 3. Crops to bounding box or masks to vector geometry
#' 4. Writes output as a multi-band GeoTIFF (one band per time step)
#'
#' For parallel downloads, set up workers before calling:
#' ```r
#' future::plan(future::multisession, workers = 4)
#' ```
#'
#' @export
#'
#' @importFrom terra rast crop mask writeRaster vect ext
#' @importFrom sf st_transform st_bbox st_crs
#'
#' @examples
#' \dontrun{
#' # Download dekadal ET for a bounding box
#' output_file <- wapor_map(
#'   region = c(35.0, 33.0, 36.0, 34.0),
#'   variable = "L1-AETI-D",
#'   period = c("2023-01-01", "2023-01-31"),
#'   folder = "output"
#' )
#'
#' # Download for a shapefile region with local caching
#' future::plan(future::multisession, workers = 4)
#' output_file <- wapor_map(
#'   region = "path/to/region.shp",
#'   variable = "L2-NPP-M",
#'   period = c("2023-01-01", "2023-12-31"),
#'   folder = "output",
#'   download_locally = TRUE
#' )
#'
#' # Download L3 data for Awash Basin
#' output_file <- wapor_map(
#'   region = "AWA",
#'   variable = "L3-AETI-D",
#'   period = c("2023-06-01", "2023-06-30"),
#'   folder = "output"
#' )
#' }
wapor_map <- function(region, variable, period, folder, filename = NULL, download_locally = FALSE) {
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

  # Download locally if requested
  if (download_locally) {
    dl_folder <- file.path(folder, "cache")
    message("Downloading locally to: ", dl_folder, " (Parallel)")
    urls <- download_urls_parallel(urls, dl_folder)
  }

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

  # Generate output filename if not provided
  if (is.null(filename)) {
    reg_str <- if (reg_info$type == "l3_code") l3_code else "region"
    filename <- paste0(reg_str, "_", variable, ".tif")
  }

  out_path <- file.path(folder, filename)

  # Write output
  tryCatch({
    terra::writeRaster(r, out_path, overwrite = TRUE)
  }, error = function(e) {
    stop(sprintf("Failed to write raster to '%s': %s", out_path, e$message), call. = FALSE)
  })

  message(sprintf("Saved raster to: %s", out_path))
  return(out_path)
}
