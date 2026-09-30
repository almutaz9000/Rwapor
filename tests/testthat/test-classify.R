test_that("adequacy uses documented tie rule", {
  expect_identical(as.character(wapor_classify(c(.68, .80, 1, 1.0001), scheme = "adequacy")),
                   c("poor", "acceptable", "good", "above ETc"))
  expect_identical(as.character(wapor_classify(c(.68, .80, 1, 1.0001), scheme = "adequacy", right = FALSE)),
                   c("acceptable", "good", "above ETc", "above ETc"))
})

test_that("custom raster classes and metadata", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 4, ncols = 4, vals = 1:16)
  out <- wapor_classify(r, breaks = c(4, 8, 12), labels = letters[1:4])
  expect_equal(terra::values(out)[, 1], rep(1:4, each = 4))
  expect_equal(terra::levels(out)[[1]]$class, letters[1:4])
  info <- wapor_class_info(out)
  expect_equal(info$breaks, c(4, 8, 12))
  expect_null(info$source)
  expect_identical(info$direction, "none")
})

test_that("quantile on a raster with no reference uses all cells", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 10, ncols = 10, vals = 1:100)
  out <- wapor_classify(r, breaks = c(0.05, 0.95), method = "quantile")
  info <- wapor_class_info(out)
  expect_equal(as.numeric(info$thresholds[1, -1]), c(5.95, 95.05))
  expect_equal(as.integer(table(terra::values(out)[, 1])), c(5, 90, 5))
})

test_that("quantiles use type 7 and reference groups", {
  out <- wapor_classify(1:100, breaks = c(.05, .95), method = "quantile", min_n = 30)
  info <- wapor_class_info(out)
  expect_equal(as.numeric(info$thresholds[1, -1]), c(5.95, 95.05))
  expect_equal(as.integer(table(out)), c(5, 90, 5))
  x <- c(1:100, 101:200); g <- rep(c("a", "b"), each = 100)
  out <- wapor_classify(x, breaks = c(.05, .95), method = "quantile", reference = g)
  info <- wapor_class_info(out)
  expect_equal(as.numeric(info$thresholds[1, -1]), c(5.95, 95.05))
  expect_equal(as.numeric(info$thresholds[2, -1]), c(105.95, 195.05))
  expect_equal(as.integer(table(out, g)), c(5, 90, 5, 5, 90, 5))
})

test_that("quantile groups match a group raster and two polygons", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  r <- terra::rast(nrows = 1, ncols = 200, xmin = 0, xmax = 200, ymin = 0, ymax = 1, crs = "EPSG:4326")
  terra::values(r) <- c(1:100, 101:200)
  g <- terra::rast(r)
  terra::values(g) <- c(rep(1L, 100), rep(2L, 100))
  out_g <- wapor_classify(r, breaks = c(0.05, 0.95), method = "quantile", reference = g)
  info <- wapor_class_info(out_g)
  expect_equal(as.numeric(info$thresholds[1, -1]), c(5.95, 95.05))
  expect_equal(as.numeric(info$thresholds[2, -1]), c(105.95, 195.05))
  expect_equal(as.integer(table(terra::values(out_g)[, 1], terra::values(g)[, 1])),
               c(5, 90, 5, 5, 90, 5))
  polys <- sf::st_sf(
    gid = c("a", "b"),
    geometry = sf::st_sfc(
      sf::st_polygon(list(cbind(c(0, 100, 100, 0, 0), c(0, 0, 1, 1, 0)))),
      sf::st_polygon(list(cbind(c(100, 200, 200, 100, 100), c(0, 0, 1, 1, 0))))
    ),
    crs = "EPSG:4326"
  )
  out_p <- wapor_classify(r, breaks = c(0.05, 0.95), method = "quantile",
                         reference = polys, id = "gid")
  expect_equal(terra::values(out_p)[, 1], terra::values(out_g)[, 1])
})

test_that("small quantile groups are missing with one warning", {
  expect_warning(out <- wapor_classify(1:40, breaks = c(.05, .95), method = "quantile", reference = c(rep("small", 20), rep("large", 20)), min_n = 30), "small")
  expect_true(all(is.na(out[1:20])))
})

test_that("uniformity schemes are per method", {
  expect_identical(as.character(wapor_classify(.70, scheme = "uniformity_surface")), "meets standard")
  expect_identical(as.character(wapor_classify(.70, scheme = "uniformity_sprinkler")), "below standard")
})

test_that("scheme options override breaks without labels", {
  old <- options(Rwapor.class_breaks = list(adequacy = list(breaks = c(.6, .8, 1))))
  on.exit(options(old), add = TRUE)
  expect_identical(as.character(wapor_classify(.65, scheme = "adequacy")), "acceptable")
})

test_that("validation errors are explicit", {
  expect_error(wapor_classify("x", breaks = 1), "numeric")
  expect_error(wapor_classify(c(1, Inf), breaks = 2), "finite")
  expect_error(wapor_classify(1, breaks = c(2, 1)), "increasing")
  expect_error(wapor_classify(1, breaks = c(1, 1)), "duplicates")
  expect_error(wapor_classify(1, breaks = 1:2, labels = "x"), "length")
  expect_error(wapor_classify(1:30, breaks = c(0, .9), method = "quantile"), "probabilities")
  expect_error(wapor_classify(1:2, breaks = 1, reference = data.frame(x = 1)), "id")
  expect_error(wapor_class_defaults("unknown"), "Available schemes")
  expect_error(wapor_classify(1, scheme = "unknown"), "Available schemes")
  sources <- vapply(wapor_class_defaults(), function(s) s$source, character(1))
  expect_true(all(nzchar(sources)))
})

test_that("raster metadata survives GeoTIFF", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 2, ncols = 2, vals = 1:4)
  out <- wapor_classify(r, breaks = 2, labels = c("low", "high"))
  path <- tempfile(fileext = ".tif")
  terra::writeRaster(out, path, overwrite = TRUE)
  expect_equal(wapor_class_info(terra::rast(path))$breaks, 2)
  expect_identical(wapor_class_info(terra::rast(path))$source, NULL)
})
