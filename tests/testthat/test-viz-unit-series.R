skip_if_not_installed("ggplot2")

unit_data <- function() {
  data.frame(unit = rep(c("F1", "F2", "F3"), each = 3),
             season = rep(c("2022/2023", "2023/2024", "2024/2025"), 3),
             value = c(900, 950, 1010, 1150, 1200, 1180, 600, 640, 700),
             type = rep(c("Orange", "Lemon", "Orange"), each = 3))
}
etc <- data.frame(season = c("2024/2025", "2022/2023", "2023/2024"), value = c(1056, 1048, 1033))

render_ok <- function(p) {
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off())
  print(p)
  TRUE
}

test_that("one line per unit coloured by group, dashed reference in time order", {
  p <- wapor_plot_unit_series(unit_data(), "unit", "season", "value", colour_col = "type",
                              reference = etc, reference_label = "Seasonal ETc")
  b <- ggplot2::ggplot_build(p)
  expect_equal(length(unique(b$data[[1]]$group)), 3)            # unit lines
  expect_equal(length(unique(b$data[[1]]$colour)), 2)           # two types
  ref <- b$data[[3]]
  expect_equal(unique(ref$linetype), "dashed")
  expect_equal(ref$y[order(ref$x)], c(1048, 1033, 1056))        # sorted seasons
  expect_equal(b$plot$scales$get_scales("linetype")$get_labels(), "Seasonal ETc")  # trained scale
  expect_equal(p$labels$colour, "type")
  expect_true(render_ok(p))
})

test_that("factor time keeps its level order", {
  d <- unit_data()
  d$season <- factor(d$season, levels = c("2024/2025", "2023/2024", "2022/2023"))
  p <- wapor_plot_unit_series(d, "unit", "season", "value")
  expect_equal(levels(p$data$season), c("2024/2025", "2023/2024", "2022/2023"))
})

test_that("Date time gets a date axis; no colour column draws grey lines", {
  d <- unit_data()
  d$month <- as.Date(c("2024-03-01", "2024-04-01", "2024-05-01"))[match(d$season, unique(d$season))]
  ref <- data.frame(month = as.Date(c("2024-03-01", "2024-04-01", "2024-05-01")), value = c(90, 110, 140))
  p <- wapor_plot_unit_series(d, "unit", "month", "value", reference = ref, date_breaks = "1 month")
  expect_s3_class(p$scales$get_scales("x"), "ScaleContinuousDate")
  expect_equal(unique(ggplot2::ggplot_build(p)$data[[1]]$colour), "grey40")
  expect_true(render_ok(p))
})

test_that("no reference and no points gives only the unit lines", {
  p <- wapor_plot_unit_series(unit_data(), "unit", "season", "value", points = FALSE)
  expect_length(p$layers, 1)
  expect_null(p$scales$get_scales("linetype"))
})

test_that("the plot is saved as PNG and returned invisibly", {
  out <- file.path(withr::local_tempdir(), "series.png")
  expect_invisible(wapor_plot_unit_series(unit_data(), "unit", "season", "value", reference = etc,
                                          out_file = out, width = 4, height = 3, dpi = 50))
  expect_true(file.exists(out))
})

test_that("clear errors for bad input", {
  d <- unit_data()
  expect_error(wapor_plot_unit_series(d, "farm", "season", "value"), "not found")
  expect_error(wapor_plot_unit_series(d, "unit", "season", "type"), "numeric")
  expect_error(wapor_plot_unit_series(d, "unit", "season", "value", reference = data.frame(x = 1)),
               "reference")
  expect_error(wapor_plot_unit_series(list(), "unit", "season", "value"), "data frame")
})
