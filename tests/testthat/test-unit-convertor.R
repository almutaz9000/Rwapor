test_that("is_temperature_variable detects all AgERA5 temperature products", {
  # Internal function, test via namespace or evaluate
  is_temp <- Rwapor:::is_temperature_variable
  expect_true(is_temp("AGERA5-TMIN-E"))
  expect_true(is_temp("AGERA5-TMAX-E"))
  expect_true(is_temp("AGERA5-TAVG-E"))
  expect_true(is_temp("AGERA5-TDEW-E"))
  expect_true(is_temp("AGERA5-TEMP-E"))
  expect_true(is_temp("AGERA5-TMIN-D"))
  expect_true(is_temp("AGERA5-TMAX-D"))

  # Negative tests
  expect_false(is_temp("AGERA5-PRECIP-E"))
  expect_false(is_temp("AGERA5-PRECIP-D"))
  expect_false(is_temp("AGERA5-SOLAR-E"))
  expect_false(is_temp("L1-AETI-D"))
  expect_false(is_temp("L1-RET-E"))
  expect_false(is_temp("L2-AETI-D"))
  expect_false(is_temp("TMIN"))
})

test_that("wapor_convert_temperature converts Kelvin to Celsius for AgERA5 temperature variables", {
  skip_if_not_installed("terra")

  # Create synthetic raster with 300 Kelvin (~26.85 C)
  r_kelvin <- terra::rast(nrows = 2, ncols = 2, vals = c(300, 301.15, 273.15, 290))

  # Test TAVG
  r_celsius_tavg <- wapor_convert_temperature(r_kelvin, "AGERA5-TAVG-E")
  vals_tavg <- as.numeric(terra::values(r_celsius_tavg))
  expect_equal(vals_tavg, c(300 - 273.15, 28, 0, 290 - 273.15), tolerance = 1e-4)

  # Test TDEW
  r_celsius_tdew <- wapor_convert_temperature(r_kelvin, "AGERA5-TDEW-E")
  vals_tdew <- as.numeric(terra::values(r_celsius_tdew))
  expect_equal(vals_tdew, c(300 - 273.15, 28, 0, 290 - 273.15), tolerance = 1e-4)

  # Test TMIN and TMAX
  r_celsius_tmin <- wapor_convert_temperature(r_kelvin, "AGERA5-TMIN-E")
  expect_equal(as.numeric(terra::values(r_celsius_tmin))[1], 300 - 273.15, tolerance = 1e-4)

  # Non-temperature variable is unchanged
  r_non_temp <- wapor_convert_temperature(r_kelvin, "AGERA5-PRECIP-E")
  expect_equal(as.numeric(terra::values(r_non_temp)), as.numeric(terra::values(r_kelvin)))

  # Input validation
  expect_error(wapor_convert_temperature("not_a_raster", "AGERA5-TAVG-E"), "must be a SpatRaster")
})
