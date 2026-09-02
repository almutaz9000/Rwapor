test_that("wapor_res_key works for scalar, vector, empty, fallback, and unknown inputs", {
  # Scalar input
  expect_equal(wapor_res_key("L1-AETI-D"), "L1_300m")
  expect_equal(wapor_res_key("L1-PCP-D"), "L1_5000m")
  expect_equal(wapor_res_key("L1-RET-D"), "L1_30000m")
  expect_equal(wapor_res_key("L2-AETI-D"), "L2_100m")
  expect_equal(wapor_res_key("L3-AETI-D"), "L3_30m")
  expect_equal(wapor_res_key("AGERA5-ET0-E"), "AGERA5_11000m")

  # Level-only fallback
  expect_equal(wapor_res_key("L2-CUSTOM-M"), "L2_100m")
  expect_equal(wapor_res_key("L3-SOMETHING-A"), "L3_30m")

  # Unknown variable returns itself
  expect_equal(wapor_res_key("UNKNOWN-VAR"), "UNKNOWN-VAR")

  # Vector input (multiple elements in single call)
  input_vec <- c("L1-AETI-D", "L1-PCP-D", "L2-AETI-D", "UNKNOWN-VAR")
  expected_vec <- c("L1_300m", "L1_5000m", "L2_100m", "UNKNOWN-VAR")
  expect_equal(wapor_res_key(input_vec), expected_vec)

  # Empty vector
  expect_equal(wapor_res_key(character(0)), character(0))
})

test_that("wapor_group_by_res correctly groups variables by resolution key", {
  vars <- c("L1-AETI-D", "L1-NPP-D", "L1-PCP-D", "L2-AETI-D")
  grouped <- wapor_group_by_res(vars)

  expect_type(grouped, "list")
  expect_named(grouped, c("L1_300m", "L1_5000m", "L2_100m"), ignore.order = TRUE)
  expect_equal(grouped[["L1_300m"]], c("L1-AETI-D", "L1-NPP-D"))
  expect_equal(grouped[["L1_5000m"]], "L1-PCP-D")
  expect_equal(grouped[["L2_100m"]], "L2-AETI-D")
})
