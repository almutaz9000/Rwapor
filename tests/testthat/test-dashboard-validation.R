test_that("dashboard dependency list includes async runtime packages", {
  required <- Rwapor:::.wapor_dashboard_required_pkgs()

  expect_true("future" %in% required)
  expect_true("promises" %in% required)
})

test_that("analysis config validation handles malformed dates without throwing", {
  cfg <- list(
    ref_year = 2023,
    period = c("bad-date", "2023-01-10"),
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    indicators = "agg_aeti"
  )

  expect_no_error({
    validation <- wapor_validate_analysis_config(cfg)
    expect_false(validation$valid)
    expect_true(any(grepl("valid \\(YYYY-MM-DD\\)", validation$errors)))
  })
})

test_that("analysis config validation rejects unsupported period types", {
  cfg <- list(
    ref_year = 2023,
    period = list("2023-01-01", "2023-01-10"),
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    indicators = "agg_aeti"
  )

  validation <- wapor_validate_analysis_config(cfg)
  expect_false(validation$valid)
  expect_true(any(grepl("character or Date vector", validation$errors)))
})