# Zonal statistics on the real-data known-answer fixture (citrus, 20 x 20 cells of 20 m).
# Expected values are plain means of pixel blocks and the golden values of the fixture.

zka_dir <- function() testthat::test_path("fixtures", "known-answer")

zka_citrus <- function() {
  folder <- tempfile("zka-citrus-"); dir.create(folder)
  for (f in list.files(file.path(zka_dir(), "citrus"), "^WAPOR-3\\..*\\.tif$", full.names = TRUE)) {
    v <- sub("^WAPOR-3\\.(.*)\\.[0-9-]+_[0-9-]+\\.tif$", "\\1", basename(f))
    wapor_unstack_map(f, folder = file.path(folder, v))
  }
  mask <- terra::rast(file.path(zka_dir(), "citrus", "crop_mask.tif")); names(mask) <- "crop_mask"
  config <- list(period = c("2024-03-01", "2025-02-28"), data_source = "local", folder = folder,
                 use_crop_mask = TRUE, area_weighted = TRUE, keep_intermediates = FALSE,
                 indicators = c("agg_aeti", "agg_t", "agg_ret", "agg_pcp", "agg_peff", "etc", "adequacy_etc",
                                "adequacy_p95", "beneficial_fraction", "green_water", "blue_water"),
                 output_dir = tempfile("zka-out-"), processing = "memory",
                 aeti_var = "L3-AETI-D", t_var = "L3-T-D", ret_var = "L1-RET-D", precip_var = "L1-PCP-D")
  cp <- wapor_create_crop_params(class_value = 1L, crop_name = "Citrus", kc_ini = 0.70, kc_mid = 0.65, kc_end = 0.70,
                                 l_ini_days = 60L, l_mid_days = 120L, l_late_days = 95L, max_height_m = 4.0,
                                 region = "Mediterranean")
  suppressWarnings(suppressMessages(wapor_run_seasonal_analysis(config, cp, list(crop_mask = mask))))
}

test_that("zonal statistics on the citrus known-answer result", {
  skip_if_not_installed("exactextractr")
  res <- zka_citrus()
  grid <- res$seasonal_aeti$raster
  e <- unname(as.vector(terra::ext(grid))); mx <- mean(e[1:2]); my <- mean(e[3:4])   # xmin, xmax, ymin, ymax
  box <- function(x1, x2, y1, y2) sf::st_as_sfc(sf::st_bbox(c(xmin = x1, ymin = y1, xmax = x2, ymax = y2),
                                                            crs = sf::st_crs(terra::crs(grid))))
  zones <- sf::st_sf(scheme = c("north", "north", "south", "south"), block = c("q1", "q2", "q3", "q4"),
                     geometry = c(box(e[1], mx, my, e[4]), box(mx, e[2], my, e[4]),
                                  box(e[1], mx, e[3], my), box(mx, e[2], e[3], my)))
  rows <- list(q1 = 1:10, q2 = 1:10, q3 = 11:20, q4 = 11:20)                    # 10 x 10 pixel quadrants
  cols <- list(q1 = 1:10, q2 = 11:20, q3 = 1:10, q4 = 11:20)
  expect_warning(
    ans <- wapor_zonal_stats(res, zones, c("scheme", "block"), stats = c("mean", "count", "sum_volume")),
    "not a depth.*adequacy_etc, adequacy_p95, beneficial_fraction"      # ratios have no volume
  )

  # 1. Quadrant means of every layer = plain means of the 100 cells.
  layers <- unique(ans$variable)
  expect_true(all(c("seasonal_aeti", "seasonal_t", "seasonal_ret", "seasonal_pcp", "seasonal_peff", "etc",
                    "adequacy_etc", "adequacy_p95", "beneficial_fraction", "green_water", "blue_water") %in% layers))
  src <- Rwapor:::.wapor_result_layers(res)$raster
  for (lyr in layers) {
    m <- terra::as.matrix(src[[lyr]], wide = TRUE)
    for (q in names(rows)) {
      got <- ans$value[ans$stat == "mean" & ans$variable == lyr & ans$block %in% q]
      expect_equal(got, mean(m[rows[[q]], cols[[q]]]), tolerance = 1e-9, info = paste(lyr, q))
    }
  }
  expect_true(all(ans$value[ans$stat == "count" & ans$level == 2] == 100))

  # 2. AOI means equal the golden values of the fixture.
  aoi <- ans[ans$level == 0 & ans$stat == "mean", ]
  expect_equal(aoi$value[aoi$variable == "seasonal_aeti"], 446.3228, tolerance = 1e-6)
  expect_equal(aoi$value[aoi$variable == "etc"], 1050.9293, tolerance = 1e-6)

  # 3. AOI volume: mean depth over the 16 ha.
  vol <- ans$value[ans$level == 0 & ans$stat == "sum_volume" & ans$variable == "seasonal_aeti"]
  expect_equal(vol, 446.3228 / 1000 * 160000, tolerance = 1e-6)
  expect_false(any(ans$stat == "sum_volume" & ans$variable == "adequacy_etc"))   # a ratio has no volume

  # 4. Adequacy classes: shares equal independent pixel counts and sum to 100.
  share <- suppressWarnings(wapor_zonal_stats(res, zones, "scheme", layers = "adequacy_etc", stats = "class_share",
                                              scheme = "adequacy"))
  pct <- share[share$level == 0 & share$stat == "class_pct", ]
  v <- terra::values(res$adequacy_etc)[, 1]
  counts <- table(cut(v, c(-Inf, 0.68, 0.80, 1.00, Inf), right = TRUE,
                      labels = c("poor", "acceptable", "good", "above ETc")))
  expect_identical(pct$class, names(counts))
  expect_equal(pct$value, as.numeric(100 * counts / sum(counts)), tolerance = 1e-9)
  expect_equal(sum(pct$value), 100)
  north <- share[share$zone_key == "NORTH" & share$stat == "class_pct", ]
  counts_n <- table(cut(terra::as.matrix(res$adequacy_etc, wide = TRUE)[1:10, ], c(-Inf, 0.68, 0.80, 1.00, Inf), right = TRUE))
  expect_equal(north$value, as.numeric(100 * counts_n / 200), tolerance = 1e-9)
})
