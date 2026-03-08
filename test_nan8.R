suppressPackageStartupMessages(library(terra))
suppressPackageStartupMessages(library(sf))
devtools::load_all('.')

# User's regions and URLs
v <- sf::st_read("C:/Users/almut/OneDrive/Documents/GitHub/Classification/Data/Vectors/Citrus_farms_final.geojson", quiet=TRUE)
v <- safe_project(v, "EPSG:32636")

urls <- wapor_generate_urls("L3-AETI-M", l3_region="JVA", period=c("2023-01-01", "2023-03-31"))

cat("--- Raw Load ---\n")
r1 <- terra::rast(paste0("/vsicurl/", urls[1]))
r1 <- terra::crop(r1, v)
cat("NA flag raw:", terra::NAflag(r1), "\n")
cat("Min/max raw:", terra::minmax(r1), "\n")
cat("NaN count raw:", terra::global(terra::app(r1, is.nan), "sum")[[1]], "\n")

cat("\n--- After Classify ---\n")
r1_c <- terra::classify(r1, cbind(NaN, NA))
cat("NaN count c:", terra::global(terra::app(r1_c, is.nan), "sum")[[1]], "\n")

cat("\n--- After Mask ---\n")
r1_m <- terra::mask(r1_c, v)
cat("NaN count m:", terra::global(terra::app(r1_m, is.nan), "sum")[[1]], "\n")

cat("\n--- After Stack and Math ---\n")
s <- c(r1_m, r1_m)
s_app <- terra::app(s, sum, na.rm=TRUE)
cat("NaN count sum:", terra::global(terra::app(s_app, is.nan), "sum")[[1]], "\n")
cat("Min/max sum:", terra::minmax(s_app), "\n")

cat("\n--- Writing Raster ---\n")
out <- tempfile(fileext=".tif")
terra::writeRaster(s_app, out, overwrite=TRUE)
r_load <- terra::rast(out)
cat("NA flag loaded:", terra::NAflag(r_load), "\n")
cat("NaN count loaded:", terra::global(terra::app(r_load, is.nan), "sum")[[1]], "\n")
cat("Min/max loaded:", terra::minmax(r_load), "\n")
