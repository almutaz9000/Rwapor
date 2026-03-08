suppressPackageStartupMessages(library(terra))
suppressPackageStartupMessages(library(sf))
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

# explicitly replace NA with -9999 and set NAflag
s_clean <- terra::classify(s_app, cbind(NA, -9999))
terra::NAflag(s_clean) <- -9999

out <- tempfile(fileext=".tif")
terra::writeRaster(s_clean, out, overwrite=TRUE)
r_load <- terra::rast(out)

cat("Metadata NA flag loaded:", terra::NAflag(r_load), "\n")
cat("R NA count loaded:", terra::global(is.na(r_load), "sum")[[1]], "\n")
cat("NaN count loaded:", terra::global(terra::app(r_load, is.nan), "sum")[[1]], "\n")
cat("Min/max loaded:", terra::minmax(r_load), "\n")
