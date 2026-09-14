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

test_that("wapor_ordered_indicator_steps respects depends", {
  wapor_register_indicator_step("test_order_leaf", function(ctx) NULL, description = "leaf")
  wapor_register_indicator_step(
    "test_order_mid",
    function(ctx) NULL,
    depends = "test_order_leaf",
    description = "mid"
  )
  wapor_register_indicator_step(
    "test_order_top",
    function(ctx) NULL,
    depends = "test_order_mid",
    description = "top"
  )

  ordered <- wapor_ordered_indicator_steps(c("test_order_top", "test_order_mid", "test_order_leaf"))
  expect_equal(ordered, c("test_order_leaf", "test_order_mid", "test_order_top"))
})

test_that("wapor_ordered_indicator_steps errors on a dependency cycle", {
  wapor_register_indicator_step("test_cycle_a", function(ctx) NULL, depends = "test_cycle_b")
  wapor_register_indicator_step("test_cycle_b", function(ctx) NULL, depends = "test_cycle_a")
  expect_error(
    wapor_ordered_indicator_steps(c("test_cycle_a", "test_cycle_b")),
    "cycle"
  )
})

test_that("wapor_run_indicator_steps executes registered steps in dependency order", {
  order_seen <- character()
  wapor_register_indicator_step("test_run_base", function(ctx) {
    order_seen <<- c(order_seen, "test_run_base")
    ctx$results$base <- 1
  })
  wapor_register_indicator_step(
    "test_run_derived",
    function(ctx) {
      order_seen <<- c(order_seen, "test_run_derived")
      ctx$results$derived <- ctx$results$base + 1
    },
    depends = "test_run_base"
  )

  ctx <- new.env(parent = emptyenv())
  ctx$indicators <- c("test_run_derived")
  ctx$results <- list()
  ctx$progress_callback <- function(v, d) NULL
  wapor_run_indicator_steps(ctx)

  expect_equal(order_seen, c("test_run_base", "test_run_derived"))
  expect_equal(ctx$results$base, 1)
  expect_equal(ctx$results$derived, 2)
})
