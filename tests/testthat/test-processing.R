# =============================================================================
# Size-aware processing: planner, shared kernel, mode equivalence, accuracy
# =============================================================================

# A 12 x 12 analysis grid (AETI, NPP, T native) with coarser, offset AgERA5-like
# sources (RET, PCP), two crop classes and a few season profiles.
processing_fixture <- function(period = c("2023-01-01", "2023-03-31"),
                               season = NULL, gaps = FALSE, seed = 1) {
  set.seed(seed)
  root <- tempfile("rwapor-proc-")
  dir.create(root)
  template <- terra::rast(nrows = 12, ncols = 12, xmin = 0, xmax = 12, ymin = 0, ymax = 12,
                          crs = "EPSG:4326")
  coarse <- terra::rast(nrows = 6, ncols = 6, xmin = -3, xmax = 15, ymin = -3, ymax = 15,
                        crs = "EPSG:4326")
  dekads <- Rwapor:::build_dekad_table(period[1], period[2])$dekad_key
  write_var <- function(var, grid, lo, hi) {
    d <- file.path(root, var)
    dir.create(d)
    for (i in seq_along(dekads)) {
      v <- stats::runif(terra::ncell(grid), lo, hi)
      if (gaps && i == 2L) v[1:6] <- NA
      terra::writeRaster(
        terra::setValues(grid, v),
        file.path(d, sprintf("WAPOR-3.%s.%s.tif", var, format(as.Date(dekads[i]), "%Y-%m-%d"))),
        overwrite = TRUE, datatype = "FLT8S"
      )
    }
  }
  write_var("L1-AETI-D", template, 1, 5)
  write_var("L1-NPP-D", template, 10, 60)
  write_var("L1-T-D", template, 0.5, 3)
  write_var("L1-RET-D", coarse, 2, 6)
  write_var("L1-PCP-D", coarse, 0, 8)

  crop_mask <- terra::setValues(template, rep(c(1L, 2L), each = 72))
  ref_year <- as.integer(format(as.Date(period[1]), "%Y"))
  if (is.null(season)) {
    s0 <- Rwapor::wapor_continuous_julian(period[1], ref_year)
    e0 <- Rwapor::wapor_continuous_julian(period[2], ref_year)
    season <- list(start = c(s0, s0 + 10), end = c(e0, e0 - 15))
  }
  season_start <- terra::setValues(template, sample(season$start, 144, TRUE))
  season_end <- terra::setValues(template, sample(season$end, 144, TRUE))

  crop_params <- data.frame(
    class_value = c(1L, 2L), crop_label = c("A", "B"),
    kc_ini = c(0.5, 0.4), kc_mid = c(1.1, 1.2), kc_end = c(0.7, 0.6),
    l_ini_days = c(15L, 10L), l_mid_days = c(20L, 25L), l_late_days = c(15L, 10L),
    HI = c(0.4, 0.5), MC = c(0.1, 0.12), fc = c(0.9, 1), AOT = c(1, 1),
    stringsAsFactors = FALSE
  )
  config <- list(
    period = period, ref_year = ref_year,
    aeti_var = "L1-AETI-D", ret_var = "L1-RET-D", precip_var = "L1-PCP-D",
    npp_var = "L1-NPP-D", t_var = "L1-T-D",
    data_source = "local", folder = root,
    indicators = c("agg_aeti", "agg_ret", "agg_pcp", "agg_peff", "etc", "adequacy_etc",
                   "agg_t", "beneficial_fraction", "agg_biomass_kg", "yield_npp",
                   "green_water", "blue_water", "cwp_bwp", "adequacy_p95"),
    use_crop_mask = TRUE, use_season_rasters = TRUE
  )
  list(root = root, template = template, config = config, crop_params = crop_params,
       rasters = list(crop_mask = crop_mask, season_start = season_start, season_end = season_end))
}

run_mode <- function(fx, mode, config = fx$config, tile_size = 5L) {
  cfg <- config
  cfg$processing <- mode
  cfg$tile_size <- if (identical(mode, "tiled")) tile_size else NULL
  cfg$output_dir <- tempfile(paste0("rwapor-", mode, "-"))
  suppressMessages(wapor_run_seasonal_analysis(cfg, fx$crop_params, fx$rasters))
}

expect_same_raster <- function(a, b, tolerance = 1e-6) {
  expect_true(terra::compareGeom(a, b, stopOnError = FALSE))
  va <- as.numeric(terra::values(a))
  vb <- as.numeric(terra::values(b))
  expect_identical(is.na(va), is.na(vb))
  expect_equal(va[!is.na(va)], vb[!is.na(vb)], tolerance = tolerance)
}

