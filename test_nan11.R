suppressPackageStartupMessages(library(terra))
devtools::load_all('.')
v <- sf::st_read("C:/Users/almut/OneDrive/Documents/GitHub/Classification/Data/Vectors/Citrus_farms_final.geojson", quiet=TRUE)
v <- safe_project(v, "EPSG:32636")
urls <- wapor_generate_urls("L3-AETI-M", l3_region="JVA", period=c("2023-01-01", "2023-03-31"))

r1 <- terra::rast(paste0("/vsicurl/", urls[1]))
r1 <- terra::crop(r1, v)
r1_c <- terra::classify(r1, cbind(NaN, NA))
r1_m <- terra::mask(r1_c, v)
s <- c(r1_m, r1_m)
s_app <- terra::app(s, sum, na.rm=TRUE)

out <- tempfile(fileext=".tif")
terra::writeRaster(s_app, out, overwrite=TRUE, NAflag=-9999)

r_load <- terra::rast(out)
cat("NAflag load:", terra::NAflag(r_load), "\n")
cat("Min/max load:", terra::minmax(r_load), "\n")

# Use gdalinfo!
gdal_info <- sf::gdal_utils("info", out, quiet=TRUE)
cat("GDAL INFO:\n")
cat(substr(gdal_info, 1, 1500), "\n")
