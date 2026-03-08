suppressPackageStartupMessages(library(terra))
devtools::load_all('.')
urls <- wapor_generate_urls("L3-AETI-M", l3_region="JVA", period=c("2023-01-01", "2023-03-31"))

v <- safe_project(sf::st_read("C:/Users/almut/OneDrive/Documents/GitHub/Classification/Data/Vectors/Citrus_farms_final.geojson", quiet=TRUE), "EPSG:32636")
r1 <- terra::mask(terra::crop(terra::rast(paste0("/vsicurl/", urls[1])), v), v)
r2 <- terra::mask(terra::crop(terra::rast(paste0("/vsicurl/", urls[2])), v), v)
r1 <- terra::classify(r1, cbind(NaN, NA))
r2 <- terra::classify(r2, cbind(NaN, NA))

stack <- c(r1, r2)
sum_r <- sum(stack, na.rm=TRUE)

# Check 0 counts
cat("Sum 0 count:", terra::global(sum_r == 0, "sum", na.rm=TRUE)[[1]], "\n")

all_na <- sum(is.na(stack)) == terra::nlyr(stack)
sum_r_fixed <- terra::mask(sum_r, all_na, maskvalue = 1)

cat("Sum Fixed 0 count:", terra::global(sum_r_fixed == 0, "sum", na.rm=TRUE)[[1]], "\n")
cat("Sum Fixed NA count:", terra::global(is.na(sum_r_fixed), "sum")[[1]], "\n")

# Apply formal -9999 classifier
seasonal_out <- terra::classify(sum_r_fixed, cbind(NA, -9999))
out <- tempfile(fileext=".tif")
terra::writeRaster(seasonal_out, out, overwrite=TRUE, NAflag=-9999)

r_load <- terra::rast(out)
cat("Final Min/max:", terra::minmax(r_load), "\n")
