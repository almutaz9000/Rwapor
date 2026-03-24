# Benchmark: Analysis Kernels (Baseline)
#
# This script measures performance for the three most computationally 
# expensive parts of the Rwapor analysis workflow.

if (nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))) {
  message("Skipping standalone benchmark script during R CMD check.")
  quit(save = "no", status = 0)
}

test_root <- if (file.exists("load_source.R")) "." else "tests"
print(.libPaths())
if (!requireNamespace("Rwapor", quietly = TRUE)) {
  source(file.path(test_root, "load_source.R"))
} else {
  library(Rwapor)
}
wapor_fix_proj(verbose = TRUE)
library(terra)
library(sf)

# ------------------------------------------------------------------
# 1. Setup Data
# ------------------------------------------------------------------
cat("=== Initializing Benchmark Data ===\n")

# Sudan-sized AOI (approx 1000x1000 pixels at 1km)
aoi_bbox <- c(xmin=22, ymin=9, xmax=38, ymax=22)
ext_aoi  <- terra::ext(aoi_bbox["xmin"], aoi_bbox["xmax"], aoi_bbox["ymin"], aoi_bbox["ymax"])
template <- terra::rast(ext_aoi, res=0.01, crs="EPSG:4326") # ~1km

# Mock Season Rasters (full overlap)
start_rast <- terra::init(template, fun=1)
end_rast   <- terra::init(template, fun=365)

# Mock Crop Mask (10 classes, distributed)
crop_mask <- terra::init(template, fun=function(x) rep(1:10, length.out=x))

# Mock AETI/RET stacks (36 dekads)
n_layers <- 36
aeti_stack <- terra::rast(lapply(1:n_layers, function(i) terra::init(template, fun=function(x) runif(x, 1, 5))))
ret_stack  <- terra::rast(lapply(1:n_layers, function(j) terra::init(template, fun=function(x) runif(x, 2, 6))))

# Crop Params (10 classes)
crop_params <- data.frame(
  class_value = 1:10,
  crop_label = paste("Crop", 1:10),
  L_ini_days = 20, L_dev_days = 30, L_mid_days = 60, L_late_days = 30,
  Kc_ini = 0.3, Kc_mid = 1.1, Kc_end = 0.5,
  HI = 0.45, MC = 0.12, fc = 1.0, AOT = 0.8
)

# ------------------------------------------------------------------
# KERNEL 1: Season Weights (Current: Daily Mask Approach)
# ------------------------------------------------------------------
cat("\n--- Kernel 1: Season Weights (36 dekads, 1000x1000 pixels) ---\n")
gc()
t1 <- proc.time()
sw <- rwapor_build_season_weights_dekad(
  "2021-01-01", "2021-12-31", 
  start_rast, end_rast, 
  reference_year = 2021
)
t1_elapsed <- (proc.time() - t1)[["elapsed"]]
cat(sprintf("  Wall time: %.2f s\n", t1_elapsed))
cat(sprintf("  Memory peak: %.1f MB\n", sum(gc()[, 6])))

# ------------------------------------------------------------------
# KERNEL 2: ETc-by-class (Current: Per-class Stack Logic)
# ------------------------------------------------------------------
cat("\n--- Kernel 2: ETc-by-class (10 classes, 36 layers) ---\n")
total_days_vec <- rep(140, 10) # fixed duration
names(total_days_vec) <- as.character(1:10)
kc_by_class <- rwapor_build_kc_by_class(crop_params, total_days_vec)

gc()
t2 <- proc.time()
# Simulate the loop in mod_analysis.R
etc_by_class <- list()
for (j in seq_len(nrow(crop_params))) {
  cls <- as.character(crop_params$class_value[j])
  kc_daily <- kc_by_class[[cls]]
  # NEW: Must aggregate to dekad first
  kc_dekad <- rwapor_aggregate_kc_dekad(kc_daily, sw$dekad_table, as.Date("2021-01-01"))
  
  # NEW: Use the optimized incremental accumulator
  etc_seasonal <- rwapor_calc_seasonal_etc_incremental(ret_stack, sw$weights, kc_dekad)
  etc_by_class[[cls]] <- etc_seasonal
}
t2_elapsed <- (proc.time() - t2)[["elapsed"]]
cat(sprintf("  Wall time: %.2f s\n", t2_elapsed))
cat(sprintf("  Memory peak: %.1f MB\n", sum(gc()[, 6])))

# ------------------------------------------------------------------
# KERNEL 3: Grouped P95 (Current: Per-class Masking)
# ------------------------------------------------------------------
cat("\n--- Kernel 3: Grouped P95 (10 classes, 1M pixels) ---\n")
seasonal_aeti <- terra::app(aeti_stack * sw$weights, fun="sum")

gc()
t3 <- proc.time()
p95_res <- rwapor_calc_class_p95_aeti(seasonal_aeti, crop_mask)
t3_elapsed <- (proc.time() - t3)[["elapsed"]]
cat(sprintf("  Wall time: %.2f s\n", t3_elapsed))
cat(sprintf("  Memory peak: %.1f MB\n", sum(gc()[, 6])))

cat("\n=== Baseline Benchmark Complete ===\n")