compare_modes <- function(fx, config = fx$config) {
  mem <- run_mode(fx, "memory", config)
  str <- run_mode(fx, "stream", config)
  til <- run_mode(fx, "tiled", config)
  pick <- list(
    aeti = function(r) r$seasonal_aeti$raster,
    ret = function(r) r$seasonal_ret$raster,
    pcp = function(r) r$seasonal_pcp,
    peff = function(r) r$seasonal_peff,
    etc_class1 = function(r) r$etc_by_class[["1"]]$etc_seasonal,
    adequacy = function(r) r$adequacy_etc,
    biomass = function(r) r$seasonal_biomass_kg,
    green = function(r) r$green_water,
    month1_aeti = function(r) r$monthly_aeti$rasters[[1]]
  )
  for (nm in names(pick)) {
    expect_same_raster(pick[[nm]](str), pick[[nm]](mem))
    expect_same_raster(pick[[nm]](til), pick[[nm]](mem))
  }
  expect_equal(til$cwp, mem$cwp, tolerance = 1e-6)
  expect_equal(til$p95_table$p95_aeti, mem$p95_table$p95_aeti, tolerance = 1e-6)
  invisible(list(memory = mem, stream = str, tiled = til))
}

# -----------------------------------------------------------------------------
# Planner
# -----------------------------------------------------------------------------

test_that("planner picks memory, stream and tiled from the working set", {
  withr::local_options(Rwapor.memory_budget_mb = 1024, Rwapor.plan_thresholds = NULL)
  small <- Rwapor:::.wapor_plan_core(100, 100, 1e4, n_layers = 36, n_targets = 13, workers = 1)
  expect_equal(small$mode, "memory")
  expect_equal(small$batch_size, 36L)

  mid <- Rwapor:::.wapor_plan_core(1000, 1000, 1e6, n_layers = 36, n_targets = 13, workers = 1)
  expect_equal(mid$mode, "stream")
  expect_lt(mid$batch_size, 36L)

  big <- Rwapor:::.wapor_plan_core(20000, 20000, 4e8, n_layers = 36, n_targets = 13, workers = 1)
  expect_equal(big$mode, "tiled")
  expect_true(is.finite(big$tile_size) && big$tile_size >= 64L)
  expect_true(length(big$reasons) >= 2L)
})

test_that("planner respects forced modes, worker counts and option overrides", {
  withr::local_options(Rwapor.memory_budget_mb = 1024)
  expect_warning(
    forced <- Rwapor:::.wapor_plan_core(20000, 20000, 4e8, 36, 13, processing = "memory", workers = 1),
    "may run out of memory"
  )
  expect_equal(forced$mode, "memory")
  expect_equal(forced$auto_mode, "tiled")

  expect_equal(Rwapor:::.wapor_memory_budget_bytes(4), 1024 * 1024^2 / 4)

  withr::local_options(Rwapor.plan_thresholds = c(memory = 1e-9))
  tiny <- Rwapor:::.wapor_plan_core(100, 100, 1e4, 36, 13, workers = 1)
  expect_equal(tiny$mode, "stream")

  withr::local_options(Rwapor.plan_thresholds = c(bogus = 1))
  expect_error(Rwapor:::.wapor_plan_thresholds(), "named numeric")
})

test_that("GDAL chunk size follows the window size within 256 KB to 10 MB", {
  expect_equal(Rwapor:::.wapor_gdal_chunk_bytes(1000), 256L * 1024L)
  expect_equal(Rwapor:::.wapor_gdal_chunk_bytes(3e6), 4L * 1024L^2)
  expect_equal(Rwapor:::.wapor_gdal_chunk_bytes(1e12), 10L * 1024L^2)
})

test_that("wapor_plan_processing works from an AOI and resolution and prints", {
  withr::local_options(Rwapor.memory_budget_mb = 2048)
  farm <- wapor_plan_processing(aoi = c(35, 33, 35.05, 33.05), resolution = 20, n_layers = 36)
  expect_s3_class(farm, "wapor_plan")
  expect_equal(farm$mode, "memory")
  scheme <- wapor_plan_processing(aoi = c(35, 33, 37, 35), resolution = 20, n_layers = 36, n_vars = 4)
  expect_equal(scheme$mode, "tiled")
  expect_output(print(scheme), "mode        : tiled")
})

