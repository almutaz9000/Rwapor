# Rwapor disk-footprint benchmark
# =============================================================================
# Measures run time, terra temporary files, output_dir and export size of one
# wapor_run_seasonal_analysis() + wapor_export_analysis_outputs() run on
# synthetic local data (BENCH_N x BENCH_N cells, 18 dekads, 5 variables,
# 2 crop classes, per-pixel seasons, 14 indicators).
#
# Usage:
#   Rscript disk_footprint_benchmark.R <pkg_path> <label> [default|TRUE|FALSE]
#   env BENCH_N    grid side in cells (default 1000)
#   env BENCH_ROOT folder for the generated inputs (reused between runs)
# The third argument sets config$keep_intermediates.
# Reference results: docs/superpowers/plans/2026-09-28-production-readiness-plan.md
args <- commandArgs(trailingOnly = TRUE)
pkg <- args[[1]]; label <- args[[2]]
keep <- if (length(args) >= 3) args[[3]] else "default"
suppressMessages(pkgload::load_all(pkg, quiet = TRUE))

dir_mb <- function(p) {
  f <- list.files(p, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  round(sum(file.info(f)$size, na.rm = TRUE) / 1024^2, 1)
}

n <- as.integer(Sys.getenv("BENCH_N", "1000"))
root <- file.path(Sys.getenv("BENCH_ROOT", tempdir()), "data")
period <- c("2023-01-01", "2023-06-30")
if (!dir.exists(root)) {
  set.seed(1)
  dir.create(root, recursive = TRUE)
  template <- terra::rast(nrows = n, ncols = n, xmin = 0, xmax = 1, ymin = 0, ymax = 1, crs = "EPSG:4326")
  coarse <- terra::rast(nrows = 20, ncols = 20, xmin = -0.1, xmax = 1.1, ymin = -0.1, ymax = 1.1, crs = "EPSG:4326")
  dekads <- Rwapor:::build_dekad_table(period[1], period[2])$dekad_key
  write_var <- function(var, grid, lo, hi, dt) {
    d <- file.path(root, var); dir.create(d)
    for (k in dekads) {
      terra::writeRaster(terra::setValues(grid, stats::runif(terra::ncell(grid), lo, hi)),
        file.path(d, sprintf("WAPOR-3.%s.%s.tif", var, format(as.Date(k), "%Y-%m-%d"))),
        datatype = dt, gdal = "COMPRESS=LZW")
    }
  }
  write_var("L1-AETI-D", template, 1, 5, "FLT4S")
  write_var("L1-NPP-D", template, 10, 60, "FLT4S")
  write_var("L1-T-D", template, 0.5, 3, "FLT4S")
  write_var("L1-RET-D", coarse, 2, 6, "FLT4S")
  write_var("L1-PCP-D", coarse, 0, 8, "FLT4S")
  terra::writeRaster(terra::setValues(template, rep(c(1L, 2L), length.out = n * n)),
                     file.path(root, "mask.tif"), datatype = "INT1U")
}
template <- terra::rast(file.path(root, "mask.tif"))
ref_year <- 2023L
s0 <- wapor_continuous_julian(period[1], ref_year); e0 <- wapor_continuous_julian(period[2], ref_year)
rasters <- list(
  crop_mask = template,
  season_start = terra::setValues(template, rep(c(s0, s0 + 20), length.out = n * n)),
  season_end = terra::setValues(template, rep(c(e0, e0 - 30), length.out = n * n))
)
crop_params <- data.frame(
  class_value = c(1L, 2L), crop_label = c("A", "B"),
  kc_ini = c(0.5, 0.4), kc_mid = c(1.1, 1.2), kc_end = c(0.7, 0.6),
  l_ini_days = c(30L, 20L), l_mid_days = c(60L, 50L), l_late_days = c(40L, 30L),
  HI = c(0.4, 0.5), MC = c(0.1, 0.12), fc = c(0.9, 1), AOT = c(1, 1)
)
out <- tempfile("bench-out-")
tmp_terra <- tempfile("bench-terra-"); dir.create(tmp_terra)
terra::terraOptions(tempdir = tmp_terra, progress = 0)
config <- list(
  period = period, ref_year = ref_year,
  aeti_var = "L1-AETI-D", ret_var = "L1-RET-D", precip_var = "L1-PCP-D",
  npp_var = "L1-NPP-D", t_var = "L1-T-D", data_source = "local", folder = root,
  indicators = c("agg_aeti", "agg_ret", "agg_pcp", "agg_peff", "etc", "adequacy_etc",
                 "agg_t", "beneficial_fraction", "agg_biomass_kg", "yield_npp",
                 "green_water", "blue_water", "cwp_bwp", "adequacy_p95"),
  use_crop_mask = TRUE, use_season_rasters = TRUE, output_dir = out
)
if (keep != "default") config$keep_intermediates <- as.logical(keep)

gc(reset = TRUE)
t0 <- proc.time()[["elapsed"]]
res <- suppressMessages(wapor_run_seasonal_analysis(config, crop_params, rasters))
t_run <- proc.time()[["elapsed"]] - t0
mem_mb <- sum(gc()[, 6])
exp_dir <- tempfile("bench-export-")
t1 <- proc.time()[["elapsed"]]
suppressWarnings(suppressMessages(
  wapor_export_analysis_outputs(res, exp_dir, indicators = config$indicators, season_label = "S1")
))
t_exp <- proc.time()[["elapsed"]] - t1
tifs <- list.files(exp_dir, "\\.tif$", recursive = TRUE, full.names = TRUE)
dtypes <- table(vapply(tifs, function(f) terra::datatype(terra::rast(f))[1], ""))
cat(sprintf(
  "RESULT %s | keep=%s | cells=%d | run %.1fs | export %.1fs | peak R heap %.0f MB | terra temp %.1f MB | output_dir %.1f MB | export %.1f MB (%d tif; %s) | dekadal_stacks kept: %s | AETI mean %.6f\n",
  label, keep, n * n, t_run, t_exp, mem_mb, dir_mb(tmp_terra), dir_mb(out), dir_mb(exp_dir),
  length(tifs), paste(names(dtypes), dtypes, sep = "=", collapse = ","),
  !is.null(res$dekadal_stacks),
  terra::global(res$seasonal_aeti$raster, "mean", na.rm = TRUE)$mean
))
