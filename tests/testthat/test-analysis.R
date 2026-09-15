# =============================================================================
# Tests for analysis functions
# =============================================================================

test_that("crop defaults validation works", {
  expect_true(wapor_validate_crop_defaults(FAO_CROP_DEFAULTS))

  # Missing columns
  bad_df <- data.frame(crop_name = "Test", kc_ini = 0.3)
  expect_error(wapor_validate_crop_defaults(bad_df), "Missing required columns")

  # Negative Kc
  bad_df2 <- FAO_CROP_DEFAULTS
  bad_df2$kc_ini[1] <- -0.1
  expect_error(wapor_validate_crop_defaults(bad_df2), "non-negative")

  # NA stage lengths
  bad_df3 <- FAO_CROP_DEFAULTS
  bad_df3$l_ini_days[1] <- NA

  expect_error(wapor_validate_crop_defaults(bad_df3), "must not be NA")
})

test_that("wapor_list_crops returns crop names", {
  crops <- wapor_list_crops()
  expect_true(length(crops) >= 3)
  expect_true("Winter Wheat" %in% crops)
  expect_true("Sorghum" %in% crops)
  expect_true("Sugarbeet" %in% crops)
})

test_that("wapor_crop_defaults works", {
  ww <- wapor_crop_defaults("Winter Wheat")
  expect_true(!is.null(ww))
  expect_equal(nrow(ww), 1)
  expect_equal(ww$kc_mid, 1.15)

  # Case insensitive
  sg <- wapor_crop_defaults("sorghum")
  expect_true(!is.null(sg))

  # Not found
  expect_null(wapor_crop_defaults("NonexistentCrop"))
})

test_that("wapor_build_crop_assignments populates rows from crop_defaults", {
  # No defaults supplied: template stays NA, one row per class
  empty_tbl <- wapor_build_crop_assignments(class_values = c(1L, 2L))
  expect_equal(nrow(empty_tbl), 2)
  expect_true(all(is.na(empty_tbl$kc_ini)))

  # Defaults from wapor_crop_defaults() (data.frame row) and a custom list
  tbl <- wapor_build_crop_assignments(
    class_values = c(1L, 2L, 3L),
    crop_defaults = list(
      "1" = wapor_crop_defaults("sorghum"),
      "2" = list(kc_ini = 0.4, kc_mid = 1.15, kc_end = 0.7,
                 l_ini_days = 25L, l_mid_days = 50L, l_late_days = 30L,
                 HI = 0.45, MC = 0.14, fc = 0.90, AOT = 0.80,
                 crop_label = "Custom crop")
    )
  )

  sorghum <- wapor_crop_defaults("sorghum")
  row1 <- tbl[tbl$class_value == 1L, ]
  expect_equal(row1$kc_ini, sorghum$kc_ini)
  expect_equal(row1$kc_mid, sorghum$kc_mid)
  expect_equal(row1$crop_label, sorghum$crop_name)

  row2 <- tbl[tbl$class_value == 2L, ]
  expect_equal(row2$kc_ini, 0.4)
  expect_equal(row2$l_late_days, 30L)
  expect_equal(row2$crop_label, "Custom crop")

  # Class 3 has no matching key: stays NA
  row3 <- tbl[tbl$class_value == 3L, ]
  expect_true(is.na(row3$kc_ini))

  # Unmatched key warns but doesn't error
  expect_warning(
    wapor_build_crop_assignments(
      class_values = c(1L),
      crop_defaults = list("99" = wapor_crop_defaults("sorghum"))
    ),
    "does not match"
  )

  # A NULL/empty defaults value (e.g. an unmatched wapor_crop_defaults() lookup)
  # warns and leaves that class NA, instead of silently no-op'ing
  expect_warning(
    result <- wapor_build_crop_assignments(
      class_values = c(1L),
      crop_defaults = list("1" = wapor_crop_defaults("not_a_real_crop"))
    ),
    "NULL or empty"
  )
  expect_true(is.na(result$kc_ini))

  # wapor_crop_defaults() crop_name lookups must match the real crop_name
  # values exactly (case-insensitive) -- "winter_wheat" (underscore) must NOT
  # silently match "Winter Wheat" via partial grep, since that's a common typo.
  expect_null(wapor_crop_defaults("winter_wheat"))
  expect_false(is.null(wapor_crop_defaults("Winter Wheat")))
  expect_false(is.null(wapor_crop_defaults("winter wheat")))
})

test_that("continuous Julian date logic works", {
  # Same year
  expect_equal(wapor_continuous_julian("2023-01-01", 2023), 1L)
  expect_equal(wapor_continuous_julian("2023-12-31", 2023), 365L)

  # Cross-year
  expect_equal(wapor_continuous_julian("2024-01-01", 2023), 366L)
  expect_equal(wapor_continuous_julian("2024-01-15", 2023), 380L)

  # Leap year
  expect_equal(wapor_continuous_julian("2024-12-31", 2024), 366L)
  expect_equal(wapor_continuous_julian("2025-01-01", 2024), 367L)
})

