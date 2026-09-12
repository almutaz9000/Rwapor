# Tests for wapor_res_key() and wapor_group_by_res()

test_that("wapor_res_key handles scalar inputs correctly", {
  expect_equal(wapor_res_key("L1-AETI-D"), "L1_300m")
  expect_equal(wapor_res_key("L1-PCP-D"), "L1_5000m")
  expect_equal(wapor_res_key("L1-RET-D"), "L1_30000m")
  expect_equal(wapor_res_key("L1-RSM-D"), "L1_500m")
  expect_equal(wapor_res_key("L2-AETI-D"), "L2_100m")
  expect_equal(wapor_res_key("L3-AETI-D"), "L3_30m")
  expect_equal(wapor_res_key("AGERA5-ET0-E"), "AGERA5_11000m")
})

test_that("wapor_res_key handles character vectors natively", {
  vars <- c("L1-AETI-D", "L1-PCP-D", "L2-AETI-D", "L3-AETI-D", "AGERA5-ET0-E")
  expected <- c("L1_300m", "L1_5000m", "L2_100m", "L3_30m", "AGERA5_11000m")
  expect_equal(wapor_res_key(vars), expected)
})

test_that("wapor_res_key handles empty vectors and unknown inputs", {
  expect_equal(wapor_res_key(character(0)), character(0))

  # Level fallback (e.g. L2-CUSTOM)
  expect_equal(wapor_res_key("L2-CUSTOM-D"), "L2_100m")

  # Unknown variable returns itself
  expect_equal(wapor_res_key("UNKNOWN-VAR-X"), "UNKNOWN-VAR-X")

  # Mixed vector with known, fallback, and unknown variables
  mixed_vars <- c("L1-AETI-D", "L2-NEW-M", "UNKNOWN-1")
  expect_equal(wapor_res_key(mixed_vars), c("L1_300m", "L2_100m", "UNKNOWN-1"))
})

test_that("wapor_res_key validates input types", {
  expect_error(wapor_res_key(123))
  expect_error(wapor_res_key(NULL))
})

test_that("wapor_group_by_res correctly groups variables", {
  vars <- c("L1-AETI-D", "L1-NPP-D", "L1-PCP-D", "L2-AETI-D")
  grouped <- wapor_group_by_res(vars)

  expect_type(grouped, "list")
  expect_named(grouped, c("L1_300m", "L1_5000m", "L2_100m"), ignore.order = TRUE)
  expect_equal(grouped$L1_300m, c("L1-AETI-D", "L1-NPP-D"))
  expect_equal(grouped$L1_5000m, "L1-PCP-D")
  expect_equal(grouped$L2_100m, "L2-AETI-D")
})
