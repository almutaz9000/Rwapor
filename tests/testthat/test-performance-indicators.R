# Independent expected values: Review §5 and master plan WP3 tests 1-12.

.pi_grid <- function(vals = 1:100, res = 20) {
  n <- sqrt(length(vals))
  r <- terra::rast(
    nrows = n, ncols = n,
    xmin = 700000, xmax = 700000 + n * res,
    ymin = 3600000, ymax = 3600000 + n * res,
    crs = "EPSG:32636"
  )
  terra::values(r) <- vals
  r
}

.pi_poly <- function(xmin, xmax, ymin, ymax, id = "z", id_col = "id") {
  g <- sf::st_sfc(sf::st_polygon(list(matrix(
    c(xmin, ymin, xmax, ymin, xmax, ymax, xmin, ymax, xmin, ymin),
    ncol = 2, byrow = TRUE
  ))), crs = 32636)
  d <- data.frame(id = id, stringsAsFactors = FALSE)
  names(d) <- id_col
  sf::st_sf(d, geometry = g)
}

.pi_full <- function(r, id = "all") {
  e <- terra::ext(r)
  .pi_poly(e[1], e[2], e[3], e[4], id = id)
}

test_that("adequacy classes on wheat fixture match independent cut()", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  mask_path <- testthat::test_path("fixtures", "known-answer", "wheat", "crop_mask.tif")
  skip_if_not(file.exists(mask_path))
  folder <- tempfile("ka-wheat-")
  dir.create(folder)
  src <- testthat::test_path("fixtures", "known-answer", "wheat")
  for (f in list.files(src, "^WAPOR-3\\..*\\.tif$", full.names = TRUE)) {
    v <- sub("^WAPOR-3\\.(.*)\\.[0-9-]+_[0-9-]+\\.tif$", "\\1", basename(f))
    wapor_unstack_map(f, folder = file.path(folder, v))
  }
  mask <- terra::rast(mask_path)
  names(mask) <- "crop_mask"
  cp <- wapor_custom_crop(
    base_crop = "Winter Wheat", class_value = 1L,
    crop_name = "Irrigated Winter Wheat", kc_ini = 0.35, kc_mid = 1.15, kc_end = 0.30,
    HI = 0.43, AOT = 0.75, fc = 1.0, MC = 0.15
  )
  config <- list(
    period = c("2023-11-01", "2024-05-31"), data_source = "local", folder = folder,
    use_crop_mask = TRUE, area_weighted = TRUE, keep_intermediates = FALSE,
    indicators = c("agg_aeti", "agg_ret", "etc", "adequacy_etc"),
    aeti_var = "L3-AETI-D", ret_var = "L1-RET-D",
    output_dir = tempfile("ka-out-"), processing = "memory"
  )
  res <- suppressWarnings(suppressMessages(
    wapor_run_seasonal_analysis(config, cp, list(crop_mask = mask))
  ))
  vals <- terra::values(res$adequacy_etc)[, 1]
  vals <- vals[is.finite(vals)]
  expected <- table(cut(vals, c(-Inf, 0.68, 0.8, 1, Inf), right = TRUE, include.lowest = TRUE))
  got <- wapor_classify_adequacy(res$adequacy_etc)
  got_vals <- terra::values(got)[, 1]
  got_vals <- got_vals[is.finite(got_vals)]
  got_tab <- table(factor(got_vals, levels = seq_along(expected)))
  expect_equal(as.integer(got_tab), as.integer(expected))
})

test_that("RWD is 1 - AETI/ETx and percentile ETx is type 7", {
  skip_if_not_installed("terra")
  rwd <- wapor_calc_rwd(400, etx = 500, etx_method = "etc")
  expect_equal(as.numeric(rwd$rwd), 0.20)
  expect_equal(as.numeric(rwd$deficit_mm), 100)
  x <- 1:100
  rwd_p <- wapor_calc_rwd(x, etx_method = "percentile", p = 0.99)
  expect_equal(as.numeric(rwd_p$etx), unname(stats::quantile(1:100, 0.99, type = 7)))
  expect_equal(as.numeric(rwd_p$etx), 99.01)
})

