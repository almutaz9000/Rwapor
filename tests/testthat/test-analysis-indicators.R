# =============================================================================
# Tests for analysis indicator calculation functions
# (Peff, CWP/BWP, masked sum, ETc, adequacy, P95, precip, yield, BF, green/blue water)
# Extracted from test-analysis.R to reduce its god-node edge count.
# =============================================================================

test_that("CWP and BWP reject provenance from different seasons", {
  skip_if_not_installed("terra")
  grid <- list(nrow = 2L, ncol = 2L, res = c(1, 1),
               extent = list(xmin = 0, xmax = 2, ymin = 0, ymax = 2), crs = "")
  make_meta <- function(start, end, units) {
    Rwapor:::.wapor_new_provenance(
      variable = NULL,
      intervals = data.frame(layer = 1L, start_date = start, end_date = end,
                             temporal_code = "S", metadata_source = "test"),
      period = list(start = start, end = end), units = units, grid = grid,
      season_definition = list(id = paste(start, end))
    )
  }
  aeti <- terra::rast(nrows = 2, ncols = 2, vals = 400)
  yield <- terra::rast(nrows = 2, ncols = 2, vals = 5000)
  aeti_meta <- make_meta("2023-01-01", "2023-12-31", "mm")
  yield_meta <- make_meta("2024-01-01", "2024-12-31", "kg/ha")
  provenance <- list(yield = yield_meta, aeti = aeti_meta)

  expect_error(wapor_calc_cwp(yield, aeti, provenance = provenance), "Analysis periods differ")
  expect_error(wapor_calc_bwp(yield, aeti, provenance = provenance), "Analysis periods differ")

  yield_meta_same <- make_meta("2023-01-01", "2023-12-31", "kg/ha")
  aeti_meta_same <- make_meta("2023-01-01", "2023-12-31", "mm")
  valid_provenance <- list(yield = yield_meta_same, aeti = aeti_meta_same)
  expect_equal(as.numeric(terra::values(wapor_calc_cwp(
    yield, aeti, provenance = valid_provenance
  ))[1, 1]), 5000 / 4000)
  expect_equal(as.numeric(terra::values(wapor_calc_bwp(
    yield, aeti, provenance = list(biomass = yield_meta_same, aeti = aeti_meta_same)
  ))[1, 1]), 5000 / 4000)
})

test_that("multi-input water indicators reject provenance from different periods", {
  skip_if_not_installed("terra")
  grid <- list(nrow = 2L, ncol = 2L, res = c(1, 1),
               extent = list(xmin = 0, xmax = 2, ymin = 0, ymax = 2), crs = "")
  make_meta <- function(start, end, units = "mm") Rwapor:::.wapor_new_provenance(
    intervals = data.frame(layer = 1L, start_date = start, end_date = end,
                           temporal_code = "M", metadata_source = "test"),
    period = list(start = start, end = end), units = units, grid = grid,
    season_definition = list(id = paste(start, end))
  )
  a <- terra::rast(nrows = 2, ncols = 2, vals = 100)
  b <- terra::rast(nrows = 2, ncols = 2, vals = 50)
  a_meta <- make_meta("2023-01-01", "2023-01-31")
  b_meta <- make_meta("2023-02-01", "2023-02-28")

  expect_error(wapor_calc_adequacy_etc(a, b, provenance = list(aeti = a_meta, etc = b_meta)),
               "Analysis periods differ")
  expect_error(wapor_calc_green_water(a, b, provenance = list(aeti = a_meta, peff = b_meta)),
               "Analysis periods differ")
  expect_error(wapor_calc_blue_water(a, b, provenance = list(aeti = a_meta, peff = b_meta)),
               "Analysis periods differ")
  expect_error(wapor_calc_et_rain(a, b, provenance = list(aeti = a_meta, precip = b_meta)),
               "Analysis periods differ")
  expect_error(wapor_calc_rainfall_surplus(a, b, provenance = list(aeti = a_meta, precip = b_meta)),
               "Analysis periods differ")
})

