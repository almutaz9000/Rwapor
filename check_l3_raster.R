setwd("c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor")
devtools::load_all(".", quiet = TRUE)
library(sf); library(terra)

farms_sf <- sf::st_read("Pivots_savola2.geojson", quiet = TRUE)
farms_sf[["farm_id"]] <- paste0("farm_", seq_len(nrow(farms_sf)))
cat("Farm BBox (WGS84):", paste(round(as.numeric(sf::st_bbox(farms_sf)), 4), collapse = " "), "\n")

# Check L3-AETI-D URLs for ENO region
urls <- Rwapor::wapor_generate_urls("L3-AETI-D", l3_region = "ENO", period = c("2022-01-01", "2022-01-31"))
cat("\nL3-AETI-D URLs found:", length(urls), "\n")
cat("First URL:", substr(urls[1], 1, 120), "\n")

# Load the raster and check its extent
url_vs <- paste0("/vsicurl/", urls[1])
cat("\nLoading L3 raster...\n")
r <- suppressWarnings(terra::rast(url_vs))
cat("CRS:", terra::crs(r, describe = TRUE)$name, "\n")
cat("Extent:", paste(round(as.numeric(terra::ext(r)), 4), collapse = " "), "\n")
cat("Resolution:", terra::res(r), "\n")
cat("Dims:", dim(r), "\n")

# Check in WGS84 if CRS is different
if (!terra::is.lonlat(r)) {
  cat("\nRaster is NOT in lonlat! Projecting extent to WGS84...\n")
  r_wgs <- terra::project(r, "EPSG:4326")
  cat("WGS84 Extent:", paste(round(as.numeric(terra::ext(r_wgs)), 4), collapse = " "), "\n")
} else {
  cat("Raster is in lonlat (WGS84/Geographic)\n")
}

cat("\nFarm bbox vs Raster extent:\n")
fb <- sf::st_bbox(farms_sf)
re <- terra::ext(r)
cat("  Farm: xmin=", fb["xmin"], "xmax=", fb["xmax"], "ymin=", fb["ymin"], "ymax=", fb["ymax"], "\n")
cat("  Rast: xmin=", re$xmin, "xmax=", re$xmax, "ymin=", re$ymin, "ymax=", re$ymax, "\n")
