test_that("L3-capable public APIs expose an explicit selection policy", {
  expect_true("l3_region" %in% names(formals(wapor_map)))
  expect_true("l3_mode" %in% names(formals(wapor_map)))
  expect_true("l3_region" %in% names(formals(wapor_ts)))
  expect_true("l3_mode" %in% names(formals(wapor_ts)))
})
