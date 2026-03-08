suppressPackageStartupMessages(library(terra))
suppressPackageStartupMessages(library(sf))
devtools::load_all('.')

# Clean PROJ vars for this session
Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")

urls <- wapor_generate_urls("L3-AETI-D", period=c("2023-01-01", "2023-01-10"))

citrus_farms <- sf::st_read("C:/Users/almut/OneDrive/Documents/GitHub/Classification/Data/Vectors/Citrus_farms_final.geojson")
bb_ext <- terra::ext(citrus_farms)
bb_poly <- terra::as.polygons(bb_ext, crs="EPSG:4326")

extracted_codes <- character()
unique_urls <- character()

for (u in urls) {
    fname <- tools::file_path_sans_ext(basename(u))
    parts <- strsplit(fname, "\\.")[[1]]
    if (length(parts) >= 4) {
      code <- parts[3] # REVERTED BACK TO 3
      if (!code %in% extracted_codes && nchar(code) == 3 && toupper(code) == code) {
        extracted_codes <- c(extracted_codes, code)
        unique_urls <- c(unique_urls, u)
      }
    }
}

cat("Found codes: ", paste(extracted_codes, collapse=", "), "\n")

intersecting_codes <- character()
for (i in seq_along(unique_urls)) {
    u <- unique_urls[i]
    code <- extracted_codes[i]
    vsi_url <- paste0("/vsicurl/", u)
    
    r <- tryCatch(suppressWarnings(terra::rast(vsi_url)), error = function(e) NULL)
    if (is.null(r)) next
    
    r_ext <- terra::ext(r)
    r_poly <- terra::as.polygons(r_ext, crs=terra::crs(r))
    r_poly_4326 <- suppressWarnings(terra::project(r_poly, "EPSG:4326"))
    
    intersects <- suppressWarnings(terra::is.related(r_poly_4326, bb_poly, "intersects"))
    if (intersects) intersecting_codes <- c(intersecting_codes, code)
}

cat("Intersects with: ", paste(intersecting_codes, collapse=", "), "\n")