test_that("CWP and BWP calculations work", {
  # 5000 kg/ha yield, 400 mm AETI
  cwp <- wapor_calc_cwp(5000, 400)
  expect_equal(cwp, 5000 / (400 * 10))  # kg/m3

  # t/ha unit
  cwp_t <- wapor_calc_cwp(5, 400, yield_unit = "t/ha")
  expect_equal(cwp_t, cwp)

  # Zero AETI returns NA
  expect_true(is.na(wapor_calc_cwp(5000, 0)))

  # BWP
  bwp <- wapor_calc_bwp(12000, 400)
  expect_equal(bwp, 12000 / (400 * 10))
})

test_that("season masked aggregation checks raster grid and layer dates", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 2, ncols = 2, nlyrs = 2, vals = 1)
  weights <- terra::rast(nrows = 2, ncols = 2, nlyrs = 2, vals = 0.5)
  names(x) <- c("AETI_2023-01-01", "AETI_2023-01-11")
  names(weights) <- c("weights_2023-01-11", "weights_2023-01-01")

  expect_error(wapor_masked_sum(x, weights), "date mismatch.*2023-01-01.*2023-01-11")

  shifted <- terra::rast(nrows = 2, ncols = 2, nlyrs = 2,
                         xmin = 1, xmax = 3, ymin = 0, ymax = 2, vals = 0.5)
  names(shifted) <- names(x)
  expect_error(wapor_masked_sum(x, shifted), "grid mismatch")
})

test_that("apply_masked_sum works with matching layers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 0.5)
  names(x) <- names(w) <- c("2023-01-01", "2023-01-11", "2023-01-21")
  result <- wapor_masked_sum(x, w)
  expect_equal(as.numeric(terra::values(result)[1, 1]), 15)  # 10 * 0.5 * 3
})

test_that("apply_masked_sum honors per-layer multipliers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 3, ncols = 3, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 3, ncols = 3, nlyrs = 3, vals = 0.5)
  names(x) <- names(w) <- c("2023-01-01", "2023-01-11", "2023-01-21")
  result <- wapor_masked_sum(x, w, layer_multipliers = c(10, 10, 11))
  expect_equal(as.numeric(terra::values(result)[1, 1]), 155)
})

test_that("apply_masked_sum errors on mismatched layers", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 5, ncols = 5, nlyrs = 3, vals = 10)
  w <- terra::rast(nrows = 5, ncols = 5, nlyrs = 2, vals = 0.5)
  expect_error(wapor_masked_sum(x, w), "Layer count mismatch")
})

test_that("analysis layer multipliers use dekad day counts for daily-rate D variables", {
  multiplier_helper <- if (exists("get_analysis_layer_multipliers", mode = "function")) {
    get("get_analysis_layer_multipliers", mode = "function")
  } else {
    getFromNamespace("get_analysis_layer_multipliers", "Rwapor")
  }
  period_table <- data.frame(
    dekad_start = as.Date(c("2023-01-01", "2023-01-11", "2023-01-21")),
    dekad_end = as.Date(c("2023-01-10", "2023-01-20", "2023-01-31")),
    n_days = c(10L, 10L, 11L)
  )

  expect_equal(multiplier_helper("L1-AETI-D", period_table), c(10, 10, 11))
  expect_equal(multiplier_helper("L1-TBP-A", period_table), c(1, 1, 1))
})

test_that("seasonal ETc incremental honors per-layer multipliers", {
  skip_if_not_installed("terra")
  ret <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3, vals = 1)
  w <- terra::rast(nrows = 2, ncols = 2, nlyrs = 3, vals = 0.5)
  names(ret) <- names(w) <- c("2023-01-01", "2023-01-11", "2023-01-21")
  result <- wapor_calc_seasonal_etc(
    ret,
    w,
    kc_dekad = c(1, 1, 1),
    layer_multipliers = c(10, 10, 11)
  )
  expect_equal(as.numeric(terra::values(result)[1, 1]), 15.5)
})

