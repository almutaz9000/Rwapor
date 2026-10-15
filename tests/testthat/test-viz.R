test_that("map palettes are appropriate for indicator semantics", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("terra")

  x <- terra::rast(nrows = 1, ncols = 3, vals = c(0.5, 1, 1.5),
                   xmin = 0, xmax = 3, ymin = 0, ymax = 1,
                   crs = "EPSG:4326")

  adequacy <- wapor_plot_map(x, indicator = "adequacy")
  built <- ggplot2::ggplot_build(adequacy)
  expect_match(class(adequacy$scales$get_scales("fill"))[1], "ScaleContinuous")
  expect_identical(toupper(built$data[[1]]$fill[2]), "#F7F7F7")

  cwp <- wapor_plot_map(x, indicator = "CWP")
  anomaly <- wapor_plot_anomaly(x - 1)
  expect_true(length(unique(ggplot2::ggplot_build(cwp)$data[[1]]$fill)) > 1L)
  anomaly_built <- ggplot2::ggplot_build(anomaly)
  expect_identical(toupper(anomaly_built$data[[1]]$fill[2]), "#F7F7F7")
})

test_that("large continuous rasters are aggregated to the configured cell budget", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("terra")

  x <- terra::rast(nrows = 10, ncols = 10, vals = seq_len(100),
                   xmin = 0, xmax = 10, ymin = 0, ymax = 10,
                   crs = "EPSG:4326")
  p <- wapor_plot_map(x, max_cells = 16)

  expect_lte(nrow(p$data), 16L)
  expect_lt(nrow(p$data), terra::ncell(x))
})

test_that("comparison maps derive common limits from all inputs", {
  expect_identical(
    Rwapor:::.wapor_plot_comparison_limits(
      list(matrix(c(0, 1), nrow = 1), matrix(c(10, 20), nrow = 1))
    ),
    c(0, 20)
  )

  skip_if_not_installed("terra")
  a <- terra::rast(nrows = 1, ncols = 2, vals = c(-5, 2))
  b <- terra::rast(nrows = 1, ncols = 2, vals = c(3, 12))
  expect_equal(Rwapor:::.wapor_plot_comparison_limits(list(a, b)), c(-5, 12))
  expect_equal(
    Rwapor:::.wapor_plot_comparison_limits(list(matrix(10), matrix(10))),
    c(9.5, 10.5)
  )
})

test_that("large categorical rasters require an explicit aggregation method", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("terra")

  x <- terra::rast(nrows = 4, ncols = 4, vals = rep(c(1, 2), 8),
                   xmin = 0, xmax = 4, ymin = 0, ymax = 4,
                   crs = "EPSG:4326")
  levels(x) <- data.frame(ID = c(1, 2), label = c("low", "high"))

  expect_error(wapor_plot_map(x, indicator = "class", max_cells = 4),
               "aggregate_fun")
  expect_s3_class(wapor_plot_map(x, indicator = "class", max_cells = 4,
                                 aggregate_fun = "modal"), "ggplot")
})

test_that("map annotations are opt-in and require georeferenced rasters", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("terra")
  skip_if_not_installed("ggspatial")

  x <- terra::rast(nrows = 2, ncols = 2, vals = 1:4,
                   xmin = 0, xmax = 2, ymin = 0, ymax = 2,
                   crs = "EPSG:4326")
  p <- wapor_plot_map(x, show_scale = TRUE, show_north_arrow = TRUE)
  expect_s3_class(p, "ggplot")
  expect_gte(length(p$layers), 3L)
  expect_no_warning(ggplot2::ggplot_build(p))
})