test_that("uniformity 1..100 and per-method classes", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  r <- .pi_grid(1:100, res = 20)
  names(r) <- "aeti"
  z <- .pi_full(r, "u")
  u <- wapor_calc_uniformity(r, z, id = "id", irrigation_method = "unknown")
  expect_lt(abs(u$uniformity_cv - 0.42840), 1e-5)
  expect_lt(abs(u$cu - 0.504950), 1e-6)
  expect_lt(abs(u$du_lq - 0.257426), 1e-6)
  expect_true(is.null(u$class) || all(is.na(u$class)))

  r2 <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 400, ymin = 0, ymax = 200,
                    crs = "EPSG:32636", vals = c(7, 13))
  names(r2) <- "aeti"
  z2 <- .pi_poly(0, 400, 0, 200, id = "f")
  z2 <- sf::st_set_crs(z2, 32636)
  surf <- suppressWarnings(wapor_calc_uniformity(r2, z2, id = "id", irrigation_method = "surface",
                                min_area_ha = 0))
  expect_equal(surf$uniformity_cv, 0.70, tolerance = 1e-10)
  expect_identical(as.character(surf$class), "meets standard")
  spr <- suppressWarnings(wapor_calc_uniformity(r2, z2, id = "id", irrigation_method = "sprinkler",
                               min_area_ha = 0))
  expect_identical(as.character(spr$class), "below standard")
})

test_that("min_area_ha: a 0.5 ha unit is NA at the default 1 ha", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 200, ymin = 0, ymax = 200,
                   crs = "EPSG:32636", vals = 1:100)
  names(r) <- "aeti"
  z <- .pi_poly(0, 100, 0, 50, id = "small")
  z <- sf::st_set_crs(z, 32636)
  expect_equal(as.numeric(sf::st_area(z)) / 1e4, 0.5, tolerance = 1e-9)
  u <- wapor_calc_uniformity(r, z, id = "id", irrigation_method = "unknown")
  expect_true(is.na(u$uniformity_cv))
})

test_that("equity of unit means 10, 12, 14", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  r <- terra::rast(nrows = 1, ncols = 3, xmin = 0, xmax = 300, ymin = 0, ymax = 100,
                   crs = "EPSG:32636", vals = c(10, 12, 14))
  names(r) <- "aeti"
  z <- rbind(
    .pi_poly(0, 100, 0, 100, "a"),
    .pi_poly(100, 200, 0, 100, "b"),
    .pi_poly(200, 300, 0, 100, "c")
  )
  z <- sf::st_set_crs(z, 32636)
  eq_pop <- wapor_calc_equity(r, z, id = "id", sd_type = "population", min_area_ha = 0)
  expect_equal(round(eq_pop$cv, 5), 0.13608)
  expect_identical(as.character(eq_pop$class), "fair")
  eq_samp <- wapor_calc_equity(r, z, id = "id", sd_type = "sample", min_area_ha = 0)
  expect_equal(round(eq_samp$cv, 5), 0.16667)
  expect_identical(as.character(eq_samp$class), "fair")
})

test_that("reliability is temporal CV of relative ET", {
  skip_if_not_installed("terra")
  r0 <- terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 20, ymin = 0, ymax = 20,
                    crs = "EPSG:32636", vals = 1)
  stack1 <- c(r0, r0, r0)
  names(stack1) <- paste0("m", 1:3)
  rel1 <- wapor_calc_reliability(stack1)
  expect_equal(as.numeric(terra::values(rel1)), 0)

  stack2 <- c(r0 * 0.5, r0 * 1.0, r0 * 1.5)
  names(stack2) <- paste0("m", 1:3)
  rel2 <- wapor_calc_reliability(stack2)
  expect_equal(as.numeric(terra::values(rel2)), 0.40825, tolerance = 1e-5)
})

test_that("climate norm factor and application rule", {
  skip_if_not_installed("terra")
  r_const <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 40, ymin = 0, ymax = 20,
                         crs = "EPSG:32636", vals = c(5, 5))
  fn_const <- wapor_calc_climate_norm(r_const, weights = "none")
  expect_equal(as.numeric(terra::values(fn_const)), c(1, 1))

  r <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 40, ymin = 0, ymax = 20,
                   crs = "EPSG:32636", vals = c(2, 4))
  fn <- wapor_calc_climate_norm(r, weights = "none")
  expect_equal(as.numeric(terra::values(fn)), c(1.5, 0.75))
  expect_equal(as.numeric(wapor_apply_climate_norm(100, 1.5, type = "depth")), 150)
  expect_equal(as.numeric(wapor_apply_climate_norm(1.2, 1.5, type = "productivity")), 0.8)
})

test_that("productivity gap uses type-7 P95", {
  skip_if_not_installed("terra")
  r <- terra::rast(
    nrows = 10, ncols = 10, xmin = 0, xmax = 1000, ymin = 0, ymax = 1000,
    crs = "EPSG:32636"
  )
  terra::values(r) <- 1:100
  names(r) <- "yield"
  g <- wapor_calc_productivity_gap(r, p = 0.95)
  expect_equal(g$target, unname(stats::quantile(1:100, 0.95, type = 7)))
  expect_equal(g$target, 95.05)
  vals <- terra::values(g$gap)[, 1]
  expect_equal(vals[90], 5.05)
  expect_equal(vals[100], 0)
  expect_equal(g$production_gap, 4469.75, tolerance = 1e-6)
})

