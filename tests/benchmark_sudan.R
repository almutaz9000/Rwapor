# Benchmark: Sudan bbox, 4 years dekadal (~144 rasters) using wapor_ts
#
# Tests batched processing in wapor_ts with a large country and long time series.

# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------
if (nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))) {
  message("Skipping standalone Sudan benchmark during R CMD check.")
  quit(save = "no", status = 0)
}

test_root <- if (file.exists("load_source.R")) "." else "tests"
if (!requireNamespace("Rwapor", quietly = TRUE)) {
  source(file.path(test_root, "load_source.R"))
} else {
  library(Rwapor)
}

# --- Configuration ---
# Sudan approx bbox (large country)
sudan_bbox <- c(21.8, 8.7, 38.6, 22.2)

variable  <- "L1-AETI-D"
period    <- c("2020-01-01", "2023-12-31")  # 4 full years

cat("=== Benchmark: Sudan bbox, L1-AETI-D, 2020-2023 ===\n")
cat(sprintf("Expected ~144 dekadal rasters over a large bbox\n\n"))

# ------------------------------------------------------------------
# PHASE 1: URL generation (tests memoisation benefit)
# ------------------------------------------------------------------
cat("--- Phase 1: URL generation ---\n")
t1 <- proc.time()
urls <- wapor_generate_urls(variable, period = period)
t1_elapsed <- (proc.time() - t1)[["elapsed"]]
cat(sprintf("  Found %d URLs in %.1f s\n", length(urls), t1_elapsed))

# Second call – should be instant if memoisation works
t1b <- proc.time()
urls2 <- wapor_generate_urls(variable, period = period)
t1b_elapsed <- (proc.time() - t1b)[["elapsed"]]
cat(sprintf("  Memoised re-call: %.3f s (should be ~0)\n\n", t1b_elapsed))

# ------------------------------------------------------------------
# PHASE 2: Full wapor_ts() with batching (batch_size=36, default)
# ------------------------------------------------------------------
cat("--- Phase 2: wapor_ts() with batch_size=36 (default, ~1 year per batch) ---\n")
gc(verbose = FALSE)
mem_before <- gc(verbose = FALSE)

t2 <- proc.time()
tryCatch({
  ts_result <- wapor_ts(
    region   = sudan_bbox,
    variable = variable,
    period   = period
  )
  t2_elapsed <- (proc.time() - t2)[["elapsed"]]
  cat(sprintf("  Completed: %d rows in %.1f s\n", nrow(ts_result), t2_elapsed))
  cat(sprintf("  Units: %s\n", attr(ts_result, "units")))
  cat(sprintf("  Date range: %s to %s\n",
              min(ts_result$start_date), max(ts_result$start_date)))
  cat("  Head:\n")
  print(head(ts_result, 3))
  cat("  Tail:\n")
  print(tail(ts_result, 3))
}, error = function(e) {
  t2_elapsed <- (proc.time() - t2)[["elapsed"]]
  cat(sprintf("  FAILED after %.1f s: %s\n", t2_elapsed, e$message))
})

mem_after <- gc(verbose = FALSE)
cat(sprintf("\n  Memory: Used %.1f MB, Max used %.1f MB\n",
            sum(mem_after[, 2]), sum(mem_after[, 6])))

# ------------------------------------------------------------------
# PHASE 3: Compare with smaller batch_size=12 (~4 months per batch)
# ------------------------------------------------------------------
cat("\n--- Phase 3: wapor_ts() with batch_size=12 (~4 months per batch) ---\n")

# Clear memoised URL cache is not needed since URLs are the same
gc(verbose = FALSE)

t3 <- proc.time()
tryCatch({
  ts_result_small <- wapor_ts(
    region     = sudan_bbox,
    variable   = variable,
    period     = period,
    batch_size = 12L
  )
  t3_elapsed <- (proc.time() - t3)[["elapsed"]]
  cat(sprintf("  Completed: %d rows in %.1f s\n", nrow(ts_result_small), t3_elapsed))

  # Verify results match
  if (exists("ts_result") && exists("ts_result_small")) {
    max_diff <- max(abs(ts_result$mean - ts_result_small$mean), na.rm = TRUE)
    cat(sprintf("  Max mean difference vs batch_size=36: %e (should be 0)\n", max_diff))
  }
}, error = function(e) {
  t3_elapsed <- (proc.time() - t3)[["elapsed"]]
  cat(sprintf("  FAILED after %.1f s: %s\n", t3_elapsed, e$message))
})

mem_small <- gc(verbose = FALSE)
cat(sprintf("  Memory: Used %.1f MB, Max used %.1f MB\n",
            sum(mem_small[, 2]), sum(mem_small[, 6])))

cat("\n=== Benchmark complete ===\n")
