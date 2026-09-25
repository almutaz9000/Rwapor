skip_if_not_installed("ggplot2")

# 100 x 100 raster of 10 m pixels (UTM 36N); values rise from west to east.
grid_raster <- function() {
  r <- terra::rast(nrows = 100, ncols = 100, xmin = 500000, xmax = 501000,
                   ymin = 3000000, ymax = 3001000, crs = "EPSG:32636")
  terra::setValues(r, rep(seq_len(100), times = 100))
}

# Three farms: A has two parcels, B and C one each.
grid_parcels <- function() {
  sq <- function(x0, y0, s = 100) {
    sf::st_polygon(list(rbind(c(x0, y0), c(x0 + s, y0), c(x0 + s, y0 + s), c(x0, y0 + s), c(x0, y0))))
  }
  sf::st_sf(
    farm = c("A", "A", "B", "C"),
    crop = c("orange", "orange", "lemon", "grapefruit"),
    geometry = sf::st_sfc(sq(500100, 3000100), sq(500300, 3000100), sq(500600, 3000600), sq(500800, 3000200),
                          crs = 32636)
  )
}

# Render a page on a null device so layout errors surface.
render_ok <- function(p) {
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off())
  print(p)
  TRUE
}

test_that("one facet panel per unit, split into pages", {
  pages <- wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm", label_col = "crop",
                                   per_page = 2, ncol = 2, title = "AETI")
  expect_named(pages, c("page_1", "page_2"))
  expect_equal(pages$page_1$labels$title, "AETI (page 1 of 2)")
  built <- ggplot2::ggplot_build(pages$page_1)
  expect_equal(levels(built$layout$layout$.panel), c("A orange", "B lemon"))
  expect_true(render_ok(pages$page_2))
})

test_that("continuous scale defaults to the 2nd-98th percentile of the whole raster", {
  pages <- wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm")
  sc <- pages$page_1$scales$get_scales("fill")
  expect_equal(sc$limits, unname(stats::quantile(seq_len(100), c(0.02, 0.98))))
  full <- wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm", limits = "full")
  expect_equal(full$page_1$scales$get_scales("fill")$limits, c(1, 100))
})

test_that("percentile and breaks scales give classes", {
  pct <- wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm",
                                 scale = "percentile", probs = c(0.25, 0.5, 0.75))
  lev <- pct$page_1$scales$get_scales("fill")$limits
  expect_length(lev, 4) # < q25, q25-q50, q50-q75, > q75
  expect_true(render_ok(pct$page_1))

  brk <- wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm",
                                 scale = "breaks", breaks = c(1, 50, 100))
  expect_equal(brk$page_1$scales$get_scales("fill")$limits, c("1 to 50", "50 to 100"))
})

test_that("colour bar is never taller than the panel grid", {
  key_h <- function(p) p$theme$legend.key.height
  # Several rows: legend_size times the default bar (5 keys of 1.2 lines each).
  multi <- wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm", ncol = 2, legend_size = 3)
  expect_equal(grid::unitType(key_h(multi$page_1)), "lines")
  expect_equal(as.numeric(key_h(multi$page_1)), 3.6)
  # One row: the bar stretches to the panel height ("null" unit).
  single <- wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm", ncol = 3)
  expect_equal(grid::unitType(key_h(single$page_1)), "null")
  expect_true(render_ok(single$page_1))
  # Class legends keep one key per class.
  pct <- wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm", ncol = 3,
                                 scale = "percentile", legend_size = 3)
  expect_equal(as.numeric(key_h(pct$page_1)), 2.4)
})

test_that("pages are saved as PNG and returned invisibly", {
  out <- withr::local_tempdir()
  expect_invisible(wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm", per_page = 2,
                                           out_dir = out, prefix = "farms", width = 4, height = 3, dpi = 50))
  expect_setequal(list.files(out), c("farms_page1.png", "farms_page2.png"))
})

test_that("own scale per panel and true panel shapes render with patchwork", {
  skip_if_not_installed("patchwork")
  own <- wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm",
                                 common_scale = FALSE, mask_outside = TRUE)
  expect_s3_class(own$page_1, "patchwork")
  expect_true(render_ok(own$page_1))
  shape <- wapor_plot_polygon_grid(grid_raster(), grid_parcels(), id_col = "farm", square = FALSE)
  expect_true(render_ok(shape$page_1))
})

test_that("a unit outside the raster gets an empty panel", {
  parcels <- grid_parcels()
  parcels$geometry[[4]] <- parcels$geometry[[4]] + c(5000, 5000)
  pages <- wapor_plot_polygon_grid(grid_raster(), parcels, id_col = "farm")
  expect_equal(nlevels(ggplot2::ggplot_build(pages$page_1)$layout$layout$.panel), 3)
  expect_true(render_ok(pages$page_1))
})

test_that("buffer is converted to degrees for lon/lat rasters", {
  r <- terra::project(grid_raster(), "EPSG:4326")
  parcels <- sf::st_transform(grid_parcels()[3, ], 4326)
  pages <- wapor_plot_polygon_grid(r, parcels, id_col = "farm", buffer = 40)
  corners <- pages$page_1$layers[[1]]$data
  bb <- sf::st_bbox(parcels)
  side <- max(bb["xmax"] - bb["xmin"], bb["ymax"] - bb["ymin"]) + 2 * 40 / 111320
  expect_equal(diff(corners$x), unname(side), tolerance = 1e-9)
})

test_that("clear errors and warnings for bad input", {
  r <- grid_raster()
  p <- grid_parcels()
  expect_error(wapor_plot_polygon_grid(r, p, id_col = "Farm"), "not found")
  expect_error(wapor_plot_polygon_grid(r, p, id_col = "farm", label_col = "type"), "not found")
  expect_error(wapor_plot_polygon_grid(r, p, id_col = "farm", scale = "breaks"), "breaks")
  expect_error(wapor_plot_polygon_grid(r, p, id_col = "farm", limits = 5), "limits")
  expect_error(wapor_plot_polygon_grid(r, p, id_col = "farm", per_page = 0), "per_page")
  expect_error(suppressWarnings(wapor_plot_polygon_grid("not-a-raster", p, id_col = "farm")))

  p$farm[4] <- NA
  expect_warning(pages <- wapor_plot_polygon_grid(r, p, id_col = "farm"), "missing 'farm' dropped")
  expect_equal(nlevels(ggplot2::ggplot_build(pages$page_1)$layout$layout$.panel), 2)
  expect_warning(wapor_plot_polygon_grid(c(r, r * 2), grid_parcels(), id_col = "farm"), "only the first")
})