test_that("wapor_suggest_tile_size accounts for 8-byte values and variables", {
  one <- suppressMessages(wapor_suggest_tile_size(36L, target_ram_mb = 1024))
  four <- suppressMessages(wapor_suggest_tile_size(36L, target_ram_mb = 1024, n_vars = 4L))
  expect_lt(four, one)
  expect_equal(one, as.integer(floor(sqrt(1024 * 1024^2 / (36 * 8 * 2.5)))))
})

# -----------------------------------------------------------------------------
# ISS-20260923-001: windows are cut by extent, not by template row/col
# -----------------------------------------------------------------------------

test_that("an offset source is read at the right place (ISS-20260923-001)", {
  src <- terra::rast(nrows = 100, ncols = 100, xmin = 0, xmax = 100, ymin = 0, ymax = 100,
                     crs = "EPSG:4326")
  terra::values(src) <- seq_len(terra::ncell(src))
  path <- tempfile(fileext = ".tif")
  terra::writeRaster(src, path, datatype = "FLT8S")
  tmpl <- terra::crop(src, terra::ext(40, 60, 40, 60))
  tile <- .wapor_window_template(.wapor_grid_signature(tmpl), list(row = 1L, col = 1L, nrows = 10L, ncols = 10L))
  batch <- Rwapor:::.wapor_read_native_batch(path, terra::ext(tile))
  expect_equal(head(batch$X[, 1], 3), c(4041, 4042, 4043))
})

# -----------------------------------------------------------------------------
# Mode equivalence (decision Q4)
# -----------------------------------------------------------------------------

test_that("memory, stream and tiled agree: offset coarse sources and per-pixel seasons", {
  fx <- processing_fixture()
  on.exit(unlink(fx$root, recursive = TRUE, force = TRUE), add = TRUE)
  out <- compare_modes(fx)
  expect_equal(unname(out$memory$processing_run$aggregation_paths[c("aeti", "ret")]),
               c("aligned", "native"))
  expect_equal(out$tiled$processing$mode, "tiled")
  expect_gt(out$tiled$processing_run$n_tiles, 1L)
})

