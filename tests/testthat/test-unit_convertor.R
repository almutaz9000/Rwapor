# Tests for wapor_convert_temperature

test_that("wapor_convert_temperature converts Kelvin to Celsius for AgERA5 variables", {
  skip_if_not_installed("terra")

  # Create a mock raster with Kelvin values (e.g., 300K)
  r <- terra::rast(nrows = 5, ncols = 5, vals = 300)

  # For TMIN
  r_celsius_min <- wapor_convert_temperature(r, "AGERA5-TMIN-E")
  expect_equal(as.numeric(terra::values(r_celsius_min)[1]), 300 - 273.15, tolerance = 1e-6)

  # For TMAX
  r_celsius_max <- wapor_convert_temperature(r, "AGERA5-TMAX-E")
  expect_equal(as.numeric(terra::values(r_celsius_max)[1]), 300 - 273.15, tolerance = 1e-6)
})

test_that("wapor_convert_temperature leaves non-temperature variables unchanged", {
  skip_if_not_installed("terra")

  r <- terra::rast(nrows = 5, ncols = 5, vals = 100)

  # For WaPOR variable
  r_unchanged_wapor <- wapor_convert_temperature(r, "L1-AETI-D")
  expect_equal(as.numeric(terra::values(r_unchanged_wapor)[1]), 100)

  # For AgERA5 non-temperature variable
  r_unchanged_agera5 <- wapor_convert_temperature(r, "AGERA5-ET0-E")
  expect_equal(as.numeric(terra::values(r_unchanged_agera5)[1]), 100)
})

test_that("is_temperature_variable handles case sensitivity and prefixes correctly", {
  # Internal function - testing via standard testthat access to internals
  expect_true(is_temperature_variable("AGERA5-TMIN-E"))
  expect_true(is_temperature_variable("AGERA5-TMAX-E"))
  expect_false(is_temperature_variable("agera5-tmin-e")) # regex has ignore.case = FALSE
  expect_false(is_temperature_variable("L1-AETI-D"))
  expect_false(is_temperature_variable("AGERA5-ET0-E"))
})
