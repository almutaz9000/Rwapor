test_that("seasonal zonal retry label uses the in-scope variable", {
  source_text <- paste(deparse(body(Rwapor::wapor_ts)), collapse = "\n")
  expect_false(grepl("var_for_code", source_text, fixed = TRUE))
  expect_true(grepl("zonal extraction", source_text, fixed = TRUE))
})
