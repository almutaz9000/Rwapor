suppressPackageStartupMessages(library(terra))
devtools::load_all('.')

urls <- wapor_generate_urls("L3-AETI-D", period=c("2023-01-01", "2023-01-10"))

# Just grab one URL
url <- paste0("/vsicurl/", urls[1])
r <- terra::rast(url)
cat("Raster CRS:\n")
cat(terra::crs(r), "\n\n")

cat("Trying to project extent bounds manually:\n")
ext_vals <- as.vector(terra::ext(r))
xy <- matrix(c(ext_vals[1], ext_vals[3], ext_vals[2], ext_vals[4]), ncol=2)
v <- terra::vect(xy, type="points", crs=terra::crs(r))
v_4326 <- tryCatch(terra::project(v, "EPSG:4326"), error=function(e) cat("Project error: ", e$message, "\n"))
cat("V_4326 representation:\n")
print(v_4326)
