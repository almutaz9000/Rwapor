# Test Analysis with Sample Rasters
# ---------------------------------
# This script verifies the optimized analysis engine using the user-provided sample rasters.
# Crops: Winter Wheat (Class 1), Sugarbeet (Class 2)

# Load package source
source("c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor/tests/load_source.R")
library(terra)
library(lubridate)

# Ensure PROJ is fixed
if (exists("wapor_fix_proj")) wapor_fix_proj(verbose = TRUE)

# 1. Inputs
raster_dir <- "c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor/tests/rasters_inputs_samples"
crop_mask_path <- file.path(raster_dir, "crop_mask.tif")
s_start_path  <- file.path(raster_dir, "season_start_jday.tif")
s_end_path    <- file.path(raster_dir, "season_end_jday_extended.tif")

# 2. Parameters
# Winter Wheat (Class 1)
# Sugarbeet (Class 2)
ref_year <- 2020
period <- c("2020-09-01", "2021-08-31")

crop_params <- data.frame(
  class_value = c(1, 2),
  crop_name   = c("Winter Wheat", "Sugarbeet"),
  L_ini_days  = c(20, 30),
  L_mid_days  = c(70, 90),
  L_late_days = c(30, 15),
  Kc_ini      = c(0.70, 0.35),
  Kc_mid      = c(1.15, 1.20),
  Kc_end      = c(0.25, 0.70),
  HI   = c(0.40, 0.70), # Harvesting Index
  AOT  = c(0.85, 0.85),
  MC   = c(0.12, 0.75),
  fc   = c(0.34, 0.34),
  stringsAsFactors = FALSE
)

# 3. Load Rasters
cat("\n--- Loading Rasters ---\n")
h_mask <- rast(crop_mask_path)
h_start <- rast(s_start_path)
h_end <- rast(s_end_path)

# 4. Step 1: Build Season Weights
cat("\n--- Step 1: Building Season Weights ---\n")
sw <- rwapor_build_season_weights_dekad(period[1], period[2], h_start, h_end, ref_year)
print(sw$weights)

# 5. Step 2: Build Kc Curves
cat("\n--- Step 2: Building Kc Curves ---\n")
mean_total_days <- 180 
total_days_vec <- setNames(rep(mean_total_days, nrow(crop_params)), as.character(crop_params$class_value))
kc_by_class <- rwapor_build_kc_by_class(crop_params, total_days_vec)

# 6. Step 3: Mock Data
n_layers <- nlyr(sw$weights)
cat(sprintf("Creating mock stacks with %d layers...\n", n_layers))
aeti_stack <- init(sw$weights, runif(n_layers, 20, 50))
names(aeti_stack) <- as.character(sw$dekad_table$dekad_start)
ret_stack <- init(sw$weights, runif(n_layers, 30, 60))
names(ret_stack) <- as.character(sw$dekad_table$dekad_start)

# 7. Step 4: Run Aggregations
cat("\n--- Step 3: Running Aggregations ---\n")
results_aeti <- rwapor_calc_seasonal_aeti_masked(aeti_stack, sw$weights, h_mask, incremental = TRUE)
print(results_aeti$by_class)

# Seasonal ETc (Incremental)
etc_by_class <- list()
for (j in seq_len(nrow(crop_params))) {
  cls <- as.character(crop_params$class_value[j])
  kc_daily <- kc_by_class[[cls]]
  v_dekad <- rwapor_aggregate_kc_dekad(kc_daily, sw$update_table %||% sw$dekad_table, period[1])
  
  # For the test, we need to match the actual n_layers
  v_dekad <- v_dekad[seq_len(n_layers)]
  
  etc_seasonal <- rwapor_calc_seasonal_etc_incremental(ret_stack, sw$weights, v_dekad)
  cls_mask <- ifel(h_mask == as.integer(cls), 1L, NA)
  etc_by_class[[cls]] <- etc_seasonal * cls_mask
}

# 8. Adequacy & P95
cat("\n--- Step 4: Final Indicators ---\n")
p95_tbl <- rwapor_calc_class_p95_aeti(results_aeti$raster, h_mask)
print(p95_tbl)

cat("\nAnalysis test with sample rasters complete.\n")
