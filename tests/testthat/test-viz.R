test_that("percentile limits use 2/98 by default", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 10, ncols = 10, vals = 1:100)
  lim <- .wapor_percentile_limits(r)
  expect_equal(lim[1], as.numeric(quantile(1:100, 0.02)))
  expect_equal(lim[2], as.numeric(quantile(1:100, 0.98)))
  lim2 <- .wapor_percentile_limits(r, vmin = 0, vmax = 50)
  expect_equal(lim2, c(0, 50))
})

test_that("wapor_plot_map returns a ggplot and can write a PNG", {
  skip_if_not_installed("terra")
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("tidyterra")
  r <- terra::rast(
    nrows = 8, ncols = 8, xmin = 0, xmax = 8, ymin = 0, ymax = 8,
    crs = "EPSG:4326", vals = 1:64
  )
  p <- wapor_plot_map(r, indicator = "agg_aeti", title = "Seasonal AETI")
  expect_s3_class(p, "ggplot")
  path <- tempfile(fileext = ".png")
  on.exit(unlink(path, force = TRUE), add = TRUE)
  wapor_plot_map(r, indicator = "agg_aeti", title = "Seasonal AETI", filename = path, dpi = 72)
  expect_true(file.exists(path))
  expect_gt(file.info(path)$size, 0)
})

test_that("wapor_plot_comparison requires matching titles", {
  skip_if_not_installed("terra")
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("tidyterra")
  skip_if_not_installed("patchwork")
  r1 <- terra::rast(nrows = 4, ncols = 4, vals = 1:16, crs = "EPSG:4326")
  r2 <- terra::rast(nrows = 4, ncols = 4, vals = 17:32, crs = "EPSG:4326")
  expect_error(wapor_plot_comparison(list(r1, r2), titles = "only one"), "same length")
  p <- wapor_plot_comparison(list(r1, r2), titles = c("Season A", "Season B"), indicator = "agg_aeti")
  expect_true(inherits(p, "ggplot") || inherits(p, "patchwork"))
})

test_that("wapor_plot_timeseries draws grouped lines", {
  skip_if_not_installed("ggplot2")
  df <- data.frame(
    start_date = as.Date(c("2023-01-01", "2023-01-11", "2023-01-01", "2023-01-11")),
    mean = c(10, 12, 8, 9),
    ID = c("A", "A", "B", "B"),
    stringsAsFactors = FALSE
  )
  p <- wapor_plot_timeseries(df, group = "ID", title = "Dekadal AETI")
  expect_s3_class(p, "ggplot")
})