test_that("adequacy_etc handles zero ETc", {
  expect_true(is.na(wapor_calc_adequacy_etc(100, 0)))
  expect_equal(wapor_calc_adequacy_etc(400, 400), 1)
  expect_equal(wapor_calc_adequacy_etc(300, 400), 0.75)
})

test_that("class p95 validity counts only non-missing analysis pixels", {
  skip_if_not_installed("terra")
  aeti <- terra::rast(nrows = 2, ncols = 2, vals = c(1, NA, 3, 4))
  crop_mask <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 1, 2, 2))

  result <- wapor_calc_p95_aeti(aeti, crop_mask, min_pixels = 2)
  result <- result[order(result$class_value), ]

  expect_equal(result$n_pixels, c(1L, 2L))
  expect_equal(result$valid, c(FALSE, TRUE))
  expect_true(is.na(result$p95_aeti[1]))
  expect_false(is.na(result$p95_aeti[2]))
})

test_that("aggregate_precip_monthly works", {
  ts <- data.frame(
    date = seq.Date(as.Date("2023-01-01"), as.Date("2023-03-31"), by = "day"),
    value = rep(2, 90),
    stringsAsFactors = FALSE
  )
  monthly <- wapor_aggregate_precip(ts)
  expect_equal(nrow(monthly), 3)
  expect_equal(monthly$p_monthly_mm[1], 62)  # 31 days * 2
  expect_equal(monthly$p_monthly_mm[2], 56)  # 28 days * 2
  expect_equal(monthly$p_monthly_mm[3], 62)  # 31 days * 2
})

test_that("NPP to TBP conversion works", {
  npp <- 100
  tbp <- wapor_convert_npp_tbp(npp)
  expect_equal(tbp, 100 * 22.222)
})

test_that("Yield calculation from NPP works", {
  # Formula:
  # dmp = NPP * 22.222
  # agbm = (AOT * fc * (dmp / (1 - MC))) / 1000
  # yield = HI * agbm

  npp <- 100
  MC  <- 0.7
  fc  <- 1.6
  AOT <- 0.8
  HI  <- 1.0

  dmp <- 100 * 22.222
  expected_agbm <- (0.8 * 1.6 * (dmp / (1 - 0.7))) / 1000
  expected_yield <- 1.0 * expected_agbm

  yield <- wapor_calc_yield_npp(npp, MC, fc, AOT, HI)
  expect_equal(yield, expected_yield)
})

test_that("beneficial fraction and green/blue water helpers work", {
  expect_equal(wapor_calc_beneficial_fraction(50, 200), 0.25)
  expect_true(is.na(wapor_calc_beneficial_fraction(50, 0)))

  expect_equal(wapor_calc_green_water(350, 200), 200)
  expect_equal(wapor_calc_green_water(150, 200), 150)

  expect_equal(wapor_calc_blue_water(350, 200), 150)
  expect_equal(wapor_calc_blue_water(150, 200), 0)
})

test_that("wapor_summary_by_class names the mean column and merges stats", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 2, ncols = 2, vals = c(10, 20, 30, 40), crs = "EPSG:4326")
  mask <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 1, 2, 2), crs = "EPSG:4326")
  stats <- data.frame(class_value = c(1L, 2L), crop_label = c("A", "B"))
  out <- wapor_summary_by_class(r, mask, class_stats = stats, var_name = "seasonal_aeti")
  expect_equal(names(out)[1:2], c("class_value", "mean_seasonal_aeti"))
  expect_equal(out$mean_seasonal_aeti, c(15, 35))
  expect_equal(out$crop_label, c("A", "B"))
})

