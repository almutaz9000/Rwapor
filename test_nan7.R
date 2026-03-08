suppressPackageStartupMessages(library(terra))
devtools::load_all('.')
urls <- wapor_generate_urls("L3-AETI-D", l3_region="JVA", period=c("2023-01-01", "2023-01-10"))

r <- terra::rast(paste0("/vsicurl/", urls[1]))
r_clean <- terra::classify(r, cbind(NaN, NA))

cat("Clean NA count:", terra::global(is.na(r_clean), "sum")[[1]], "\n")

# Simulate vector masking from wapor_map
suppressPackageStartupMessages(library(sf))
v <- sf::st_read("C:/Users/almut/OneDrive/Documents/GitHub/Classification/Data/Vectors/Citrus_farms_final.geojson", quiet=TRUE)
v <- safe_project(v, terra::crs(r))
r_crop <- terra::crop(r_clean, v)
r_mask <- terra::mask(r_crop, v)

cat("\nCropped NA count:", terra::global(is.na(r_crop), "sum")[[1]], "\n")
cat("Cropped NaN:", terra::global(terra::app(r_crop, is.nan), "sum")[[1]], "\n")

cat("\nMasked NA count:", terra::global(is.na(r_mask), "sum")[[1]], "\n")
cat("Masked NaN:", terra::global(terra::app(r_mask, is.nan), "sum")[[1]], "\n")
