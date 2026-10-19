test_that("multi-L3 selection requires an explicit policy", {
  expect_error(
    wapor_resolve_l3_selection(c("AAA", "BBB")),
    "multiple L3 regions"
  )

  expect_equal(
    wapor_resolve_l3_selection(c("AAA", "BBB"), l3_region = "BBB"),
    "BBB"
  )

  expect_equal(
    wapor_resolve_l3_selection(c("AAA", "BBB"), l3_mode = "mosaic_all"),
    c("AAA", "BBB")
  )
})

test_that("wapor_run_seasonal_analysis enforces L3 policy and records mosaic_all coverage", {
  skip_if_not_installed("terra")

  tmp_dir <- tempfile("rwapor-l3-season-")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE, force = TRUE), add = TRUE)

  dates <- c("2023-01-01", "2023-01-11", "2023-01-21")
  left <- terra::rast(nrows = 2, ncols = 2, xmin = 30, xmax = 31, ymin = 30, ymax = 32,
                      crs = "EPSG:4326", vals = 20)
  right <- terra::rast(nrows = 2, ncols = 2, xmin = 31, xmax = 32, ymin = 30, ymax = 32,
                       crs = "EPSG:4326", vals = 30)

  aaa_paths <- character(length(dates))
  bbb_paths <- character(length(dates))
  for (i in seq_along(dates)) {
    aaa_paths[i] <- file.path(tmp_dir, sprintf("WAPOR-3.L3-AETI-D.AAA.%s.tif", dates[i]))
    bbb_paths[i] <- file.path(tmp_dir, sprintf("WAPOR-3.L3-AETI-D.BBB.%s.tif", dates[i]))
    terra::writeRaster(left, aaa_paths[i], overwrite = TRUE)
    terra::writeRaster(right, bbb_paths[i], overwrite = TRUE)
  }

  local_mocked_bindings(
    wapor_guess_region = function(variable, reg_info, period, ...) c("AAA", "BBB"),
    wapor_generate_urls = function(variable, l3_region = NULL, period = NULL, ...) {
      if (identical(l3_region, "AAA")) return(aaa_paths)
      if (identical(l3_region, "BBB")) return(bbb_paths)
      c(aaa_paths, bbb_paths)
    },
    .wapor_resolve_remote_sources = function(urls, ...) as.list(urls),
    .package = "Rwapor"
  )

  crop_params <- data.frame(
    class_value = 1L, crop_label = "Wheat",
    kc_ini = 1, kc_mid = 1, kc_end = 1,
    l_ini_days = 10L, l_mid_days = 10L, l_late_days = 11L,
    HI = 0.45, MC = 0.12, fc = 1, AOT = 0.8,
    stringsAsFactors = FALSE
  )

  # 1. Two intersecting L3 regions with no selection -> error listing both region IDs
  cfg_no_sel <- list(
    period = c("2023-01-01", "2023-01-31"),
    ref_year = 2023,
    aeti_var = "L3-AETI-D",
    data_source = "api",
    indicators = "agg_aeti",
    use_crop_mask = FALSE,
    use_season_rasters = FALSE
  )
  expect_error(
    wapor_run_seasonal_analysis(cfg_no_sel, crop_params, list(), aoi_region = c(30, 30, 32, 32)),
    "AAA.*BBB"
  )

  # 2. Explicit single L3 region -> succeeds on selected region
  cfg_one <- cfg_no_sel
  cfg_one$l3_code <- "AAA"
  res_one <- wapor_run_seasonal_analysis(cfg_one, crop_params, list(), aoi_region = c(30, 30, 31, 32))
  expect_true(inherits(res_one$seasonal_aeti$raster, "SpatRaster"))

  # 3. mosaic_all -> succeeds and records per-region coverage_fraction in provenance
  cfg_mos <- cfg_no_sel
  cfg_mos$l3_mode <- "mosaic_all"
  res_mos <- wapor_run_seasonal_analysis(cfg_mos, crop_params, list(), aoi_region = c(30, 30, 32, 32))
  expect_true(inherits(res_mos$seasonal_aeti$raster, "SpatRaster"))
  expect_equal(res_mos$provenance$l3_coverage[["L3-AETI-D"]]$l3_codes, c("AAA", "BBB"))
  expect_equal(
    unname(res_mos$provenance$l3_coverage[["L3-AETI-D"]]$coverage_fraction[c("AAA", "BBB")]),
    c(0.5, 0.5),
    tolerance = 1e-6
  )
})