test_that("wapor_calc_peff applies USDA-SCS to monthly rasters", {
  skip_if_not_installed("terra")
  jan <- terra::rast(nrows = 2, ncols = 2, vals = 100, crs = "EPSG:4326")
  feb <- terra::rast(nrows = 2, ncols = 2, vals = 300, crs = "EPSG:4326")
  res <- wapor_calc_peff(list(`2023-01` = jan, `2023-02` = feb))
  expect_equal(as.numeric(terra::values(res$monthly[[1]])[1, 1]), 100 * (125 - 0.2 * 100) / 125)
  expect_equal(as.numeric(terra::values(res$monthly[[2]])[1, 1]), 125 + 0.1 * 300)
  expected_seasonal <- 100 * (125 - 0.2 * 100) / 125 + 125 + 0.1 * 300
  expect_equal(as.numeric(terra::values(res$seasonal)[1, 1]), expected_seasonal)
})

test_that("rainfall surplus raster helpers validate stack periods", {
  skip_if_not_installed("terra")
  template <- terra::rast(nrows = 2, ncols = 2, vals = 1, crs = "EPSG:4326")
  aeti <- c(template, template)
  precip <- c(template, template)

  terra::time(aeti) <- as.Date(c("2023-01-01", "2023-02-01"))
  terra::time(precip) <- as.Date(c("2023-01-01", "2023-02-01"))
  expect_s4_class(wapor_calc_rainfall_surplus(aeti, precip), "SpatRaster")

  terra::time(aeti) <- as.Date(c(NA, NA))
  terra::time(precip) <- as.Date(c(NA, NA))
  names(aeti) <- c("AETI_2023-01", "AETI_2023-02")
  names(precip) <- c("PCP_2023-01", "PCP_2023-02")
  expect_s4_class(wapor_calc_rainfall_surplus(aeti, precip), "SpatRaster")
  names(precip) <- c("PCP_2023-02", "PCP_2023-03")
  expect_error(
    wapor_calc_rainfall_surplus(aeti, precip),
    "date mismatch.*2023-01.*2023-02"
  )

  expect_error(
    wapor_calc_rainfall_surplus(aeti, template),
    "layer count mismatch.*2.*1"
  )

  terra::time(aeti) <- as.Date(c("2023-01-01", "2023-02-01"))
  terra::time(precip) <- as.Date(c("2023-02-01", "2023-03-01"))
  expect_error(
    wapor_calc_et_rain(aeti, precip),
    "date mismatch.*2023-01-01.*2023-02-01"
  )

  # If neither stack exposes dates, preserve positional processing but say so.
  terra::time(aeti) <- as.Date(c(NA, NA))
  terra::time(precip) <- as.Date(c(NA, NA))
  names(aeti) <- c("layer1", "layer2")
  names(precip) <- c("layer1", "layer2")
  expect_warning(
    wapor_calc_rainfall_surplus(aeti, precip),
    "[Cc]annot verify.*dates.*position"
  )
})

test_that("wapor_calc_et_rain and wapor_calc_rainfall_surplus resample precip to AETI grid", {
  skip_if_not_installed("terra")
  # AETI: 4x4 fine grid (simulates ~20 m L3)
  aeti <- terra::rast(nrows = 4, ncols = 4,
                      xmin = 0, xmax = 1, ymin = 0, ymax = 1,
                      crs = "EPSG:4326", vals = 200)
  # PCP: 2x2 coarse grid (simulates ~5 km L1) with same extent
  pcp  <- terra::rast(nrows = 2, ncols = 2,
                      xmin = 0, xmax = 1, ymin = 0, ymax = 1,
                      crs = "EPSG:4326", vals = 300)
  # After harmonization pcp should be on the 4x4 grid
  etr  <- wapor_calc_et_rain(aeti, pcp)
  sur  <- wapor_calc_rainfall_surplus(aeti, pcp)
  expect_equal(terra::nrow(etr), 4)
  expect_equal(terra::ncol(etr), 4)
  expect_equal(terra::nrow(sur), 4)
  # With AETI=200 and P=300 (bilinear resampled to same extent): ET_rain=200, surplus=100
  expect_equal(as.numeric(terra::global(etr, "mean", na.rm = TRUE)[[1]]), 200)
  expect_equal(as.numeric(terra::global(sur, "mean", na.rm = TRUE)[[1]]), 100)
  # Identity: P_resampled = ET_rain + surplus
  pcp_h <- wapor_harmonize_raster(pcp, aeti, method = "bilinear")
  expect_equal(
    as.numeric(terra::global(etr + sur, "mean", na.rm = TRUE)[[1]]),
    as.numeric(terra::global(pcp_h,     "mean", na.rm = TRUE)[[1]])
  )
})

