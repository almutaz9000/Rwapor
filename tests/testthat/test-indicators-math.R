# =============================================================================
# Tests for the terra-free indicator math layer (Rwapor Phase 1.2)
# =============================================================================

test_that("math adequacy_etc matches the public numeric API and handles zero", {
  expect_equal(wapor_math_adequacy_etc(400, 400), 1)
  expect_equal(wapor_math_adequacy_etc(300, 400), 0.75)
  expect_true(is.na(wapor_math_adequacy_etc(100, 0)))
  expect_equal(wapor_math_adequacy_etc(c(400, 300, 100), c(400, 400, 0)), c(1, 0.75, NA_real_))
  expect_equal(wapor_calc_adequacy_etc(300, 400), wapor_math_adequacy_etc(300, 400))
})

test_that("math beneficial fraction matches the public numeric API", {
  expect_equal(wapor_math_beneficial_fraction(200, 400), 0.5)
  expect_true(is.na(wapor_math_beneficial_fraction(10, 0)))
  expect_equal(
    wapor_calc_beneficial_fraction(200, 400),
    wapor_math_beneficial_fraction(200, 400)
  )
})

test_that("math USDA Peff matches the piecewise formula", {
  expect_equal(wapor_math_peff_usda(100), 100 * (125 - 0.2 * 100) / 125)
  expect_equal(wapor_math_peff_usda(250), 250 * (125 - 0.2 * 250) / 125)
  expect_equal(wapor_math_peff_usda(300), 125 + 0.1 * 300)
})

test_that("math green and blue water partition AETI against Peff", {
  expect_equal(wapor_math_green_water(350, 200), 200)
  expect_equal(wapor_math_blue_water(350, 200), 150)
  expect_equal(wapor_math_green_water(150, 200), 150)
  expect_equal(wapor_math_blue_water(150, 200), 0)
  expect_equal(wapor_calc_green_water(350, 200), wapor_math_green_water(350, 200))
  expect_equal(wapor_calc_blue_water(350, 200), wapor_math_blue_water(350, 200))
})

test_that("math NPP biomass and yield match the FAO conversion", {
  npp <- 10
  expect_equal(wapor_math_npp_to_biomass(npp), npp * 22.222)
  expect_equal(wapor_convert_npp_tbp(npp), wapor_math_npp_to_biomass(npp))
  expect_equal(
    wapor_math_yield_from_npp(npp, mc = 0.2, fc = 1, aot = 0.8, hi = 0.45),
    wapor_calc_yield_npp(npp, mc = 0.2, fc = 1, aot = 0.8, hi = 0.45)
  )
})

test_that("math CWP and BWP convert mm to m3/ha", {
  expect_equal(wapor_math_cwp(5000, 400), 5000 / (400 * 10))
  expect_equal(wapor_math_cwp(5, 400, yield_unit = "t/ha"), 5000 / (400 * 10))
  expect_true(is.na(wapor_math_cwp(5000, 0)))
  expect_equal(wapor_calc_cwp(5000, 400), wapor_math_cwp(5000, 400))
  expect_equal(wapor_calc_bwp(12000, 400), wapor_math_bwp(12000, 400))
})

test_that("math area-weighted mean and zonal mean work on matrices", {
  values <- matrix(c(10, 20, 30, 40), nrow = 2, byrow = TRUE)
  area <- matrix(c(1, 1, 3, 3), nrow = 2, byrow = TRUE)
  expect_equal(wapor_math_area_weighted_mean(values, area), sum(values * area) / sum(area))
  expect_equal(wapor_math_area_weighted_mean(values, NULL), mean(values))

  mask <- matrix(c(1, 1, 2, 2), nrow = 2, byrow = TRUE)
  zonal <- wapor_math_zonal_mean_by_class(values, mask, area)
  expect_equal(zonal[["1"]], 15)
  expect_equal(zonal[["2"]], 35)
})
