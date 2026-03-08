suppressPackageStartupMessages(library(terra))
devtools::load_all('.')
v <- safe_project(sf::st_read("C:/Users/almut/OneDrive/Documents/GitHub/Classification/Data/Vectors/Citrus_farms_final.geojson", quiet=TRUE), "EPSG:32636")
urls <- wapor_generate_urls("L3-AETI-M", l3_region="JVA", period=c("2023-01-01", "2023-03-31"))

r1 <- terra::rast(paste0("/vsicurl/", urls[1]))
r1 <- terra::crop(r1, v)
r1_m <- terra::mask(r1, v) # Mask FIRST

cat("r1_m NaN:", terra::global(terra::app(r1_m, is.nan), "sum")[[1]], "\n")

# Try to clean ALL missing types to -9999
r1_c <- terra::classify(r1_m, cbind(NaN, -9999))
r1_c <- terra::classify(r1_c, cbind(NA, -9999))

cat("r1_c NaN:", terra::global(terra::app(r1_c, is.nan), "sum")[[1]], "\n")
cat("r1_c NA:", terra::global(is.na(r1_c), "sum")[[1]], "\n")

# Is terra writing NA correctly?
out <- tempfile(fileext=".tif")
terra::writeRaster(r1_c, out, overwrite=TRUE, NAflag=-9999)
r_load <- terra::rast(out)

cat("Metadata NA flag loaded:", terra::NAflag(r_load), "\n")
cat("Min/max loaded:", terra::minmax(r_load), "\n")