test_that("wapor_calc_cv and wapor_calc_theil return overall and by-class stats", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 2, ncols = 2, vals = c(10, 20, 30, 40), crs = "EPSG:4326")
  mask <- terra::rast(nrows = 2, ncols = 2, vals = c(1, 1, 2, 2), crs = "EPSG:4326")
  cv <- wapor_calc_cv(r, mask)
  expect_true(is.numeric(cv$overall) && is.finite(cv$overall))
  expect_equal(cv$overall, sd(c(10, 20, 30, 40)) / mean(c(10, 20, 30, 40)))
  expect_equal(nrow(cv$by_class), 2)

  theil <- wapor_calc_theil(r, mask)
  vals <- c(10, 20, 30, 40)
  xbar <- mean(vals)
  expected <- mean((vals / xbar) * log(vals / xbar))
  expect_equal(theil$overall, expected)
  expect_equal(nrow(theil$by_class), 2)
})

test_that("wapor_calc_beneficial_fraction clamps values to [0, 1]", {
  skip_if_not_installed("terra")
  # Numeric clamping
  expect_equal(wapor_calc_beneficial_fraction(500, 400), 1.0)
  expect_equal(wapor_calc_beneficial_fraction(-10, 400), 0.0)
  expect_equal(wapor_calc_beneficial_fraction(200, 400), 0.5)

  # Raster clamping
  grid <- list(nrow = 2L, ncol = 2L, res = c(1, 1),
               extent = list(xmin = 0, xmax = 2, ymin = 0, ymax = 2), crs = "")
  make_meta <- function(start, end, units = "mm") Rwapor:::.wapor_new_provenance(
    intervals = data.frame(layer = 1L, start_date = start, end_date = end,
                           temporal_code = "M", metadata_source = "test"),
    period = list(start = start, end = end), units = units, grid = grid,
    season_definition = list(id = paste(start, end))
  )
  prov <- list(
    transpiration = make_meta("2023-01-01", "2023-12-31", "mm"),
    aeti = make_meta("2023-01-01", "2023-12-31", "mm")
  )
  t_r <- terra::rast(nrows = 2, ncols = 2, vals = c(500, 200, -50, 100), crs = "EPSG:4326")
  aeti_r <- terra::rast(nrows = 2, ncols = 2, vals = c(400, 400, 400, 400), crs = "EPSG:4326")
  bf_r <- wapor_calc_beneficial_fraction(t_r, aeti_r, provenance = prov)
  expect_equal(as.numeric(terra::values(bf_r)), c(1.0, 0.5, 0.0, 0.25))
})

test_that("wapor_calc_nbwp and wapor_math_nbwp compute net biomass water productivity correctly", {
  skip_if_not_installed("terra")
  # 12,000 kg/ha biomass with 300 mm Transpiration -> 12,000 / (300 * 10) = 4.0 kg/m3
  expect_equal(wapor_calc_nbwp(12000, 300, biomass_unit = "kg/ha"), 4.0)
  expect_equal(wapor_calc_nbwp(12, 300, biomass_unit = "t/ha"), 4.0)
  expect_equal(wapor_math_nbwp(12000, 300, biomass_unit = "kg/ha"), 4.0)

  # SpatRaster
  grid <- list(nrow = 2L, ncol = 2L, res = c(1, 1),
               extent = list(xmin = 0, xmax = 2, ymin = 0, ymax = 2), crs = "")
  make_meta <- function(start, end, units = "mm") Rwapor:::.wapor_new_provenance(
    intervals = data.frame(layer = 1L, start_date = start, end_date = end,
                           temporal_code = "M", metadata_source = "test"),
    period = list(start = start, end = end), units = units, grid = grid,
    season_definition = list(id = paste(start, end))
  )
  prov <- list(
    biomass = make_meta("2023-01-01", "2023-12-31", "kg/ha"),
    transpiration = make_meta("2023-01-01", "2023-12-31", "mm")
  )
  bio_r <- terra::rast(nrows = 2, ncols = 2, vals = c(12000, 9000, 6000, 3000), crs = "EPSG:4326")
  t_r <- terra::rast(nrows = 2, ncols = 2, vals = c(300, 300, 200, 100), crs = "EPSG:4326")
  nbwp_r <- wapor_calc_nbwp(bio_r, t_r, biomass_unit = "kg/ha", provenance = prov)
  expect_equal(as.numeric(terra::values(nbwp_r)), c(4.0, 3.0, 3.0, 3.0))
})

