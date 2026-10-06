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

# =============================================================================
# perf-b: the restructured engine returns exactly the table of the frozen
# reference (tests/testthat/helper-zonal-reference.R), for any layer chunk size
# =============================================================================

.zeq_fixture <- function() {
  set.seed(7)
  r <- terra::rast(nrows = 60, ncols = 60, xmin = 700000, xmax = 701200, ymin = 3600000, ymax = 3601200,
                   crs = "EPSG:32636", nlyrs = 6)
  x <- round(stats::runif(60 * 60 * 6, 0, 80)) / 10
  x[sample(length(x), 600)] <- NA
  terra::values(r) <- x
  names(r) <- sprintf("d%02d", 1:6)
  terra::units(r) <- "mm/day"
  r[[1]][1:20, 1:20] <- NA                      # one zone falls below min_coverage in layer 1
  g <- expand.grid(i = 0:2, j = 0:2)
  z <- sf::st_sf(
    scheme = paste0("S", g$i %/% 2), farm = sprintf("f%02d ", seq_len(9)),
    geometry = sf::st_sfc(lapply(seq_len(9), function(k) {
      x0 <- 700000 + g$i[k] * 400 + 7; y0 <- 3600000 + g$j[k] * 400 + 13   # borders cut cells
      sf::st_polygon(list(cbind(x0 + c(0, 290, 290, 0, 0), y0 + c(0, 0, 250, 250, 0))))
    }), crs = 32636)
  )
  square <- function(x0, y0, side) sf::st_sfc(sf::st_polygon(list(cbind(
    x0 + c(0, side, side, 0, 0), y0 + c(0, 0, side, side, 0)))), crs = 32636)
  z <- rbind(z,
             sf::st_sf(scheme = "S9", farm = "away", geometry = square(900000, 3600000, 50)),   # no overlap
             sf::st_sf(scheme = "S0", farm = "tiny", geometry = square(700905, 3600905, 30)))   # under 3 x 3 cells
  full <- terra::rast(r[[1]]); terra::values(full) <- round(stats::runif(3600, 0, 80)) / 10
  names(full) <- "full"; terra::units(full) <- "mm"
  mk <- terra::rast(r[[1]]); terra::values(mk) <- stats::rbinom(3600, 1, .7)
  wt <- terra::rast(r[[1]]); terra::values(wt) <- stats::runif(3600)
  cl <- terra::rast(r[[1]]); terra::values(cl) <- sample(1:4, 3600, TRUE); names(cl) <- "cls"
  list(r = r, z = z, full = full, mask = mk, weights = wt, classes = cl)
}

.zeq_run <- function(f, args) {
  w <- character()
  v <- withCallingHandlers(
    tryCatch(do.call(f, args), error = function(e) paste("ERROR:", conditionMessage(e))),
    warning = function(cnd) { w <<- c(w, conditionMessage(cnd)); invokeRestart("muffleWarning") }
  )
  list(value = v, warnings = w)
}

.zeq_cases <- function(fx) {
  all_stats <- c("mean", "sd", "cv", "cu", "du_lq", "gini", "theil", "min", "max", "count", "n_eff",
                 "quantiles", "area_ha", "mask_fraction", "coverage", "sum_volume")
  list(
    defaults_two_levels_aoi = list(x = fx$r, zones = fx$z, id = c("scheme", "farm")),
    all_stats_with_days = list(x = fx$r, zones = fx$z, id = "farm", stats = all_stats, days = rep(10, 6),
                               dissolve = FALSE, aoi = FALSE),
    all_stats_volume_skipped = list(x = fx$r, zones = fx$z, id = "farm", stats = all_stats, aoi = FALSE),
    mask_and_weights = list(x = fx$r, zones = fx$z, id = "farm", mask = fx$mask, weights = fx$weights,
                            stats = c("mean", "sd", "coverage", "mask_fraction", "quantiles")),
    sample_sd_thresholds = list(x = fx$r, zones = fx$z, id = "farm", stats = c("mean", "sd", "cv", "quantiles"),
                                sd_type = "sample", probs = c(.05, .5, .95), min_coverage = .9,
                                min_cell_fraction = .5, min_mask_area_ha = 1),
    class_share_breaks = list(x = fx$full, zones = fx$z, id = "farm", stats = c("mean", "class_share"),
                              breaks = c(2, 4, 6), labels = c("a", "b", "c", "d"), aoi = FALSE),
    class_share_integer_layer = list(x = fx$classes, zones = fx$z, id = "farm", stats = "class_share"),
    count_only = list(x = fx$r, zones = fx$z, id = "farm", stats = "count", aoi = FALSE),
    layers_season_raw_ids = list(x = fx$r, zones = fx$z, id = "farm", layers = c(3, 5), season = "2024",
                                 normalize_id = FALSE),
    wide = list(x = fx$r[[1:2]], zones = fx$z, id = "farm", stats = c("mean", "coverage"), format = "wide",
                aoi = FALSE),
    class_share_error = list(x = fx$r[[2]], zones = fx$z, id = "farm", stats = "class_share")
  )
}

test_that("restructured wapor_zonal_stats() equals the frozen reference, tables and warnings", {
  skip_if_not_installed("exactextractr")
  fx <- .zeq_fixture()
  cases <- .zeq_cases(fx)
  for (nm in names(cases)) {
    ref <- .zeq_run(reference_zonal_stats, cases[[nm]])
    new <- .zeq_run(Rwapor::wapor_zonal_stats, cases[[nm]])
    expect_identical(new$value, ref$value, info = nm)
    expect_identical(new$warnings, ref$warnings, info = nm)
  }
  # The cases exercise what they claim to.
  expect_true(any(grepl("no overlap", .zeq_run(reference_zonal_stats, cases$defaults_two_levels_aoi)$warnings)))
  expect_true(any(grepl("below min_coverage", .zeq_run(reference_zonal_stats, cases$defaults_two_levels_aoi)$warnings)))
  expect_match(.zeq_run(reference_zonal_stats, cases$class_share_error)$value, "^ERROR: class_share needs")
  expect_true(any(.zeq_run(reference_zonal_stats, cases$class_share_breaks)$value$stat == "class_pct"))
})

