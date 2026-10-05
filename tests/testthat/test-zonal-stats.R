test_that("weighted statistics match independent values", {
  expect_equal(Rwapor:::.wapor_wmean(c(1, 2, 3), c(1, 1, 2)), 2.25)
  expect_equal(Rwapor:::.wapor_wgini(1:100, rep(1, 100)), .33, tolerance = 1e-12)
  expect_equal(Rwapor:::.wapor_wtheil(1:4, rep(1, 4)), .106440135, tolerance = 1e-6)
  expect_equal(Rwapor:::.wapor_wquantile(1:100, rep(1, 100), .95), unname(quantile(1:100, .95, type = 7)), tolerance = 1e-12)
})

test_that("zonal mean and fractional weights", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  r <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 1, vals = c(500, 300), crs = "EPSG:32636")
  z <- sf::st_sf(id = "z", geometry = sf::st_sfc(sf::st_polygon(list(matrix(c(0,0,2,0,2,1,0,1,0,0), ncol=2, byrow=TRUE))), crs=32636))
  w <- terra::setValues(r, c(1, .25))
  ans <- Rwapor::wapor_zonal_stats(r, z, "id", stats = "mean", weights = w, aoi = FALSE)
  expect_equal(ans$value, 460, tolerance = 1e-12)
  crop <- terra::rast(nrows=1, ncols=8, xmin=0, xmax=2, ymin=0, ymax=1, vals=c(1,1,1,1,1,2,2,2), crs="EPSG:32636")
  h <- Rwapor::wapor_harmonize_mask(crop, r, class=1, min_fraction=0)
  from_mask <- Rwapor::wapor_zonal_stats(r, z, "id", stats="mean", weights=h$fraction, aoi=FALSE)
  expect_equal(from_mask$value, 460, tolerance=1e-12)
})

.zgrid <- function() {
  r <- terra::rast(nrows = 10, ncols = 10, xmin = 700000, xmax = 700200,
                   ymin = 3600000, ymax = 3600200, crs = "EPSG:32636")
  terra::values(r) <- matrix(1:100, 10, 10, byrow = TRUE)
  try(terra::units(r) <- "mm", silent = TRUE)
  names(r) <- "aeti"
  r
}
.zpoly <- function(xmin, xmax, ymin, ymax, id = "z") {
  sf::st_sf(id = id, geometry = sf::st_sfc(sf::st_polygon(list(matrix(
    c(xmin, ymin, xmax, ymin, xmax, ymax, xmin, ymax, xmin, ymin), ncol = 2, byrow = TRUE
  ))), crs = 32636))
}
.zstat <- function(ans, stat, zone = NULL) {
  d <- ans[ans$stat == stat, , drop = FALSE]
  if (!is.null(zone)) d <- d[d$zone_key == zone, , drop = FALSE]
  d$value
}

test_that("aligned halves: mean count area coverage", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  r <- .zgrid()
  z <- .zpoly(700000, 700100, 3600000, 3600200, "left")
  ans <- wapor_zonal_stats(r, z, "id", stats = c("mean", "count", "area_ha", "coverage", "mask_fraction"), aoi = FALSE)
  m <- matrix(1:100, 10, 10, byrow = TRUE)
  expect_equal(.zstat(ans, "mean"), mean(m[, 1:5]), tolerance = 1e-8)
  expect_equal(.zstat(ans, "count"), 50)
  expect_equal(.zstat(ans, "area_ha"), 2, tolerance = 1e-6)
  expect_equal(.zstat(ans, "coverage"), 1, tolerance = 1e-8)
  expect_equal(.zstat(ans, "mask_fraction"), 1, tolerance = 1e-8)
})

test_that("partial cells: full plus half cell mean 13.333", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  r <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 40, ymin = 0, ymax = 20, crs = "EPSG:32636", vals = c(10, 20))
  try(terra::units(r) <- "mm", silent = TRUE)
  z <- .zpoly(0, 30, 0, 20)
  z <- sf::st_set_crs(z, 32636)
  ans <- wapor_zonal_stats(r, z, "id", stats = "mean", aoi = FALSE, min_coverage = 0)
  expect_equal(ans$value, (10 * 400 + 20 * 200) / 600, tolerance = 1e-6)
  ans2 <- wapor_zonal_stats(r, z, "id", stats = "mean", aoi = FALSE, min_coverage = 0, min_cell_fraction = 0.6)
  expect_equal(ans2$value, 10, tolerance = 1e-6)
})

