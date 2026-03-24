# library(Rwapor)
source("tests/load_source.R")
library(terra)
cat("\n--- Terra Functions ---\n")
print(grep("meta", ls("package:terra"), value = TRUE))

# Use a small bbox in Ethiopia
region <- c(38.5, 8.5, 38.6, 8.6)
variable <- "L1-AETI-D"
period <- c("2023-01-01", "2023-01-01") # Just one day
folder <- "test_metadata"

# Download
out_file <- wapor_map(
  region = region,
  variable = variable,
  period = period,
  folder = folder,
  filename = "test_meta.tif"
)

# Download seasonal
out_file_seasonal <- wapor_map(
  region = region,
  variable = variable,
  period = period,
  folder = folder,
  seasonal = TRUE
)

# Inspect non-seasonal
r <- terra::rast(out_file)
cat("\n--- Non-Seasonal Raster Metadata ---\n")
print(terra::units(r))
print(terra::metags(r))

# Inspect seasonal
r_s <- terra::rast(out_file_seasonal)
cat("\n--- Seasonal Raster Metadata ---\n")
print(terra::units(r_s))
print(terra::metags(r_s))
