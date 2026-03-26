# tests/test_analysis_all_indicators.R
# Test script for all indicators with sample rasters

if (nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))) {
  message("Skipping standalone all-indicators analysis script during R CMD check.")
  quit(save = "no", status = 0)
}

test_root <- if (file.exists("load_source.R")) "." else "tests"
if (!requireNamespace("Rwapor", quietly = TRUE)) {
  source(file.path(test_root, "load_source.R"))
} else {
  library(Rwapor)
}
library(terra)
library(sf)
library(lubridate)

# 1. Setup paths
mask_path <- "rasters_inputs_samples/crop_mask.tif"
start_path <- "rasters_inputs_samples/season_start_jday.tif"
end_path <- "rasters_inputs_samples/season_end_jday_extended.tif"
output_dir <- "output_all_indicators"
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# 2. Parameters
aeti_var <- "L3-AETI-D"
ret_var <- "L1-RET-D"
precip_var <- "L1-PCP-D"
npp_var <- "L1-NPP-D"
ref_year <- 2021
period <- c("2021-01-01", "2021-12-31")

# 3. Load input rasters
cat("Loading sample rasters...\n")
crop_mask <- rast(mask_path)
season_start <- rast(start_path)
season_end <- rast(end_path)

# 4. Resolve L3 region
cat("Resolving L3 region...\n")
reg_info <- wapor_parse_region(mask_path)
l3_code <- guess_l3_region(aeti_var, reg_info, period)[1]
cat("Detected L3 Region:", l3_code, "\n")

# 5. Load Template & Harmonize
cat("Fetching template and harmonizing...\n")
cat("Using L3 Code:", l3_code, "\n")
ref_urls <- wapor_generate_urls(aeti_var, l3_region = l3_code, period = period)
cat("Ref URLs found:", length(ref_urls), "\n")
if(length(ref_urls)>0) cat("First Ref URL:", ref_urls[1], "\n")

r_raw <- rast(paste0("/vsicurl/", ref_urls[1]))
cat("Raster name:", basename(ref_urls[1]), "\n")
cat("Raster extent (raw):", paste(as.vector(ext(r_raw)), collapse=", "), "\n")
cat("Mask extent (4326):", paste(as.vector(reg_info$value), collapse=", "), "\n")
template_r <- crop_to_region(r_raw, reg_info)

h_mask <- wapor_harmonize_crop_mask(crop_mask, template_r)
h_start <- wapor_harmonize_raster(season_start, template_r)
h_end <- wapor_harmonize_raster(season_end, template_r)

# Check alignment
cat("Template Dim:", paste(dim(template_r), collapse="x"), "\n")
cat("Mask Dim:", paste(dim(h_mask), collapse="x"), "\n")
cat("Start Dim:", paste(dim(h_start), collapse="x"), "\n")
cat("End Dim:", paste(dim(h_end), collapse="x"), "\n")

if(!compareGeom(template_r, h_mask, stopOnError=FALSE)) cat("WARN: Template and Mask mismatch!\n")

# 6. Crop Parameters
# Wheat (1), Sugarbeet (2)
crop_params <- data.frame(
  class_value = c(1, 2),
  crop_name = c("Wheat", "Sugarbeet"),
  l_ini_days = c(20, 25),
  L_dev_days = c(50, 45),
  l_mid_days = c(70, 80),
  l_late_days = c(40, 50),
  kc_ini = c(0.3, 0.35),
  kc_mid = c(1.15, 1.2),
  kc_end = c(0.4, 0.7),
  HI = c(0.45, 0.7),
  AOT = c(0.85, 0.8),
  fc = c(0.48, 0.5),
  MC = c(0.12, 0.15),
  stringsAsFactors = FALSE
)

# 7. Build Season Weights
cat("Building season weights...\n")
sw <- wapor_build_season_weights(period[1], period[2], h_start, h_end, ref_year)

# 8. Load Data Stacks (Streaming)
cat("Streaming data stacks...\n")
load_stack <- function(var, l3 = NULL) {
  urls <- wapor_generate_urls(var, l3_region = l3, period = period)
  cat("Loading", var, "(", length(urls), "layers)...\n")
  s <- rast(paste0("/vsicurl/", urls))
  s <- crop_to_region(s, reg_info)
  # MUST harmonize to template resolution (20m) for calculations
  s <- wapor_harmonize_raster(s, template_r)
  meta <- get_variable_metadata(var)
  if (!is.null(meta$scale)) s <- s * meta$scale
  s
}

aeti_stack <- load_stack(aeti_var, l3_code)
ret_stack <- load_stack(ret_var)
pcp_stack <- load_stack(precip_var)
npp_stack <- load_stack(npp_var)

# 9. Compute Indicators
cat("Computing Indicators...\n")
results <- list()

# Seasonal AETI
results$seasonal_aeti <- wapor_calc_seasonal_aeti(aeti_stack, sw$weights)

# Seasonal RET
results$seasonal_ret <- wapor_calc_seasonal_ret(ret_stack, sw$weights)

# Seasonal PCP
results$seasonal_pcp <- wapor_masked_sum(pcp_stack, sw$weights)

# Seasonal ETc (Incremental)
total_days_r <- wapor_season_days(h_start, h_end)
mean_total_days <- as.numeric(global(total_days_r, "mean", na.rm = TRUE)[1,1])
total_days_vec <- setNames(rep(mean_total_days, nrow(crop_params)), as.character(crop_params$class_value))
kc_by_class <- wapor_build_kc_by_class(crop_params, total_days_vec)

results$etc_by_class <- list()
for (i in seq_len(nrow(crop_params))) {
  cls <- as.character(crop_params$class_value[i])
  cat("  Computing ETc for class", cls, "...\n")
  
  # Aggregate daily Kc to dekads matching the stack
  # Use period[1] as anchor for temporal alignment
  kc_dekad <- wapor_aggregate_kc(kc_by_class[[cls]], sw$dekad_table, period[1])
  
  class_mask <- ifel(h_mask == as.integer(cls), 1L, NA)
  etc_inc <- wapor_calc_seasonal_etc(ret_stack, sw$weights, kc_dekad)
  results$etc_by_class[[cls]] <- list(etc_seasonal = etc_inc * class_mask)
}

# Adequacy P95
p95_table <- wapor_calc_p95_aeti(results$seasonal_aeti$raster, h_mask)
results$adequacy_p95 <- wapor_calc_adequacy_p95(results$seasonal_aeti$raster, h_mask, p95_table)

# Biomass
results$seasonal_biomass <- wapor_masked_sum(npp_stack, sw$weights) * 22.222

# 10. Save Rasters
cat("Saving results to", output_dir, "...\n")
writeRaster(results$seasonal_aeti$raster, file.path(output_dir, "seasonal_aeti.tif"), overwrite = TRUE)
writeRaster(results$seasonal_ret$raster, file.path(output_dir, "seasonal_ret.tif"), overwrite = TRUE)
writeRaster(results$seasonal_pcp, file.path(output_dir, "seasonal_pcp.tif"), overwrite = TRUE)
writeRaster(results$adequacy_p95, file.path(output_dir, "adequacy_p95.tif"), overwrite = TRUE)
writeRaster(results$seasonal_biomass, file.path(output_dir, "seasonal_biomass.tif"), overwrite = TRUE)

for (cls in names(results$etc_by_class)) {
  writeRaster(results$etc_by_class[[cls]]$etc_seasonal, 
              file.path(output_dir, paste0("seasonal_etc_class_", cls, ".tif")), overwrite = TRUE)
}

cat("Test complete!\n")