test_that("crop share vs coverage", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  r <- .zgrid()
  mask <- r
  terra::values(mask) <- NA
  terra::values(mask)[1:20] <- 1
  terra::values(r)[16:20] <- NA
  z <- .zpoly(700000, 700200, 3600000, 3600200)
  ans <- wapor_zonal_stats(r, z, "id", stats = c("mask_fraction", "coverage", "mean"), mask = mask, aoi = FALSE, min_coverage = 0.5)
  expect_equal(.zstat(ans, "mask_fraction"), 0.20, tolerance = 0.02)
  expect_equal(.zstat(ans, "coverage"), 0.75, tolerance = 0.05)
  expect_false(is.na(.zstat(ans, "mean")))
})

test_that("volumes from depths and days", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  r <- terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 100, ymin = 0, ymax = 200, crs = "EPSG:32636", vals = 100)
  try(terra::units(r) <- "mm", silent = TRUE)
  z <- .zpoly(0, 100, 0, 200)
  z <- sf::st_set_crs(z, 32636)
  ans <- wapor_zonal_stats(r, z, "id", stats = "sum_volume", aoi = FALSE, min_coverage = 0)
  expect_equal(ans$value[ans$stat == "sum_volume"], 2000, tolerance = 1)
  r2 <- r
  terra::values(r2) <- 2
  try(terra::units(r2) <- "mm/day", silent = TRUE)
  expect_warning(ans2 <- wapor_zonal_stats(r2, z, "id", stats = "sum_volume", aoi = FALSE, min_coverage = 0), "days")
  expect_false("sum_volume" %in% ans2$stat)
  ans3 <- wapor_zonal_stats(r2, z, "id", stats = "sum_volume", aoi = FALSE, min_coverage = 0, days = 8)
  expect_equal(ans3$value[ans3$stat == "sum_volume"], 320, tolerance = 1)
})

test_that("spread statistics on 1:100", {
  expect_equal(1 - Rwapor:::.wapor_wsd(1:100, rep(1, 100), "population") / mean(1:100), 0.42840, tolerance = 1e-4)
  expect_equal(Rwapor:::.wapor_cu(1:100, rep(1, 100)), 0.504950, tolerance = 1e-5)
  expect_equal(Rwapor:::.wapor_du_lq(1:100, rep(1, 100)), 0.257426, tolerance = 1e-5)
  expect_equal(Rwapor:::.wapor_wgini(1:100, rep(1, 100)), 0.33, tolerance = 1e-2)
  expect_equal(Rwapor:::.wapor_wtheil(c(1, 2, 3, 4), rep(1, 4)), 0.106440, tolerance = 1e-5)
  expect_equal(Rwapor:::.wapor_wsd(1:100, rep(1, 100), "sample"), stats::sd(1:100), tolerance = 1e-10)
})

test_that("class share lists zeros and no-data", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  r <- .zgrid()
  z <- .zpoly(700000, 700200, 3600000, 3600200)
  ans <- wapor_zonal_stats(r, z, "id", stats = "class_share", breaks = c(25, 50, 75),
                          labels = c("a", "b", "c", "d"), aoi = FALSE, min_coverage = 0)
  pct <- ans$value[ans$stat == "class_pct"]
  expect_equal(sum(pct), 100, tolerance = 1e-6)
  expect_true("no data" %in% ans$class)
})

test_that("n_eff warning for 4 cells", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 40, ymin = 0, ymax = 40, crs = "EPSG:32636", vals = 1:4)
  z <- .zpoly(0, 40, 0, 40)
  z <- sf::st_set_crs(z, 32636)
  expect_warning(wapor_zonal_stats(r, z, "id", stats = "sd", aoi = FALSE, min_coverage = 0), "3 x 3")
})

test_that("normalize_id and missing id error", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  r <- .zgrid()
  z <- .zpoly(700000, 700200, 3600000, 3600200, " f01 ")
  ans <- wapor_zonal_stats(r, z, "id", stats = "mean", aoi = FALSE)
  expect_equal(unique(ans$zone_key), "F01")
  expect_error(wapor_zonal_stats(r, z, "missing", aoi = FALSE), "available columns")
})

test_that("wide format", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  r <- .zgrid()
  z <- .zpoly(700000, 700200, 3600000, 3600200)
  w <- wapor_zonal_stats(r, z, "id", stats = c("mean", "count"), aoi = FALSE, format = "wide")
  expect_true("mean" %in% names(w))
})
