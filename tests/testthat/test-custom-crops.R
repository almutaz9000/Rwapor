test_that("wapor_create_crop_params creates valid crop params", {
  cp <- wapor_create_crop_params(
    class_value = 1L,
    crop_name = "Local Durum Wheat",
    kc_ini = 0.35,
    kc_mid = 1.20,
    kc_end = 0.28,
    l_ini_days = 25L,
    l_mid_days = 45L,
    l_late_days = 30L,
    HI = 0.48
  )
  expect_true(is.data.frame(cp))
  expect_equal(nrow(cp), 1)
  expect_equal(cp$class_value, 1L)
  expect_equal(cp$kc_mid, 1.20)
  expect_equal(cp$HI, 0.48)
  expect_equal(cp$crop_name, "Local Durum Wheat")
})

test_that("wapor_custom_crop overrides default values", {
  cw <- wapor_custom_crop(
    base_crop = "Winter Wheat",
    class_value = 2L,
    crop_name = "Custom Wheat",
    kc_mid = 1.25,
    HI = 0.50
  )
  expect_true(is.data.frame(cw))
  expect_equal(cw$class_value, 2L)
  expect_equal(cw$kc_mid, 1.25)
  expect_equal(cw$HI, 0.50)
  expect_equal(cw$crop_name, "Custom Wheat")
  # Non-overridden fields should match FAO defaults
  expect_equal(cw$kc_ini, 0.40)
})

test_that("wapor_combine_crop_params combines and catches duplicate classes", {
  c1 <- wapor_custom_crop("Winter Wheat", class_value = 1L)
  c2 <- wapor_custom_crop("Maize", class_value = 2L)
  combined <- wapor_combine_crop_params(c1, c2)

  expect_equal(nrow(combined), 2)
  expect_equal(combined$class_value, c(1L, 2L))

  # Duplicate class value should error
  c3 <- wapor_custom_crop("Potato", class_value = 1L)
  expect_error(wapor_combine_crop_params(c1, c3), "Duplicate class_value")
})
