suppressPackageStartupMessages(library(terra))
suppressPackageStartupMessages(library(sf))

# Initialize terra with the bad PROJ cache!
r_dummy <- terra::rast(matrix(1:4, 2))
terra::crs(r_dummy) <- "EPSG:4326"

# Now try to project using sf
v_sf <- sf::st_as_sfc(sf::st_bbox(c(xmin=35, ymin=32, xmax=36, ymax=33), crs=sf::st_crs("EPSG:4326")))

# Project sf to UTM 36N
v_proj_sf <- tryCatch(sf::st_transform(v_sf, "EPSG:32636"), error=function(e) cat("sf project error: ", e$message, "\n"))
if (!is.null(v_proj_sf)) {
    cat("sf::st_transform succeeded!\n")
    # Convert it back to terra to see if terra can use it
    v_terra <- terra::vect(v_proj_sf)
    cat("Converted back to terra successfully!\n")
}
