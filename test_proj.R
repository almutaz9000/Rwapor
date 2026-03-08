suppressPackageStartupMessages(library(terra))
devtools::load_all('.')

cat("PROJ_LIB: ", Sys.getenv("PROJ_LIB"), "\n")
cat("PROJ_DATA: ", Sys.getenv("PROJ_DATA"), "\n")

# Try to unset
Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")

urls <- suppressWarnings(wapor_generate_urls("L3-AETI-D", period=c("2023-01-01", "2023-01-10")))
url <- paste0("/vsicurl/", urls[1])
r <- tryCatch(suppressWarnings(terra::rast(url)), error=function(e) NULL)

if (!is.null(r)) {
    r_ext <- terra::ext(r)
    r_poly <- terra::as.polygons(r_ext, crs=terra::crs(r))
    r_poly_4326 <- tryCatch(suppressWarnings(terra::project(r_poly, "EPSG:4326")), error=function(e) cat("Error: ", e$message, "\n"))
    print(r_poly_4326)
}
