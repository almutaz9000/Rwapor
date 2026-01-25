#' Download a Map
#'
#' @param region Region definition
#' @param variable Variable name
#' @param period Date range c(start, end)
#' @param folder Output folder
#' @param filename Output filename (optional)
#' @param download_locally If TRUE, download files using parallel processing before reading
#' @return Path to output file
#' @importFrom terra rast crop mask writeRaster
#' @importFrom sf st_transform st_bbox
#' @export
wapor_map <- function(region, variable, period, folder, filename = NULL, download_locally = FALSE) {
  if (!dir.exists(folder)) dir.create(folder, recursive = TRUE)
  
  # Parse region
  reg_info <- parse_region(region)
  l3_code <- if (reg_info$type == "l3_code") reg_info$value else NULL
  
  # Get URLs
  urls <- wapor_generate_urls(variable, l3_region = l3_code, period = period)
  message(sprintf("Found %d files for %s.", length(urls), variable))
  
  if (length(urls) == 0) stop("No data found for this period/region.")
  
  # Download locally if requested
  if (download_locally) {
      # Use a subfolder or just caching folder? 
      # Let's use a "cache" folder inside the output folder or just temporary
      dl_folder <- file.path(folder, "cache")
      message("Downloading locally to: ", dl_folder, " (Parallel)")
      urls <- download_urls_parallel(urls, dl_folder)
  }
  
  # Load as SpatRaster
  r <- terra::rast(urls)
  
  # Crop/Mask if region is vector or bbox
  if (reg_info$type == "vector") {
    vect <- reg_info$value
    # Transform vector to raster CRS if needed (usually EPSG:4326 for WaPOR)
    # WaPOR is typically 4326.
    if (sf::st_crs(vect)$epsg != 4326) {
        vect <- sf::st_transform(vect, 4326)
    }
    v <- terra::vect(vect)
    r <- terra::crop(r, v)
    r <- terra::mask(r, v)
  } else if (reg_info$type == "bbox") {
    # Crop to bbox
    ext <- terra::ext(reg_info$value[c("xmin", "xmax", "ymin", "ymax")])
    r <- terra::crop(r, ext)
  }
  
  # Output filename
  if (is.null(filename)) {
    # Generate filename: region_variable_period.tif
    reg_str <- if (reg_info$type == "l3_code") l3_code else "region"
    filename <- paste0(reg_str, "_", variable, ".tif")
  }
  
  out_path <- file.path(folder, filename)
  terra::writeRaster(r, out_path, overwrite = TRUE)
  
  return(out_path)
}