test_that("spots: bright and dark use >= and <=", {
  skip_if_not_installed("terra")
  lp <- .pi_grid(1:100, res = 20)
  wp <- .pi_grid(1:100, res = 20)
  names(lp) <- "lp"
  names(wp) <- "wp"
  sp <- suppressWarnings(wapor_classify_spots(lp, wp))
  codes <- terra::values(sp)[, 1]
  labs <- terra::levels(sp)[[1]]
  lab <- labs$class[match(codes, labs$value)]
  expect_equal(sum(lab == "bright", na.rm = TRUE), 5L)
  expect_equal(sum(lab == "dark", na.rm = TRUE), 5L)
  expect_true(all(which(lab == "bright") %in% 96:100))
  expect_true(all(which(lab == "dark") %in% 1:5))

  wp_rev <- .pi_grid(100:1, res = 20)
  sp0 <- suppressWarnings(wapor_classify_spots(lp, wp_rev))
  codes0 <- terra::values(sp0)[, 1]
  lab0 <- terra::levels(sp0)[[1]]$class[match(codes0, terra::levels(sp0)[[1]]$value)]
  expect_equal(sum(lab0 == "bright", na.rm = TRUE), 0L)
  expect_equal(sum(lab0 == "dark", na.rm = TRUE), 0L)

  x <- c(1:19, 20)
  sp_eq <- wapor_classify_spots(x, x, breaks = c(5, 20))
  expect_identical(as.character(sp_eq[20]), "bright")
})

test_that("spots per reference group and zone mode; class_share sums to 100", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  lp <- terra::rast(nrows = 1, ncols = 200, xmin = 0, xmax = 200, ymin = 0, ymax = 1,
                    crs = "EPSG:32636")
  terra::values(lp) <- c(1:100, 1:100)
  wp <- lp
  names(lp) <- "lp"
  names(wp) <- "wp"
  ref <- terra::rast(lp)
  terra::values(ref) <- c(rep(1L, 100), rep(2L, 100))
  sp <- suppressWarnings(wapor_classify_spots(lp, wp, reference = ref))
  codes <- terra::values(sp)[, 1]
  labs <- terra::levels(sp)[[1]]
  lab <- labs$class[match(codes, labs$value)]
  expect_equal(sum(lab[1:100] == "bright", na.rm = TRUE), 5L)
  expect_equal(sum(lab[101:200] == "bright", na.rm = TRUE), 5L)

  r <- .pi_grid(1:100, res = 20)
  z <- rbind(
    .pi_poly(700000, 700100, 3600000, 3600200, "left"),
    .pi_poly(700100, 700200, 3600000, 3600200, "right")
  )
  zone_sp <- wapor_classify_spots(r, r, zones = z, zone_id = "id")
  expect_equal(nrow(zone_sp), 2L)
  expect_true("class" %in% names(zone_sp) || "spot" %in% names(zone_sp))

  pix <- suppressWarnings(wapor_classify_spots(r, r))
  share <- wapor_zonal_stats(pix, z, id = "id", stats = "class_share", aoi = FALSE, min_coverage = 0)
  pct <- tapply(share$value[share$stat == "class_pct" & share$class != "no data"],
                share$zone_key[share$stat == "class_pct" & share$class != "no data"], sum)
  expect_equal(unname(as.numeric(pct)), c(100, 100), tolerance = 1e-6)
})

test_that("NIR is the monthly sum of max(0, ETc - Peff)", {
  skip_if_not_installed("terra")
  expect_equal(as.numeric(wapor_calc_nir(c(100, 80), c(30, 90))), 70)
  etc <- c(
    terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 20, ymin = 0, ymax = 20,
                crs = "EPSG:32636", vals = 100),
    terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 20, ymin = 0, ymax = 20,
                crs = "EPSG:32636", vals = 80)
  )
  peff <- c(
    terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 20, ymin = 0, ymax = 20,
                crs = "EPSG:32636", vals = 30),
    terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 20, ymin = 0, ymax = 20,
                crs = "EPSG:32636", vals = 90)
  )
  names(etc) <- c("m1", "m2")
  names(peff) <- c("m1", "m2")
  nir <- wapor_calc_nir(etc, peff)
  expect_equal(as.numeric(terra::values(nir)), 70)
})

test_that("wapor_calc_cv, wapor_calc_peff and wapor_calc_theil are exported", {
  ns <- getNamespaceExports("Rwapor")
  expect_true("wapor_calc_cv" %in% ns)
  expect_true("wapor_calc_peff" %in% ns)
  expect_true("wapor_calc_theil" %in% ns)
  expect_true(!is.null(utils::help("wapor_calc_cv", package = "Rwapor")) ||
                file.exists(system.file("help", "wapor_calc_cv", package = "Rwapor")) ||
                exists("wapor_calc_cv"))
})
