suppressPackageStartupMessages(library(terra))
suppressPackageStartupMessages(library(sf))
devtools::load_all('.')

out_folder <- "C:/Users/almut/Desktop/WaPOR_Seasonal_L3"
citrus_farms <- sf::st_read("C:/Users/almut/OneDrive/Documents/GitHub/Classification/Data/Vectors/Citrus_farms_final.geojson", quiet=TRUE)

seasonal_map_paths <- tryCatch({
  wapor_map(
      region = citrus_farms,
      variable = "L3-AETI-D",             
      period = c("2023-01-01", "2023-03-31"),
      folder = out_folder,
      seasonal = TRUE,
      parallel = FALSE
  )
}, error = function(e) {
  cat("Error: ", e$message, "\n")
  NULL
})

if (!is.null(seasonal_map_paths)) {
  r <- terra::rast(seasonal_map_paths[1])
  cat("NA count:", terra::global(is.na(r), "sum")[[1]], "\n")
  cat("NaN count:", terra::global(terra::app(r, is.nan), "sum")[[1]], "\n")
  cat("Zero count:", terra::global(r == 0, "sum", na.rm=TRUE)[[1]], "\n")
  cat("Neg9999 count:", terra::global(r == -9999, "sum", na.rm=TRUE)[[1]], "\n")
  cat("Min/max:", terra::minmax(r), "\n")
}
