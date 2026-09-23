# Rwapor live remote smoke test
# =============================================================================
# Runs the seasonal engine, wapor_ts() and wapor_map() against the live WaPOR
# API and checks that memory and tiled modes agree on real remote COGs.
#
# Usage:
#   Rscript remote_smoke_test.R [pkg_path]
#
#   pkg_path  Optional package source to load with pkgload (default: the
#             installed Rwapor).
#
# Needs internet access and a GDAL build with curl (see
# wapor_remote_capabilities()). Takes a few minutes.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) && nzchar(args[1])) {
  pkgload::load_all(args[1], quiet = TRUE)
} else {
  library(Rwapor)
}

results <- list()
check <- function(name, expr) {
  t0 <- proc.time()[["elapsed"]]
  out <- tryCatch({
    detail <- force(expr)
    list(status = "PASS", detail = detail)
  }, error = function(e) list(status = "FAIL", detail = conditionMessage(e)))
  out$seconds <- proc.time()[["elapsed"]] - t0
  results[[name]] <<- out
  cat(sprintf("[%s] %-48s %6.1fs  %s\n", out$status, name, out$seconds, paste(out$detail, collapse = " ")))
  invisible(out)
}

caps <- wapor_remote_capabilities(refresh = TRUE)
cat("GDAL remote capability:", caps$message, "\n\n")

farm <- c(35.95, 33.80, 36.00, 33.85)           # about 5 km x 5 km, Bekaa valley
period <- c("2023-06-01", "2023-06-30")
cp <- data.frame(class_value = 1L, crop_label = "Crop", kc_ini = 0.5, kc_mid = 1.1, kc_end = 0.7,
                 l_ini_days = 10L, l_mid_days = 10L, l_late_days = 10L,
                 HI = 0.4, MC = 0.1, fc = 1, AOT = 1)

run_engine <- function(aeti_var, ret_var, processing, tile_size = NULL, l3_code = NULL) {
  config <- list(
    period = period, data_source = "api", l3_code = l3_code,
    aeti_var = aeti_var, ret_var = ret_var,
    indicators = c("agg_aeti", "agg_ret", "etc", "adequacy_etc"),
    use_crop_mask = FALSE, use_season_rasters = FALSE,
    processing = processing, tile_size = tile_size,
    output_dir = tempfile(paste0("smoke-", processing, "-"))
  )
  suppressMessages(wapor_run_seasonal_analysis(config, cp, rasters = list(), aoi_region = farm))
}
summarise <- function(res) {
  a <- terra::global(res$seasonal_aeti$raster, c("mean", "notNA"), na.rm = TRUE)
  sprintf("mode=%s cells=%d AETI mean=%.2f mm, paths=%s", res$processing$mode,
          as.integer(a$notNA), a$mean, paste(res$processing_run$aggregation_paths, collapse = "/"))
}

l1_mem <- NULL
check("L1 farm seasonal analysis (auto)", {
  l1_mem <<- run_engine("L1-AETI-D", "L1-RET-D", "auto")
  summarise(l1_mem)
})
check("L1 farm tiled equals memory", {
  til <- run_engine("L1-AETI-D", "L1-RET-D", "tiled", tile_size = 8L)
  a <- as.numeric(terra::values(l1_mem$seasonal_aeti$raster))
  b <- as.numeric(terra::values(til$seasonal_aeti$raster))
  e <- as.numeric(terra::values(l1_mem$adequacy_etc))
  f <- as.numeric(terra::values(til$adequacy_etc))
  stopifnot(identical(is.na(a), is.na(b)), isTRUE(all.equal(a, b, tolerance = 1e-6)),
            isTRUE(all.equal(e, f, tolerance = 1e-6)))
  sprintf("%d tiles, max |diff| %.2g", til$processing_run$n_tiles, max(abs(a - b), na.rm = TRUE))
})
check("L3 20 m farm seasonal analysis (auto)", {
  # Reference ET is published at L1 only; L3 AETI with L1 RET exercises the
  # native-resolution path (RET summed on its own grid, resampled once).
  res <- run_engine("L3-AETI-D", "L1-RET-D", "auto", l3_code = "BKA")
  summarise(res)
})
check("wapor_ts bbox time series", {
  df <- suppressMessages(wapor_ts(farm, "L1-AETI-D", period))
  stopifnot(nrow(df) >= 3, all(is.finite(df$mean)))
  sprintf("%d rows, mean AETI %.2f", nrow(df), mean(df$mean))
})
check("wapor_map download", {
  out <- suppressMessages(wapor_map(farm, "L1-AETI-D", period, folder = tempfile("smoke-map-")))
  r <- terra::rast(out$output_paths)
  sprintf("%d layers, %d x %d cells", terra::nlyr(r), terra::nrow(r), terra::ncol(r))
})

n_fail <- sum(vapply(results, function(r) identical(r$status, "FAIL"), logical(1)))
cat(sprintf("\n%d check(s), %d failed.\n", length(results), n_fail))
if (n_fail) quit(status = 1, save = "no")
