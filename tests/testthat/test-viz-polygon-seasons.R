skip_if_not_installed("ggplot2")

# Three layers ("seasons") of a 100 x 100 raster of 10 m pixels (UTM 36N);
# values rise from west to east and by 100 per season.
season_stack <- function() {
  r <- terra::rast(nrows = 100, ncols = 100, xmin = 500000, xmax = 501000,
                   ymin = 3000000, ymax = 3001000, crs = "EPSG:32636")
  base <- rep(seq_len(100), times = 100)
  s <- c(terra::setValues(r, base), terra::setValues(r, base + 100), terra::setValues(r, base + 200))
  names(s) <- c("2021/2022", "2022/2023", "2023/2024")
  s
}

# Three farms: A has two parcels, B and C one each.
season_parcels <- function() {
  sq <- function(x0, y0, s = 100) {
    sf::st_polygon(list(rbind(c(x0, y0), c(x0 + s, y0), c(x0 + s, y0 + s), c(x0, y0 + s), c(x0, y0))))
  }
  sf::st_sf(farm = c("A", "A", "B", "C"),
            geometry = sf::st_sfc(sq(500100, 3000100), sq(500300, 3000100), sq(500600, 3000600),
                                  sq(500800, 3000200), crs = 32636))
}

render_ok <- function(p) {
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off())
  print(p)
  TRUE
}

test_that("one row per unit in the given order and one column per layer", {
  p <- wapor_plot_polygon_seasons(season_stack(), season_parcels(), id_col = "farm", ids = c("C", "A"),
                                  row_labels = c("C above", "A below"), title = "AETI")
  lay <- ggplot2::ggplot_build(p)$layout$layout
  expect_equal(max(lay$ROW), 2)
  expect_equal(max(lay$COL), 3)
  expect_equal(levels(lay$.row), c("C above", "A below"))
  expect_equal(levels(lay$.col), c("2021/2022", "2022/2023", "2023/2024"))
  expect_true(render_ok(p))
})

test_that("every panel of a row shows the unit on the same 0-1 frame", {
  p <- wapor_plot_polygon_seasons(season_stack(), season_parcels(), id_col = "farm", ids = "B")
  px <- p$layers[[1]]$data
  expect_equal(nrow(px[px$.col == "2021/2022", ]), nrow(px[px$.col == "2023/2024", ]))
  ol <- p$layers[[2]]$data
  # B is a 100 m square with a 40 m buffer: outline from 40/180 to 140/180.
  expect_equal(range(ol$x), c(40, 140) / 180, tolerance = 1e-9)
  expect_equal(range(ol$y), c(40, 140) / 180, tolerance = 1e-9)
  # The same pixels two seasons later are 200 higher.
  a <- px[px$.col == "2021/2022", ]
  b <- px[px$.col == "2023/2024", ]
  expect_equal(b$value - a$value, rep(200, nrow(a)))
})

test_that("custom column labels replace the layer names", {
  p <- wapor_plot_polygon_seasons(season_stack(), season_parcels(), id_col = "farm", ids = "A",
                                  col_labels = c("S1\nETc 900", "S2\nETc 950", "S3\nETc 1000"))
  expect_equal(levels(ggplot2::ggplot_build(p)$layout$layout$.col),
               c("S1\nETc 900", "S2\nETc 950", "S3\nETc 1000"))
})

test_that("one colour scale from all pixels of all layers", {
  s <- season_stack()
  all_v <- as.vector(terra::values(s))
  p <- wapor_plot_polygon_seasons(s, season_parcels(), id_col = "farm")
  expect_equal(p$scales$get_scales("fill")$limits, unname(stats::quantile(all_v, c(0.02, 0.98))))
  full <- wapor_plot_polygon_seasons(s, season_parcels(), id_col = "farm", limits = "full")
  expect_equal(full$scales$get_scales("fill")$limits, c(1, 300))
})

test_that("percentile stretch anchors the gradient at the quantiles", {
  s <- season_stack()
  probs <- c(0.1, 0.5, 0.9)
  q <- unname(stats::quantile(as.vector(terra::values(s)), probs))
  p <- wapor_plot_polygon_seasons(s, season_parcels(), id_col = "farm", scale = "percentile_stretch",
                                  probs = probs)
  sc <- p$scales$get_scales("fill")
  expect_equal(sc$limits, range(q))
  expect_equal(sc$breaks, q)
  expect_equal(sc$get_labels(), format(signif(q, 3), trim = TRUE, big.mark = ","))
  expect_true(render_ok(p))
})

test_that("colour bar: panel height for one row, fixed length for several rows", {
  key_h <- function(p) p$theme$legend.key.height
  one <- wapor_plot_polygon_seasons(season_stack(), season_parcels(), id_col = "farm", ids = "A")
  expect_equal(grid::unitType(key_h(one)), "null")
  three <- wapor_plot_polygon_seasons(season_stack(), season_parcels(), id_col = "farm", legend_size = 3)
  expect_equal(as.numeric(key_h(three)), 3.6)
})

test_that("a unit outside the raster keeps an empty row", {
  parcels <- season_parcels()
  parcels$geometry[[4]] <- parcels$geometry[[4]] + c(5000, 5000)
  p <- wapor_plot_polygon_seasons(season_stack(), parcels, id_col = "farm")
  expect_equal(max(ggplot2::ggplot_build(p)$layout$layout$ROW), 3)
  expect_false("C" %in% p$layers[[1]]$data$.row)
  expect_true(render_ok(p))
})

test_that("the plot is saved as PNG and returned invisibly", {
  out <- file.path(withr::local_tempdir(), "sub", "seasons.png")
  expect_invisible(wapor_plot_polygon_seasons(season_stack(), season_parcels(), id_col = "farm",
                                              out_file = out, dpi = 50))
  expect_true(file.exists(out))
})

test_that("clear errors for bad input", {
  s <- season_stack()
  p <- season_parcels()
  expect_error(wapor_plot_polygon_seasons(s, p, id_col = "Farm"), "not found")
  expect_error(wapor_plot_polygon_seasons(s, p, id_col = "farm", ids = c("A", "Z")), "Unknown unit")
  expect_error(wapor_plot_polygon_seasons(s, p, id_col = "farm", ids = c("A", "A")), "repeat")
  expect_error(wapor_plot_polygon_seasons(s, p, id_col = "farm", ids = c("A", "B"), row_labels = "x"),
               "row_labels")
  expect_error(wapor_plot_polygon_seasons(s, p, id_col = "farm", col_labels = c("a", "b")), "col_labels")
  expect_error(wapor_plot_polygon_seasons(s, p, id_col = "farm", limits = 5), "limits")
  flat <- terra::setValues(s, 1)
  expect_error(wapor_plot_polygon_seasons(flat, p, id_col = "farm", scale = "percentile_stretch"),
               "not distinct")
})