test_that("tiled mode works on grids whose cell size is not exact in binary (0.0002 deg)", {
  root <- tempfile("rwapor-fp-")
  dir.create(file.path(root, "L1-AETI-D"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  n <- 150
  aoi <- terra::rast(nrows = n, ncols = n, xmin = 35, xmax = 35 + n * 0.0002,
                     ymin = 33, ymax = 33 + n * 0.0002, crs = "EPSG:4326")
  for (d in c("2023-01-01", "2023-01-11", "2023-01-21")) {
    terra::writeRaster(terra::setValues(aoi, stats::runif(n * n, 1, 5)),
                       file.path(root, "L1-AETI-D", sprintf("WAPOR-3.L1-AETI-D.%s.tif", d)))
  }
  fx <- list(
    crop_params = data.frame(class_value = 1L, crop_label = "A", kc_ini = 1, kc_mid = 1, kc_end = 1,
                             l_ini_days = 10L, l_mid_days = 10L, l_late_days = 11L,
                             HI = 1, MC = 0, fc = 1, AOT = 1),
    rasters = list(crop_mask = terra::setValues(aoi, 1L)),
    config = list(period = c("2023-01-01", "2023-01-31"), data_source = "local", folder = root,
                  aeti_var = "L1-AETI-D", indicators = "agg_aeti",
                  use_crop_mask = TRUE, use_season_rasters = FALSE)
  )
  mem <- run_mode(fx, "memory")
  til <- run_mode(fx, "tiled", tile_size = 37L)
  expect_same_raster(til$seasonal_aeti$raster, mem$seasonal_aeti$raster)
})

test_that("memory, stream and tiled agree for a cross-year season", {
  period <- c("2022-11-01", "2023-02-28")
  fx <- processing_fixture(period = period, season = list(start = c(305L, 315L), end = c(59L, 40L)))
  on.exit(unlink(fx$root, recursive = TRUE, force = TRUE), add = TRUE)
  out <- compare_modes(fx)
  expect_true(any(!is.na(terra::values(out$memory$etc_by_class[["1"]]$etc_seasonal))))
})

test_that("memory, stream and tiled agree on the per-dekad fallback path", {
  fx <- processing_fixture()
  on.exit(unlink(fx$root, recursive = TRUE, force = TRUE), add = TRUE)
  withr::local_options(Rwapor.max_season_profiles = 1L)
  out <- compare_modes(fx)
  expect_equal(unname(out$memory$processing_run$aggregation_paths[["ret"]]), "per_dekad")
})

test_that("memory, stream and tiled agree on a projected analysis grid", {
  fx <- processing_fixture()
  on.exit(unlink(fx$root, recursive = TRUE, force = TRUE), add = TRUE)
  utm <- terra::project(fx$rasters$crop_mask, "EPSG:32631", method = "near")
  fx$rasters <- list(
    crop_mask = utm,
    season_start = terra::project(fx$rasters$season_start, utm, method = "near"),
    season_end = terra::project(fx$rasters$season_end, utm, method = "near")
  )
  cfg <- fx$config
  cfg$reference_layer <- "crop_mask"
  cfg$indicators <- c("agg_aeti", "agg_ret", "etc", "adequacy_etc")
  mem <- run_mode(fx, "memory", cfg)
  til <- run_mode(fx, "tiled", cfg, tile_size = 4L)
  expect_same_raster(til$seasonal_aeti$raster, mem$seasonal_aeti$raster)
  expect_same_raster(til$adequacy_etc, mem$adequacy_etc)
})

# -----------------------------------------------------------------------------
# Accuracy: agreement with v1.0.0 and coverage (decisions A-C)
# -----------------------------------------------------------------------------

# The v1.0.0 order: resample every dekad onto the analysis grid, then sum.
# Resampling the uncropped source keeps neighbours outside the area for
# bilinear (v1.0.0 cropped first, which biased the outer rows under bilinear).
v100_seasonal_sum <- function(fx, var, method, mult) {
  paths <- wapor_local_rasters(fx$root, var, fx$config$period[1], fx$config$period[2])
  stack <- terra::resample(terra::rast(paths), fx$template, method = method)
  sw <- wapor_build_season_weights(fx$config$period[1], fx$config$period[2],
                                   fx$rasters$season_start, fx$rasters$season_end,
                                   fx$config$ref_year)
  wapor_masked_sum(stack, sw$weights, mult)
}

test_that("gap-free results match the v1.0.0 per-dekad method (near and bilinear)", {
  fx <- processing_fixture()
  on.exit(unlink(fx$root, recursive = TRUE, force = TRUE), add = TRUE)
  mult <- Rwapor:::get_analysis_layer_multipliers(
    "L1-RET-D", Rwapor:::build_dekad_table(fx$config$period[1], fx$config$period[2])
  )
  new_near <- run_mode(fx, "memory")
  expect_same_raster(new_near$seasonal_ret$raster, v100_seasonal_sum(fx, "L1-RET-D", "near", mult))
  expect_same_raster(new_near$seasonal_aeti$raster, v100_seasonal_sum(fx, "L1-AETI-D", "near", mult))

  cfg <- fx$config
  cfg$resampling_method <- list(ret = "bilinear")
  new_bil <- run_mode(fx, "memory", cfg)
  expect_same_raster(new_bil$seasonal_ret$raster, v100_seasonal_sum(fx, "L1-RET-D", "bilinear", mult))
})

test_that("pixels missing a dekad are NA by default and summed when min_coverage allows", {
  fx <- processing_fixture(gaps = TRUE)
  on.exit(unlink(fx$root, recursive = TRUE, force = TRUE), add = TRUE)
  strict <- run_mode(fx, "memory")
  aeti <- terra::values(strict$seasonal_aeti$raster)[, 1]
  cov <- terra::values(strict$coverage$aeti)[, 1]
  expect_true(all(is.na(aeti[1:6])))
  expect_true(all(cov[1:6] < 1))
  expect_true(all(!is.na(aeti[7:144])))

  cfg <- fx$config
  cfg$min_coverage <- 0.5
  loose <- run_mode(fx, "memory", cfg)
  mult <- Rwapor:::get_analysis_layer_multipliers(
    "L1-AETI-D", Rwapor:::build_dekad_table(fx$config$period[1], fx$config$period[2])
  )
  ref <- terra::values(v100_seasonal_sum(fx, "L1-AETI-D", "near", mult))[, 1]
  got <- terra::values(loose$seasonal_aeti$raster)[, 1]
  expect_equal(got[1:6], ref[1:6], tolerance = 1e-6)
})

# -----------------------------------------------------------------------------
# Engine behaviour
# -----------------------------------------------------------------------------

test_that("the AOI defaults to the crop mask extent and is logged", {
  fx <- processing_fixture()
  on.exit(unlink(fx$root, recursive = TRUE, force = TRUE), add = TRUE)
  cfg <- fx$config
  cfg$indicators <- "agg_aeti"
  expect_message(
    wapor_run_seasonal_analysis(cfg, fx$crop_params, fx$rasters),
    "aoi_region not supplied"
  )
})

test_that("keep_intermediates controls dekadal stacks and registry steps still see them lazily", {
  fx <- processing_fixture()
  on.exit(unlink(fx$root, recursive = TRUE, force = TRUE), add = TRUE)
  step_name <- paste0("probe_", as.integer(stats::runif(1, 1, 1e6)))
  wapor_register_indicator_step(step_name, function(ctx) {
    ctx$results[[step_name]] <- terra::nlyr(ctx$season_weights)
  }, depends = "agg_aeti")
  cfg <- fx$config
  cfg$indicators <- c("agg_aeti", step_name)
  cfg$keep_intermediates <- FALSE
  res <- run_mode(fx, "memory", cfg)
  expect_null(res$dekadal_stacks)
  expect_null(res$season_weights)
  expect_equal(res[[step_name]], 9L)

  cfg$keep_intermediates <- TRUE
  kept <- run_mode(fx, "memory", cfg)
  expect_equal(terra::nlyr(kept$dekadal_stacks$aeti), 9L)
})

# -----------------------------------------------------------------------------
# Bounded-memory statistics
# -----------------------------------------------------------------------------

test_that("exact P95 matches stats::quantile even when refinement is forced", {
  set.seed(3)
  r <- terra::rast(nrows = 80, ncols = 60, crs = "EPSG:4326")
  v <- round(stats::rgamma(terra::ncell(r), 3, 0.01), 1)
  v[sample(length(v), 200)] <- NA
  x <- terra::setValues(r, v)
  z <- terra::setValues(r, sample(c(1, 2, 3), terra::ncell(r), TRUE))
  zv <- terra::values(z)[, 1]
  ref <- vapply(1:3, function(k) unname(stats::quantile(v[zv == k & !is.na(v)], 0.95)), numeric(1))
  forced <- Rwapor:::.wapor_zonal_quantile_exact(x, z, 0.95, max_values = 25, n_bins = 16L)
  expect_equal(forced$quantile, ref, tolerance = 1e-12)
  tab <- wapor_calc_p95_aeti(x, z)
  expect_equal(tab$p95_aeti, ref, tolerance = 1e-12)
  expect_true(all(tab$valid))
})

test_that("block-wise Theil equals the direct formula", {
  set.seed(4)
  r <- terra::rast(nrows = 40, ncols = 40, crs = "EPSG:4326")
  v <- stats::runif(terra::ncell(r), 50, 500)
  x <- terra::setValues(r, v)
  z <- terra::setValues(r, rep(c(1, 2), each = 800))
  direct <- function(vals) { m <- mean(vals); mean((vals / m) * log(vals / m)) }
  th <- wapor_calc_theil(x, z)
  expect_equal(th$overall, direct(v), tolerance = 1e-10)
  expect_equal(th$by_class$theil, c(direct(v[1:800]), direct(v[801:1600])), tolerance = 1e-10)
})

test_that("closed-form linear_trend matches a per-pixel least-squares fit with gaps", {
  set.seed(5)
  r <- terra::rast(nrows = 20, ncols = 20)
  tt <- seq(2001, by = 1, length.out = 10)
  stack <- terra::rast(lapply(seq_along(tt), function(i) {
    v <- 100 + 3 * i + stats::rnorm(terra::ncell(r), 0, 5)
    v[stats::runif(length(v)) < 0.2] <- NA
    terra::setValues(r, v)
  }))
  fit <- function(v) {
    ok <- is.finite(v)
    if (sum(ok) < 2) return(c(NA, NA))
    cf <- stats::coef(stats::lm(v[ok] ~ tt[ok]))
    c(cf[[2]], cf[[1]])
  }
  ref <- terra::app(stack, fit)
  got <- linear_trend(stack, times = tt)
  expect_equal(as.numeric(terra::values(got$slope)), as.numeric(terra::values(ref[[1]])), tolerance = 1e-8)
  expect_equal(as.numeric(terra::values(got$intercept)), as.numeric(terra::values(ref[[2]])), tolerance = 1e-8)
})

test_that("WaPOR dekad labels are parsed to their start dates", {
  expect_equal(Rwapor:::.wapor_ymd_from_name("WAPOR-3.L1-AETI-D.2023-01-D2.tif"), "2023-01-11")
  expect_equal(Rwapor:::.wapor_ymd_from_name("WAPOR-3.L1-AETI-D.2023-12-D3.tif"), "2023-12-21")
  expect_equal(Rwapor:::.wapor_ymd_from_name("WAPOR-3.L1-AETI-D.2023-05-01.tif"), "2023-05-01")
})
