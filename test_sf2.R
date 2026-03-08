suppressPackageStartupMessages(library(terra))
suppressPackageStartupMessages(library(sf))

# Simulate poisoned GDAL
r_dummy <- terra::rast(matrix(1:4, 2))
terra::crs(r_dummy) <- "EPSG:4326"

url <- "/vsicurl/https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets/L3-AETI-D/rasters/WAPOR-3.L3-AETI-D.JVA.2023-01-D1.tif"
r <- tryCatch(terra::rast(url), error=function(e) NULL)

if (!is.null(r)) {
    target_crs <- terra::crs(r)
    v_sf <- sf::st_as_sfc(sf::st_bbox(c(xmin=35, ymin=32, xmax=36, ymax=33), crs=sf::st_crs("EPSG:4326")))
    
    # Can sf project using the WKT string from terra directly?
    v_sf_proj <- tryCatch(sf::st_transform(v_sf, target_crs), error=function(e) cat("sf error: ", e$message, "\n"))
    
    if (!is.null(v_sf_proj)) {
        cat("sf projected using native terra WKT string!\n")
        v_terra <- terra::vect(v_sf_proj)
        cat("Successfully rebuilt SpatVector\n")
    }
}