test_that("wapor_zonal_stats() gives the same table whatever the number of layers read at once", {
  skip_if_not_installed("exactextractr")
  fx <- .zeq_fixture()
  cases <- .zeq_cases(fx)[c("defaults_two_levels_aoi", "all_stats_volume_skipped", "mask_and_weights")]
  for (budget_mb in c(0.02, 0.5)) {              # one layer per read, and a few
    withr::with_options(list(Rwapor.memory_budget_mb = budget_mb), {
      for (nm in names(cases)) {
        ref <- .zeq_run(reference_zonal_stats, cases[[nm]])
        new <- .zeq_run(Rwapor::wapor_zonal_stats, cases[[nm]])
        expect_identical(new$value, ref$value, info = paste(nm, budget_mb))
        expect_identical(new$warnings, ref$warnings, info = paste(nm, budget_mb))
      }
    })
  }
})

test_that("format = 'sf' gives every row the geometry of its own zone (ISS-20261005-003)", {
  skip_if_not_installed("exactextractr")
  fx <- .zeq_fixture()
  z <- fx$z[1:4, ]
  out <- suppressWarnings(Rwapor::wapor_zonal_stats(fx$r[[2:3]], z, id = "farm", dissolve = FALSE, aoi = FALSE,
                                                    stats = c("mean", "area_ha"), format = "sf"))
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 4 * 2 * 2)
  expect_false(any(sf::st_is_empty(out)))
  own <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(z)))[match(out$zone_id, toupper(trimws(z$farm))), ]
  got <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(out)))
  expect_equal(unname(got), unname(own))
})

# =============================================================================
# ISS-20261005-004 and -005: lon/lat rasters, and class shares with NoData
# =============================================================================

test_that("wapor_zonal_stats() works on lon/lat rasters without lwgeom, with geodesic zone areas", {
  skip_if_not_installed("exactextractr")
  r <- terra::rast(nrows = 40, ncols = 40, xmin = 35, xmax = 35.4, ymin = 32, ymax = 32.4, crs = "EPSG:4326")
  terra::values(r) <- seq_len(1600) / 100
  names(r) <- "aeti"; terra::units(r) <- "mm"
  ring <- function(x0, y0, dx, dy) sf::st_polygon(list(cbind(x0 + c(0, dx, dx, 0, 0), y0 + c(0, 0, dy, dy, 0))))
  z <- sf::st_sf(farm = c("a", "b"), geometry = sf::st_sfc(ring(35.05, 32.05, 0.1, 0.12), ring(35.2, 32.2, 0.15, 0.1),
                                                           crs = 4326))
  out <- Rwapor::wapor_zonal_stats(r, z, id = "farm", dissolve = FALSE, aoi = FALSE,
                                   stats = c("mean", "area_ha", "coverage", "mask_fraction"))
  area <- out$value[out$stat == "area_ha"]
  expect_equal(area, terra::expanse(terra::vect(z), unit = "ha"), tolerance = 1e-4)
  expect_equal(out$value[out$stat == "coverage"], c(1, 1))
  # Cell areas come from exactextractr (sphere), zone areas from the ellipsoid: equal within 1%.
  expect_equal(out$value[out$stat == "mask_fraction"], c(1, 1), tolerance = 0.01)
  expect_true(all(is.finite(out$value[out$stat == "mean"])))
  # Zone area helper: projected zones are measured as they are.
  utm <- sf::st_transform(z, 32636)
  expect_identical(Rwapor:::.wapor_zone_area_ha(utm, FALSE), as.numeric(sf::st_area(utm)) / 1e4)
  # The s2 setting of the session is left alone.
  before <- sf::sf_use_s2()
  invisible(Rwapor::wapor_zonal_stats(r, z, id = "farm", stats = "mean"))
  expect_identical(sf::sf_use_s2(), before)
})

test_that("class_share with breaks works when zones contain NoData cells", {
  skip_if_not_installed("exactextractr")
  r <- terra::rast(nrows = 10, ncols = 10, xmin = 700000, xmax = 700200, ymin = 3600000, ymax = 3600200,
                   crs = "EPSG:32636")
  v <- rep(c(1, 3, 5, 7), each = 25)        # 25 cells in each of four classes for breaks 2, 4, 6
  v[c(1, 2, 3, 4, 5)] <- NA                 # five NoData cells in the first class
  terra::values(r) <- v
  names(r) <- "x"; terra::units(r) <- "mm"
  z <- sf::st_sf(id = "all", geometry = sf::st_as_sfc(sf::st_bbox(c(xmin = 700000, ymin = 3600000, xmax = 700200,
                                                                   ymax = 3600200), crs = 32636)))
  out <- Rwapor::wapor_zonal_stats(r, z, id = "id", aoi = FALSE, stats = "class_share",
                                   breaks = c(2, 4, 6), labels = c("a", "b", "c", "d"))
  pct <- out[out$stat == "class_pct", ]
  expect_identical(pct$class, c("a", "b", "c", "d"))
  expect_equal(pct$value, 100 * c(20, 25, 25, 25) / 95)
  expect_equal(sum(pct$value), 100)
  no_data <- out$value[out$stat == "class_area_ha" & out$class == "no data"]
  expect_equal(no_data, 5 * 400 / 1e4)       # five 20 m cells
})
