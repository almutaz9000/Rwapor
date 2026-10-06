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

# The reference predates the B2 completion: it has no id columns, no
# sum_volume_mcm, used the key for zone_id and wrote "|NA" for missing child ids.
# Both tables are brought to the reference's shape before they are compared.
.zeq_old_cols <- c("level", "zone_id", "zone_key", "season", "variable", "period", "stat", "class", "value", "unit")
.zeq_shape <- function(x, new) {
  if (!is.data.frame(x)) return(x)
  class(x) <- "data.frame"
  attr(x, "wapor_zonal_call") <- NULL; attr(x, "wapor_classes") <- NULL
  if (new) {
    x <- x[x$stat != "sum_volume_mcm", .zeq_old_cols, drop = FALSE]
    x$zone_id <- x$zone_key
  } else {
    x$zone_key <- x$zone_id <- gsub("(\\|NA)+$", "", x$zone_key)
  }
  rownames(x) <- NULL
  x
}
.zeq_old_warnings <- function(w) gsub("(\\|NA)+", "", w)

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
  for (nm in setdiff(names(cases), "wide")) {      # the wide layout changed on purpose; tested below
    ref <- .zeq_run(reference_zonal_stats, cases[[nm]])
    new <- .zeq_run(Rwapor::wapor_zonal_stats, cases[[nm]])
    expect_identical(.zeq_shape(new$value, TRUE), .zeq_shape(ref$value, FALSE), info = nm)
    expect_identical(new$warnings, .zeq_old_warnings(ref$warnings), info = nm)
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
        expect_identical(.zeq_shape(new$value, TRUE), .zeq_shape(ref$value, FALSE), info = paste(nm, budget_mb))
        expect_identical(new$warnings, .zeq_old_warnings(ref$warnings), info = paste(nm, budget_mb))
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
  expect_equal(nrow(out), 4 * 2)                  # one row per zone and layer, statistics as columns
  expect_true(all(c("mean", "area_ha") %in% names(out)))
  expect_false(any(sf::st_is_empty(out)))
  own <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(z)))[match(out$zone_key, toupper(trimws(z$farm))), ]
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
  # Cell areas and zone areas are both on the ellipsoid, so a fully covered zone has share 1.
  expect_equal(out$value[out$stat == "mask_fraction"], c(1, 1), tolerance = 1e-4)
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

# =============================================================================
# B2 completion (taken over 2026-10-06): the specification's remaining test
# groups and features. Expected values are worked out by hand from the 10 x 10
# grid of 20 m cells holding 1..100 row by row from the top.
# =============================================================================

.zm <- matrix(1:100, 10, 10, byrow = TRUE)        # .zm[row from top, column from left]
.zbox <- function(c1, c2, r1, r2, ...) {          # zone covering columns c1..c2 and rows r1..r2
  .zpoly(700000 + (c1 - 1) * 20, 700000 + c2 * 20, 3600200 - r2 * 20, 3600200 - (r1 - 1) * 20, ...)
}

test_that("half a cell: one cell, half its area, effective count 0.5", {
  z <- .zpoly(700000, 700010, 3600180, 3600200)
  ans <- wapor_zonal_stats(.zgrid(), z, "id", stats = c("mean", "count", "n_eff", "area_ha", "sum_volume"),
                           aoi = FALSE, min_coverage = 0)
  expect_equal(.zstat(ans, "mean"), 1)
  expect_equal(.zstat(ans, "count"), 1)
  expect_equal(.zstat(ans, "n_eff"), 0.5)
  expect_equal(.zstat(ans, "area_ha"), 0.02)
  expect_equal(.zstat(ans, "sum_volume"), 1 / 1000 * 200)         # 1 mm over 200 m2
  expect_equal(.zstat(ans, "sum_volume_mcm"), 1 / 1000 * 200 / 1e6)
})

test_that("crop share and data coverage are separate and exact", {
  r <- .zgrid()
  mask <- r; terra::values(mask) <- NA; terra::values(mask)[1:20] <- 1
  terra::values(r)[16:20] <- NA
  ans <- wapor_zonal_stats(r, .zbox(1, 10, 1, 10), "id", stats = c("mask_fraction", "coverage", "mean", "count"),
                           mask = mask, aoi = FALSE)
  expect_equal(.zstat(ans, "mask_fraction"), 0.20)                 # 20 of 100 cells are crop
  expect_equal(.zstat(ans, "coverage"), 0.75)                      # 15 of those 20 have data
  expect_equal(.zstat(ans, "mean"), mean(1:15))
  expect_equal(.zstat(ans, "count"), 15)
})

