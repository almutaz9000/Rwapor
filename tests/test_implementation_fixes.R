# Verify Download Module Fixes
# 1. Dual-stage download (Individual + Seasonal)
# 2. Vector-based masking using crop_mask.tif bbox

library(Rwapor)
library(terra)
library(sf)

# Setup
project_folder <- file.path(getwd(), "test_project_fixes")
dir.create(project_folder, showWarnings = FALSE)

# Use the existing crop_mask.tif from the project
mask_file <- "tests/rasters_inputs_samples/crop_mask.tif"
if (!file.exists(mask_file)) {
  stop("Crop mask file not found at tests/rasters_inputs_samples/crop_mask.tif")
}

# Create a vector from its extent
r_mask <- terra::rast(mask_file)
mask_vect <- sf::st_as_sfc(sf::st_bbox(sf::st_as_sf(terra::as.polygons(terra::ext(r_mask) , crs = terra::crs(r_mask)))))
test_vect_path <- file.path(project_folder, "crop_mask_bbox.geojson")
sf::st_write(mask_vect, test_vect_path, delete_dsn = TRUE, quiet = TRUE)

variable <- "L1-AETI-D"
period <- c("2023-01-01", "2023-01-31")

message("--- Starting Verification with Crop Mask BBox ---")

# Stage 1: Individual Files
message("Running Stage 1: Individual files...")
ind_paths <- wapor_map(
  region = test_vect_path,
  variable = variable,
  period = period,
  folder = project_folder,
  seasonal = FALSE,
  separate_files = TRUE,
  mask = TRUE
)

# Stage 2: Seasonal Aggregate
message("Running Stage 2: Seasonal aggregate...")
sea_path <- wapor_map(
  region = test_vect_path,
  variable = variable,
  period = period,
  folder = project_folder,
  seasonal = TRUE,
  separate_files = FALSE,
  mask = TRUE
)

message("--- Analysis of Results ---")

# Check if expected files exist
all_files <- list.files(project_folder, pattern = "\\.tif$", recursive = TRUE)
message(sprintf("Total TIFF files found: %d", length(all_files)))
print(all_files)

# Perform masking check on seasonal aggregate
r_sea <- terra::rast(sea_path)
message(sprintf("Output Raster Extent: %f, %f, %f, %f", 
                terra::ext(r_sea)$xmin, terra::ext(r_sea)$ymin, 
                terra::ext(r_sea)$xmax, terra::ext(r_sea)$ymax))

message("--- End of Verification ---")
