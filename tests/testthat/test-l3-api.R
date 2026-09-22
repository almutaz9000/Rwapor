# Network guard: skip when WaPOR API is not reachable (CI offline, air-gapped)
skip_if_wapor_offline()

test_that("L3-capable public APIs expose an explicit selection policy", {
  expect_true("l3_region" %in% names(formals(wapor_map)))
  expect_true("l3_mode" %in% names(formals(wapor_map)))
  expect_true("l3_region" %in% names(formals(wapor_ts)))
  expect_true("l3_mode" %in% names(formals(wapor_ts)))
})
