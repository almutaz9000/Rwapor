test_that("wapor_list_indicator_steps returns expected steps", {
  steps <- wapor_list_indicator_steps()
  expect_true(is.character(steps))
  expect_true("agg_aeti" %in% steps)
  expect_true("etc" %in% steps)
  expect_true("cwp_bwp" %in% steps)
  expect_true("beneficial_fraction" %in% steps)
})

test_that("wapor_register_indicator_step registers custom step", {
  custom_called <- FALSE
  wapor_register_indicator_step("test_custom_step", function(ctx) {
    custom_called <<- TRUE
    ctx$results$custom_value <- 42
  }, description = "Custom test step")

  expect_true("test_custom_step" %in% wapor_list_indicator_steps())

  mock_ctx <- new.env(parent = emptyenv())
  mock_ctx$results <- list()
  step_fn <- wapor_get_indicator_step("test_custom_step")
  step_fn(mock_ctx)

  expect_true(custom_called)
  expect_equal(mock_ctx$results$custom_value, 42)
})
