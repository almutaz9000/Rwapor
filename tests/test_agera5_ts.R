# Test: AgERA5 Timeseries Extraction
#
# Verifies wapor_ts() with AgERA5 climate variables.

library(Rwapor)
library(sf)

# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------
# Test region: Rectangle in Sudan
test_bbox <- c(32.5, 15.5, 33.0, 16.0)

cat("=== Testing AgERA5 Timeseries Extraction ===\n")
cat(sprintf("Test region: %s\n\n", paste(test_bbox, collapse = ", ")))

# ------------------------------------------------------------------
# Test 1: Daily Min Temperature (AGERA5-TMIN-E)
# ------------------------------------------------------------------
cat("--- Test 1: Daily Min Temperature (AGERA5-TMIN-E) ---\n")
var_e <- "AGERA5-TMIN-E"
period_e <- c("2023-01-01", "2023-01-05") # 5 days

t1 <- proc.time()
df_e <- wapor_ts(
  region   = test_bbox,
  variable = var_e,
  period   = period_e
)
cat(sprintf("  Extraction completed in %.1f s\n", (proc.time() - t1)[["elapsed"]]))

if (is.data.frame(df_e)) {
  cat(sprintf("  Results rows: %d (expected 5)\n", nrow(df_e)))
  cat(sprintf("  Units: %s\n", attr(df_e, "units")))
  cat("  Head:\n")
  print(head(df_e, 3))
  # AgERA5 TMIN is in Kelvin
  if (all(df_e$mean > 200 & df_e$mean < 320, na.rm = TRUE)) {
    cat("  Values look reasonable for Kelvin.\n")
  } else {
    cat("  WARNING: Values outside typical Kelvin range.\n")
  }
} else {
  cat("  FAILED: Result is not a data frame.\n")
}

# ------------------------------------------------------------------
# Test 2: Monthly ET0 (AGERA5-ET0-M)
# ------------------------------------------------------------------
cat("\n--- Test 2: Monthly ET0 (AGERA5-ET0-M) ---\n")
var_m <- "AGERA5-ET0-M"
period_m <- c("2023-01-01", "2023-03-31") # 3 months

t2 <- proc.time()
df_m <- wapor_ts(
  region   = test_bbox,
  variable = var_m,
  period   = period_m
)
cat(sprintf("  Extraction completed in %.1f s\n", (proc.time() - t2)[["elapsed"]]))

if (is.data.frame(df_m)) {
  cat(sprintf("  Results rows: %d (expected 3)\n", nrow(df_m)))
  cat(sprintf("  Units: %s\n", attr(df_m, "units")))
  cat("  Head:\n")
  print(head(df_m, 3))
} else {
  cat("  FAILED: Result is not a data frame.\n")
}

cat("\n=== AgERA5 Timeseries Test Complete ===\n")
