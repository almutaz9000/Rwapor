# Integrated Savola Analysis Pipeline
# This script demonstrates the full workflow: Download -> Mask Generation -> Seasonal Analysis -> Export

# 1. Setup Environment
library(Rwapor)
library(terra)

# Configuration
project_folder <- "C:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Desktop/wapor_data/Savola"
aoi_path       <- file.path(project_folder, "Pivots_savola2.geojson")
csv_path       <- file.path(project_folder, "Sugarbeet_Pivots_data.csv")
output_dir     <- file.path(project_folder, "Analysis_Outputs")

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# 2. Download Data (Inputs)
variables <- c("L3-AETI-D", "L3-T-D", "L1-RET-D", "L1-PCP-D", "L3-NPP-D")
period    <- c("2023-10-01", "2024-05-31")

message("--- Step 1: Downloading/Verifying Data ---")
# In local test mode, we skip downloading but ensure files are matched
for (v in variables) {
  # message(sprintf("Verifying local data for %s...", v))
  # wapor_map(variable = v, period = period, region = aoi_path, folder = project_folder, separate_files = TRUE)
}

# 3. Generate Timing Masks (Pre-processing)
message("--- Step 2: Generating Seasonal Timing Masks ---")

# Get a template raster from one of the downloaded files
aeti_files <- list.files(file.path(project_folder, "L3-AETI-D"), pattern = "\\.tif$", full.names = TRUE)
if (length(aeti_files) == 0) stop("No AETI data found in project folder.")
template_r <- terra::rast(aeti_files[1])

masks_registry <- wapor_vector_to_season_rasters(
  vector_path   = aoi_path,
  csv_path      = csv_path,
  template_r    = template_r,
  vector_id_col = "Name",
  csv_id_col    = "Name",
  season_col    = "Season",
  start_col     = "PlantingDate",
  end_col       = "HavestDate",
  crop_col      = "Crop",
  output_folder = file.path(project_folder, "Generated_Masks")
)

# 4. Run Seasonal Analysis (Engine)
message("--- Step 3: Running Seasonal Analysis ---")

# Define Indicators to calculate
indicators <- c(
  "agg_aeti", "agg_t", "agg_pcp", 
  "adequacy_etc", "beneficial_fraction", "yield_npp"
)

# Process the identified season (Season_23_24)
season_to_run <- "Season_23_24"
mask_info <- masks_registry[masks_registry$season == season_to_run, ]

# Setup Engine Configuration
config <- list(
  period      = period,
  aeti_var    = "L3-AETI-D",
  ret_var     = "L1-RET-D",
  precip_var  = "L1-PCP-D",
  npp_var     = "L3-NPP-D",
  t_var       = "L3-T-D",
  data_source = "local",
  folder      = project_folder,
  indicators  = indicators,
  use_crop_mask      = TRUE,
  use_season_rasters = TRUE
)

# Load the generated masks
rasters <- list(
  crop_mask    = terra::rast(mask_info$crop_mask),
  season_start = terra::rast(mask_info$start_raster),
  season_end   = terra::rast(mask_info$end_raster)
)

# Build crop assignments based on classes in the generated mask
classes <- unique(terra::values(rasters$crop_mask, na.rm=TRUE))
crop_params <- wapor_build_crop_assignments(classes)
# Optionally update labels from CSV/Vector if needed, but defaults are fine for testing

# Execute
results <- wapor_run_seasonal_analysis(
  config      = config,
  crop_params = crop_params,
  rasters     = rasters,
  progress_callback = function(v, m) message(sprintf("[%d%%] %s", round(v*100), m))
)

# 5. Export Results (Outputs)
message("--- Step 4: Exporting Results ---")

# Save spatial rasters
for (ind in names(results)) {
  if (inherits(results[[ind]], "SpatRaster")) {
    out_path <- file.path(output_dir, paste0(season_to_run, "_", ind, ".tif"))
    terra::writeRaster(results[[ind]], out_path, overwrite=TRUE)
    message(sprintf("Saved indicator raster: %s", basename(out_path)))
  }
}

# Save tabular statistics
if (!is.null(results$seasonal_aeti$by_class)) {
  stats_path <- file.path(output_dir, paste0(season_to_run, "_stats.csv"))
  write.csv(results$seasonal_aeti$by_class, stats_path, row.names = FALSE)
  message(sprintf("Saved stats CSV: %s", basename(stats_path)))
}

message("--- Pipeline Completed Successfully ---")
