test_that("wapor_clear_url_cache executes without error", {
  res <- wapor_clear_url_cache()
  expect_true(is.numeric(res) || is.integer(res))
})