test_that("volumes use depths, or rates with days given as a vector or by layer name", {
  r <- terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 100, ymin = 0, ymax = 100, crs = "EPSG:32636", vals = 2)
  names(r) <- "d1"; terra::units(r) <- "mm/day"
  z <- sf::st_set_crs(.zpoly(0, 100, 0, 100), 32636)
  vol <- function(...) {
    a <- wapor_zonal_stats(r, z, "id", stats = "sum_volume", aoi = FALSE, ...)
    a$value[a$stat == "sum_volume"]
  }
  expect_equal(vol(days = 8), 160)                                 # 2 mm/day x 8 days over 1 ha
  expect_equal(vol(days = data.frame(layer = c("other", "d1"), days = c(99, 8))), 160)
  expect_warning(none <- vol(days = data.frame(layer = "other", days = 99)), "without days: d1")
  expect_length(none, 0)
  expect_error(wapor_zonal_stats(r, z, "id", stats = "sum_volume", days = data.frame(a = 1)), "'layer' and 'days'")
  # Day counts of WaPOR dekads, against plain date arithmetic.
  dekad_days <- function(tag) wapor_date_info(sprintf("https://x/WAPOR-3.L1-AETI-D.%s.tif", tag), "D")$number_of_days
  expect_equal(dekad_days("2023-02-D3"), as.integer(as.Date("2023-03-01") - as.Date("2023-02-21")))   # 8
  expect_equal(dekad_days("2024-02-D3"), as.integer(as.Date("2024-03-01") - as.Date("2024-02-21")))   # 9
  expect_equal(dekad_days("2023-01-D3"), as.integer(as.Date("2023-02-01") - as.Date("2023-01-21")))   # 11
})

test_that("nested levels are computed from their own geometry and carry their id columns", {
  farms <- rbind(.zbox(1, 5, 1, 5, "A1"), .zbox(1, 5, 6, 10, "A2"), .zbox(6, 10, 1, 5, "B1"), .zbox(6, 8, 6, 10, "B2"))
  names(farms)[names(farms) == "id"] <- "farm"
  farms$scheme <- c("A", "A", "B", "B")
  ans <- wapor_zonal_stats(.zgrid(), farms, c("scheme", "farm"), stats = c("mean", "count", "sum_volume"))
  expect_identical(names(ans), c("level", "zone_id", "zone_key", "scheme", "farm", "season", "variable", "period",
                                 "stat", "class", "value", "unit"))
  b_cells <- c(.zm[1:5, 6:10], .zm[6:10, 6:8])                     # 25 + 15 cells
  expect_equal(.zstat(ans, "mean", "B"), mean(b_cells))
  expect_false(isTRUE(all.equal(mean(b_cells), mean(c(mean(.zm[1:5, 6:10]), mean(.zm[6:10, 6:8])))))) # not the mean of means
  expect_equal(.zstat(ans, "count", "B"), 40)
  expect_equal(.zstat(ans, "sum_volume", "B"),
               .zstat(ans, "sum_volume", "B|B1") + .zstat(ans, "sum_volume", "B|B2"), tolerance = 1e-9)
  expect_equal(.zstat(ans, "mean", "AOI"), mean(c(.zm[, 1:5], b_cells)))
  one <- function(key) ans[ans$zone_key == key & ans$stat == "mean", ]
  expect_identical(c(one("AOI")$level, one("B")$level, one("B|B2")$level), c(0L, 1L, 2L))
  expect_identical(c(one("B")$scheme, one("B")$farm), c("B", NA_character_))
  expect_identical(c(one("B|B2")$scheme, one("B|B2")$farm, one("B|B2")$zone_id), c("B", "B2", "B|B2"))
  expect_identical(one("AOI")$zone_id, "AOI")
})

