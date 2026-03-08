suppressPackageStartupMessages(library(terra))
suppressPackageStartupMessages(library(sf))
devtools::load_all('.')

v <- sf::st_read("C:/Users/almut/OneDrive/Documents/GitHub/Classification/Data/Vectors/Citrus_farms_final.geojson", quiet=TRUE)
v <- safe_project(v, "EPSG:32636")
urls <- wapor_generate_urls("L3-AETI-M", l3_region="JVA", period=c("2023-01-01", "2023-03-31"))

r1 <- terra::rast(paste0("/vsicurl/", urls[1]))
r1 <- terra::crop(r1, v)
r1_m <- terra::mask(r1, v) # Terra mask injects NaN!

# Clean NaN directly to -9999
r1_clean <- terra::classify(r1_m, cbind(NaN, -9999))
# Clean NA directly to -9999 just in case
r1_clean <- terra::classify(r1_clean, cbind(NA, -9999))

cat("r1_clean NaN count:", terra::global(terra::app(r1_clean, is.nan), "sum")[[1]], "\n")

out <- tempfile(fileext=".tif")
terra::writeRaster(r1_clean, out, overwrite=TRUE, NAflag=-9999)

r_load <- terra::rast(out)
cat("NAflag load:", terra::NAflag(r_load), "\n")
cat("Min/max load:", terra::minmax(r_load), "\n")
cat("NA count load:", terra::global(is.na(r_load), "sum")[[1]], "\n")
