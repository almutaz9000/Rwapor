test_that("wapor_res_key works for scalar, vector, and empty inputs", {
  expect_equal(wapor_res_key("L1-AETI-D"), "L1_300m")
  expect_equal(wapor_res_key("L1-PCP-D"), "L1_5000m")
  expect_equal(wapor_res_key("L1-RET-D"), "L1_30000m")
  expect_equal(wapor_res_key("L2-AETI-D"), "L2_100m")
  expect_equal(wapor_res_key("L3-AETI-D"), "L3_30m")
  expect_equal(wapor_res_key("AGERA5-ET0-E"), "AGERA5_11000m")

  # Vectorized input
  vars <- c("L1-AETI-D", "L1-PCP-D", "L2-AETI-D", "UNKNOWN-VAR")
  expected <- c("L1_300m", "L1_5000m", "L2_100m", "UNKNOWN-VAR")
  expect_equal(wapor_res_key(vars), expected)

  # Empty input
  expect_equal(wapor_res_key(character(0)), character(0))
})

test_that("wapor_group_by_res correctly groups variables by native resolution key", {
  vars <- c("L1-AETI-D", "L1-NPP-D", "L1-PCP-D", "L2-AETI-D")
  res <- wapor_group_by_res(vars)

  expect_named(res, c("L1_300m", "L1_5000m", "L2_100m"), ignore.order = TRUE)
  expect_equal(res$L1_300m, c("L1-AETI-D", "L1-NPP-D"))
  expect_equal(res$L1_5000m, "L1-PCP-D")
  expect_equal(res$L2_100m, "L2-AETI-D")
})