test_that("polygons with the same id are dissolved; the AOI is the union of overlapping zones", {
  two <- rbind(.zbox(1, 5, 1, 5, "z"), .zbox(6, 10, 6, 10, "z"))
  ans <- wapor_zonal_stats(.zgrid(), two, "id", stats = c("count", "mean"), aoi = FALSE)
  expect_equal(.zstat(ans, "count"), 50)
  expect_equal(.zstat(ans, "mean"), mean(c(.zm[1:5, 1:5], .zm[6:10, 6:10])))
  over <- rbind(.zbox(1, 6, 1, 10, "a"), .zbox(5, 10, 1, 10, "b"))   # columns 5 and 6 belong to both
  aoi <- wapor_zonal_stats(.zgrid(), over, "id", stats = c("area_ha", "count"))
  expect_equal(.zstat(aoi, "area_ha", "AOI"), 4)                    # 200 m x 200 m, not 2.4 + 2.4
  expect_equal(.zstat(aoi, "count", "AOI"), 100)
  expect_equal(.zstat(aoi, "area_ha", "A"), 2.4)
})

test_that("zones below min_coverage get NA statistics and are named in one warning", {
  r <- .zgrid(); terra::values(r)[1:60] <- NA
  z <- .zbox(1, 10, 1, 10, "field")
  expect_warning(low <- wapor_zonal_stats(r, z, "id", stats = c("mean", "coverage", "count"), aoi = FALSE),
                 "zones below min_coverage: FIELD")
  expect_equal(.zstat(low, "coverage"), 0.4)
  expect_true(is.na(.zstat(low, "mean")))
  expect_equal(.zstat(low, "count"), 40)                            # still reported
  ok <- wapor_zonal_stats(r, z, "id", stats = "mean", aoi = FALSE, min_coverage = 0.3)
  expect_equal(.zstat(ok, "mean"), mean(61:100))
})

test_that("weighted quantiles and the median equal type 7 for equal weights", {
  set.seed(11); x <- stats::rnorm(57)
  for (p in c(0.05, 0.5, 0.95)) {
    expect_equal(Rwapor:::.wapor_wquantile(x, rep(1, 57), p), unname(stats::quantile(x, p, type = 7)), tolerance = 1e-12)
  }
  ans <- wapor_zonal_stats(.zgrid(), .zbox(1, 10, 1, 10), "id", stats = c("median", "quantiles"), aoi = FALSE,
                           probs = c(0.1, 0.9))
  expect_equal(.zstat(ans, "median"), 50.5)
  expect_equal(.zstat(ans, "quantile_0.1"), unname(stats::quantile(1:100, 0.1, type = 7)))
  expect_equal(.zstat(ans, "quantile_0.9"), unname(stats::quantile(1:100, 0.9, type = 7)))
  expect_identical(ans$unit, rep("mm", 3))
})

test_that("class shares equal independent counts, list empty classes, and report the area without data", {
  r <- .zgrid(); terra::values(r)[c(1, 2, 3, 99, 100)] <- NA        # 3 cells of class a and 2 of class d without data
  ans <- wapor_zonal_stats(r, .zbox(1, 10, 1, 10), "id", stats = "class_share", aoi = FALSE,
                           breaks = c(25, 50, 75, 200), labels = c("a", "b", "c", "d", "e"))
  pct <- ans[ans$stat == "class_pct", ]
  expect_identical(pct$class, c("a", "b", "c", "d", "e"))
  expect_equal(pct$value, 100 * c(22, 25, 25, 23, 0) / 95)          # (0,25], (25,50], (50,75], (75,200], above
  area <- ans[ans$stat == "class_area_ha", ]
  expect_equal(area$value[area$class == "e"], 0)
  expect_equal(area$value[area$class == "no data"], 5 * 0.04)
  expect_identical(attr(ans, "wapor_classes")$labels, c("a", "b", "c", "d", "e"))
  # Without labels every class of the breaks is still listed, by number.
  plain <- wapor_zonal_stats(.zgrid(), .zbox(1, 10, 1, 10), "id", stats = "class_share", aoi = FALSE,
                             breaks = c(25, 50, 75, 200))
  expect_identical(plain$class[plain$stat == "class_pct"], as.character(1:5))
})

test_that("a classified raster given as 'classes' is reported with all its categories", {
  cls <- .zgrid(); terra::values(cls) <- rep(c(1L, 2L), each = 50)
  levels(cls) <- data.frame(value = 1:3, class = c("crop", "fallow", "orchard"))
  names(cls) <- "landuse"                           # after levels<-, which renames the layer
  ans <- wapor_zonal_stats(.zgrid(), .zbox(1, 10, 1, 4), "id", stats = c("mean", "class_share"), classes = cls,
                           aoi = FALSE)
  share <- ans[ans$stat == "class_pct", ]
  expect_identical(share$variable, rep("landuse", 3))
  expect_identical(share$class, c("crop", "fallow", "orchard"))
  expect_equal(share$value, c(100, 0, 0))                           # rows 1 to 4 are all class 1
  expect_equal(.zstat(ans, "mean"), mean(.zm[1:4, ]))               # value statistics are unaffected
  expect_error(wapor_zonal_stats(.zgrid(), .zbox(1, 10, 1, 4), "id", classes = c(cls, cls)), "single-layer")
})