test_that("daily Kc curve generation works", {
  kc <- wapor_build_kc(0.4, 1.15, 0.30, 30, 60, 40, 30)
  expect_equal(length(kc), 160)  # 30 + 60 + 40 + 30

  # Initial stage is constant
  expect_true(all(kc[1:30] == 0.4))

  # Mid stage is constant
  expect_true(all(kc[91:130] == 1.15))

  # Development is increasing
  expect_true(all(diff(kc[31:90]) > 0))

  # Late stage is decreasing
  expect_true(all(diff(kc[131:160]) < 0))

  # End value
  expect_equal(kc[160], 0.30, tolerance = 0.01)
})

test_that("Kc by class generation works", {
  params <- data.frame(
    class_value = c(1L, 2L),
    kc_ini = c(0.4, 0.3),
    kc_mid = c(1.15, 1.05),
    kc_end = c(0.30, 0.55),
    l_ini_days = c(30L, 20L),
    l_mid_days = c(40L, 40L),
    l_late_days = c(30L, 30L),
    stringsAsFactors = FALSE
  )
  result <- wapor_build_kc_by_class(params, c("1" = 160, "2" = 150))
  expect_true(length(result) == 2)
  expect_equal(length(result[["1"]]), 160)
  expect_equal(length(result[["2"]]), 150)
})

test_that("crop mask harmonization requires SpatRaster inputs", {
  expect_error(wapor_harmonize_raster("not_a_raster", "also_not"),
    "must be a SpatRaster")
})

test_that("build_dekad_table produces valid dekads", {
  tbl <- build_dekad_table("2023-01-01", "2023-02-28")
  expect_true(nrow(tbl) >= 5)
  expect_true(all(tbl$n_days > 0))
  expect_true(all(tbl$n_days <= 11))
  # All dates covered
  total_days <- sum(tbl$n_days)
  expect_equal(total_days, as.integer(as.Date("2023-02-28") - as.Date("2023-01-01")) + 1)
})

test_that("season raster harmonization validates overlap", {
  skip_if_not_installed("terra")
  # Create test rasters with no overlap
  r1 <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 10,
                     ymin = 0, ymax = 10, vals = 1L)
  r2 <- terra::rast(nrows = 10, ncols = 10, xmin = 100, xmax = 110,
                     ymin = 100, ymax = 110, vals = 1L)
  # Harmonizing should error because extents don't overlap
  expect_error(wapor_harmonize_raster(r1, r2, method = "near"),
               "No spatial overlap")
})

test_that("harmonization works with overlapping but different extents", {
  skip_if_not_installed("terra")
  # Create source raster larger than template
  r_source <- terra::rast(nrows = 20, ncols = 20, xmin = 0, xmax = 20,
                           ymin = 0, ymax = 20, vals = seq_len(400))
  # Template is smaller but overlaps
  r_template <- terra::rast(nrows = 10, ncols = 10, xmin = 5, xmax = 15,
                             ymin = 5, ymax = 15, vals = 1L)

  # Harmonization should succeed
  result <- wapor_harmonize_raster(r_source, r_template, method = "bilinear")

  expect_true(inherits(result, "SpatRaster"))
  expect_equal(dim(result)[1:2], dim(r_template)[1:2])
  expect_true(all(!is.na(terra::values(result))))
})

test_that("harmonization works for multi-layer stacks (regression test for extent mismatch)", {
  skip_if_not_installed("terra")
  # Simulate the scenario: data stack with slightly different extent than template
  # This is the regression test for the bug where aeti_stack wasn't harmonized

  # Create template (cropped to specific extent)
  template <- terra::rast(nrows = 10, ncols = 10, xmin = 30, xmax = 35,
                           ymin = 10, ymax = 15, vals = 1)

  # Create multi-layer stack with larger extent (like full raster from WaPOR)
  stack <- terra::rast(nrows = 100, ncols = 100, xmin = 25, xmax = 50,
                        ymin = 5, ymax = 30, nlyrs = 5, vals = runif(50000))
  names(stack) <- paste0("2023-01-0", 1:5)

  # Create season weights from template extent
  weights <- terra::rast(nrows = 10, ncols = 10, xmin = 30, xmax = 35,
                          ymin = 10, ymax = 15, nlyrs = 5, vals = 0.5)
  names(weights) <- names(stack)

  # Without harmonization, this operation would fail with extent mismatch
  harmonized_stack <- wapor_harmonize_raster(stack, template, method = "bilinear")

  # Now the multiplication should work
  result <- harmonized_stack * weights

  expect_true(inherits(result, "SpatRaster"))
  expect_equal(terra::nlyr(result), 5)
  expect_true(all(dim(result)[1:2] == dim(template)[1:2]))
})

test_that("total days and ldev computation works", {
  skip_if_not_installed("terra")
  start_r <- terra::rast(nrows = 5, ncols = 5, vals = 1)
  end_r   <- terra::rast(nrows = 5, ncols = 5, vals = 160)
  total_r <- wapor_season_days(start_r, end_r)
  expect_equal(as.numeric(terra::values(total_r)[1, 1]), 160)

  ldev_r <- wapor_season_ldev(total_r, 30, 40, 30)
  expect_equal(as.numeric(terra::values(ldev_r)[1, 1]), 60)  # 160 - 100
})
