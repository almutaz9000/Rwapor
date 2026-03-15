# Test: AgERA5 Variables Download
#
# Verifies wapor_map() with AgERA5 climate variables.

library(Rwapor)
library(terra)

# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------
# Small test region in Ethiopia (Awash area)
test_bbox <- c(38.5, 8.5, 39.0, 9.0)
output_folder <- "tests/output_agera5"

if (!dir.exists(output_folder)) {
  dir.create(output_folder, recursive = TRUE)
}

cat("=== Testing AgERA5 Download ===\n")
cat(sprintf("Test region: %s\n\n", paste(test_bbox, collapse = ", ")))

# ------------------------------------------------------------------
# Test 1: Daily ET0 (Reference Evapotranspiration)
# ------------------------------------------------------------------
cat("--- Test 1: Daily ET0 (AGERA5-ET0-E) ---\n")
var_e <- "AGERA5-ET0-E"
period_e <- c("2023-01-01", "2023-01-03") # 3 days

t1 <- proc.time()
file_e <- wapor_map(
  region   = test_bbox,
  variable = var_e,
  period   = period_e,
  folder   = output_folder
)
cat(sprintf("  Download completed in %.1f s\n", (proc.time() - t1)[["elapsed"]]))
cat(sprintf("  Output file: %s\n", file_e))

if (file.exists(file_e)) {
  r_e <- terra::rast(file_e)
  cat(sprintf("  Raster layers: %d (expected 3)\n", terra::nlyr(r_e)))
  cat(sprintf("  Mean value: %.2f mm/day\n", terra::global(r_e, mean, na.rm = TRUE)$mean))
} else {
  cat("  FAILED: Output file not found.\n")
}

# ------------------------------------------------------------------
# Test 2: Monthly Precipitation (AGERA5-PF-M)
# ------------------------------------------------------------------
cat("\n--- Test 2: Monthly Precipitation (AGERA5-PF-M) ---\n")
var_m <- "AGERA5-PF-M"
period_m <- c("2023-01-01", "2023-02-28") # 2 months

t2 <- proc.time()
file_m <- wapor_map(
  region   = test_bbox,
  variable = var_m,
  period   = period_m,
  folder   = output_folder
)
cat(sprintf("  Download completed in %.1f s\n", (proc.time() - t2)[["elapsed"]]))
cat(sprintf("  Output file: %s\n", file_m))

if (file.exists(file_m)) {
  r_m <- terra::rast(file_m)
  cat(sprintf("  Raster layers: %d (expected 2)\n", terra::nlyr(r_m)))
  cat(sprintf("  Mean value: %.2f mm/month\n", terra::global(r_m, mean, na.rm = TRUE)$mean))
} else {
  cat("  FAILED: Output file not found.\n")
}

cat("\n=== AgERA5 Download Test Complete ===\n")