test_that("lon/lat cell weights match geodesic cell areas", {
  r <- terra::rast(nrows = 40, ncols = 40, xmin = 35, xmax = 35.4, ymin = 32, ymax = 32.4, crs = "EPSG:4326", vals = 1000)
  names(r) <- "depth"; terra::units(r) <- "mm"
  z <- sf::st_sf(id = "z", geometry = sf::st_as_sfc(sf::st_bbox(c(xmin = 35.1, ymin = 32.1, xmax = 35.2, ymax = 32.2),
                                                                crs = 4326)))
  ans <- wapor_zonal_stats(r, z, "id", stats = c("sum_volume", "count"), aoi = FALSE)
  cells <- terra::crop(terra::cellSize(r, unit = "m"), terra::ext(35.1, 35.2, 32.1, 32.2))
  expect_equal(.zstat(ans, "count"), terra::ncell(cells))
  expect_equal(.zstat(ans, "sum_volume"), sum(terra::values(cells)), tolerance = 1e-4)   # 1000 mm = 1 m3 per m2
  # The cell-area formula against geodesic cell areas over the whole latitude range of WaPOR.
  g <- terra::rast(nrows = 120, ncols = 1, xmin = 0, xmax = 0.25, ymin = -60, ymax = 60, crs = "EPSG:4326")
  expect_equal(Rwapor:::.wapor_lonlat_cell_area(terra::yFromRow(g, 1:120), 0.25, 1),
               terra::values(terra::cellSize(g, unit = "m"))[, 1], tolerance = 1e-5)
})

test_that("wide and sf formats, call settings, and argument errors", {
  farms <- rbind(.zbox(1, 5, 1, 10, "west"), .zbox(6, 10, 1, 10, "east"))
  r <- c(.zgrid(), .zgrid() * 2); names(r) <- c("a", "b")
  long <- wapor_zonal_stats(r, farms, "id", stats = c("mean", "count", "class_share"), breaks = 50, labels = c("low", "high"))
  wide <- wapor_zonal_wide(long)
  expect_identical(names(wide)[1:6], c("level", "zone_id", "zone_key", "id", "season", "variable"))
  expect_true(all(c("mean", "count", "class_pct.low", "class_pct.high", "class_area_ha.no data") %in% names(wide)))
  expect_equal(nrow(wide), 3 * 2)                                   # west, east, AOI x two layers
  expect_equal(wide$mean[wide$zone_key == "WEST" & wide$variable == "b"], 2 * mean(.zm[, 1:5]))
  expect_identical(wapor_zonal_stats(r, farms, "id", stats = c("mean", "count", "class_share"), breaks = 50,
                                     labels = c("low", "high"), format = "wide"), wide)
  shp <- wapor_zonal_stats(r, farms, "id", stats = "mean", format = "sf")
  expect_s3_class(shp, "sf")
  expect_equal(nrow(shp), 3 * 2)
  expect_equal(as.numeric(sf::st_area(shp[shp$zone_key == "AOI", ][1, ])), 200 * 200)
  call <- attr(long, "wapor_zonal_call")
  expect_identical(call[c("sd_type", "id", "mask", "weights")], list(sd_type = "population", id = "id", mask = FALSE, weights = FALSE))
  expect_match(call$area_method, "planar")
  expect_error(wapor_zonal_stats(r, stats::setNames(farms, c("level", "geometry")), "level"), "cannot be named: level")
  expect_error(wapor_zonal_stats(list(1, 2), farms, "id"), "no raster outputs")
  away <- sf::st_set_crs(.zpoly(800000, 800100, 3600000, 3600100, "away"), 32636)
  expect_warning(none <- wapor_zonal_stats(r, away, "id", aoi = FALSE), "no overlap")
  expect_equal(nrow(none), 0)
  ratio <- .zgrid(); terra::units(ratio) <- ""
  expect_warning(wapor_zonal_stats(ratio, farms, "id", stats = "sum_volume", aoi = FALSE), "not a depth")
})
