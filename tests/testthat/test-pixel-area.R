# =============================================================================
# Tests for latitude-aware per-pixel area (Rwapor Phase 1.1)
# =============================================================================

test_that("wapor_pixel_area_ha returns a SpatRaster matching the template", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 4, ncols = 3, xmin = 0, xmax = 3, ymin = 30, ymax = 34, crs = "EPSG:4326")
  area <- wapor_pixel_area_ha(r)
  expect_s4_class(area, "SpatRaster")
  expect_equal(terra::nrow(area), 4)
  expect_equal(terra::ncol(area), 3)
  expect_true(terra::compareGeom(area, r, stopOnError = FALSE))
})

test_that("wapor_pixel_area_ha is larger at lower latitudes on a lonlat grid", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 3, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 60, crs = "EPSG:4326")
  area <- wapor_pixel_area_ha(r)
  vals <- matrix(terra::values(area)[, 1], nrow = 3, ncol = 2, byrow = TRUE)
  # Row 1 is northernmost (near 60 N); row 3 is nearest the equator.
  expect_true(all(vals[1, ] < vals[2, ]))
  expect_true(all(vals[2, ] < vals[3, ]))
  expect_equal(vals[1, 1], vals[1, 2])
})

test_that("wapor_pixel_area_ha uses a constant cell area on projected grids", {
  skip_if_not_installed("terra")
  r <- terra::rast(
    nrows = 4, ncols = 4,
    xmin = 0, xmax = 400, ymin = 0, ymax = 400,
    crs = "EPSG:3857"
  )
  area <- wapor_pixel_area_ha(r)
  vals <- terra::values(area)[, 1]
  expect_true(abs(max(vals) - min(vals)) < 1e-9)
  expected <- (terra::res(r)[1] * terra::res(r)[2]) / 10000
  expect_equal(vals[1], expected)
})

test_that("wapor_masked_global_mean is area-weighted when area is supplied", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 3, ncols = 1, xmin = 0, xmax = 1, ymin = 0, ymax = 60, crs = "EPSG:4326")
  values <- terra::setValues(r, c(10, 20, 30))
  area <- wapor_pixel_area_ha(r)
  weighted <- wapor_masked_global_mean(values, area = area)
  unweighted <- wapor_masked_global_mean(values)
  w <- terra::values(area)[, 1]
  v <- c(10, 20, 30)
  expected <- sum(v * w) / sum(w)
  expect_equal(weighted, expected)
  expect_equal(unweighted, mean(v))
  expect_false(isTRUE(all.equal(weighted, unweighted)))
})

test_that("wapor_weighted_class_mean prefers area_ha over pixel_count", {
  summary_tbl <- data.frame(class_value = c(1L, 2L), mean_val = c(10, 30))
  class_stats <- data.frame(
    class_value = c(1L, 2L),
    pixel_count = c(100, 100),
    area_ha = c(90, 10)
  )
  got <- wapor_weighted_class_mean(summary_tbl, class_stats, "mean_val")
  expect_equal(got, stats::weighted.mean(c(10, 30), w = c(90, 10)))
  expect_false(isTRUE(all.equal(got, 20)))
})

test_that("engine class areas vary with latitude instead of using ymin only", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("rwapor-area-")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  dates <- c("2023-01-01", "2023-01-11", "2023-01-21")
  template <- terra::rast(
    nrows = 6, ncols = 4,
    xmin = 0, xmax = 4, ymin = 0, ymax = 60,
    crs = "EPSG:4326"
  )
  # Northern half = class 1, southern half = class 2 (more area per pixel).
  crop_vals <- c(rep(1L, 12), rep(2L, 12))
  crop_mask <- terra::setValues(template, crop_vals)
  season_start <- terra::setValues(template, rep(1L, terra::ncell(template)))
  season_end <- terra::setValues(template, rep(31L, terra::ncell(template)))

  var_dir <- file.path(analysis_dir, "L1-AETI-D")
  dir.create(var_dir, recursive = TRUE)
  for (d in dates) {
    r <- terra::setValues(template, rep(2, terra::ncell(template)))
    terra::writeRaster(
      r,
      file.path(var_dir, sprintf("WAPOR-3.L1-AETI-D.%s.tif", d)),
      overwrite = TRUE
    )
  }

  crop_params <- data.frame(
    class_value = c(1L, 2L),
    crop_label = c("North", "South"),
    kc_ini = c(1, 1), kc_mid = c(1, 1), kc_end = c(1, 1),
    l_ini_days = c(10L, 10L), l_mid_days = c(10L, 10L), l_late_days = c(11L, 11L),
    HI = c(1, 1), MC = c(0, 0), fc = c(1, 1), AOT = c(1, 1),
    stringsAsFactors = FALSE
  )

  results <- wapor_run_seasonal_analysis(
    config = list(
      period = c("2023-01-01", "2023-01-31"),
      ref_year = 2023,
      aeti_var = "L1-AETI-D",
      data_source = "local",
      folder = analysis_dir,
      indicators = c("agg_aeti"),
      use_crop_mask = TRUE,
      use_season_rasters = TRUE
    ),
    crop_params = crop_params,
    rasters = list(
      crop_mask = crop_mask,
      season_start = season_start,
      season_end = season_end
    )
  )

  stats <- results$mask_class_stats
  area_1 <- stats$area_ha[stats$class_value == 1]
  area_2 <- stats$area_ha[stats$class_value == 2]
  expect_equal(as.integer(stats$pixel_count[stats$class_value == 1]), 12L)
  expect_equal(as.integer(stats$pixel_count[stats$class_value == 2]), 12L)
  expect_true(area_2 > area_1)
})