test_that("wapor_audit_etlook_mass_balance checks conservation correctly", {
  skip_if_not_installed("terra")
  # Perfect mass balance (numeric)
  audit_ok <- wapor_audit_etlook_mass_balance(aeti = 100, e = 30, t = 65, i = 5)
  expect_true(audit_ok$is_conserved)
  expect_equal(audit_ok$max_absolute_error, 0.0)

  # Discrepant mass balance (numeric)
  audit_fail <- wapor_audit_etlook_mass_balance(aeti = 100, e = 30, t = 65, i = 10) # sum = 105 != 100
  expect_false(audit_fail$is_conserved)
  expect_equal(audit_fail$max_absolute_error, 5.0)

  # SpatRaster mass balance
  aeti_r <- terra::rast(nrows = 2, ncols = 2, vals = c(100, 200, 150, 80), crs = "EPSG:4326")
  e_r    <- terra::rast(nrows = 2, ncols = 2, vals = c(30, 60, 40, 20), crs = "EPSG:4326")
  t_r    <- terra::rast(nrows = 2, ncols = 2, vals = c(65, 130, 100, 55), crs = "EPSG:4326")
  i_r    <- terra::rast(nrows = 2, ncols = 2, vals = c(5, 10, 10, 5), crs = "EPSG:4326")
  audit_rast <- wapor_audit_etlook_mass_balance(aeti_r, e_r, t_r, i_r)
  expect_true(audit_rast$is_conserved)
  expect_equal(audit_rast$max_absolute_error, 0.0)
})

test_that("wapor_calc_yield_npp validates crop parameters strictly", {
  npp <- 400
  # Valid
  expect_silent(wapor_calc_yield_npp(npp, mc = 0.12, fc = 1.0, aot = 0.8, hi = 0.45))

  # Invalid MC (fraction >= 1 or < 0)
  expect_error(wapor_calc_yield_npp(npp, mc = 14, fc = 1.0, aot = 0.8, hi = 0.45), "moisture content 'mc'.*fraction in \\[0, 1\\)")
  expect_error(wapor_calc_yield_npp(npp, mc = -0.1, fc = 1.0, aot = 0.8, hi = 0.45), "moisture content 'mc'.*fraction in \\[0, 1\\)")

  # Invalid HI (not in (0, 1])
  expect_error(wapor_calc_yield_npp(npp, mc = 0.12, fc = 1.0, aot = 0.8, hi = 0), "Harvest index 'hi'.*fraction in \\(0, 1\\]")
  expect_error(wapor_calc_yield_npp(npp, mc = 0.12, fc = 1.0, aot = 0.8, hi = 1.5), "Harvest index 'hi'.*fraction in \\(0, 1\\]")

  # Invalid fc / aot
  expect_error(wapor_calc_yield_npp(npp, mc = 0.12, fc = -1, aot = 0.8, hi = 0.45), "Light Use Efficiency.*positive")
  expect_error(wapor_calc_yield_npp(npp, mc = 0.12, fc = 1.0, aot = -0.5, hi = 0.45), "Above-ground over total.*positive")
})
