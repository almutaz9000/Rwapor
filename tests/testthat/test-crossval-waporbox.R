test_that("cross-implementation golden fixture (Rwapor <-> waporbox) matches closed-form reference across memory, stream, and tiled modes", {
  fix_dir <- testthat::test_path("fixtures", "crossval")
  expect_true(dir.exists(fix_dir))

  manifest_path <- file.path(fix_dir, "manifest.json")
  expected_path <- file.path(fix_dir, "expected.json")
  expect_true(file.exists(manifest_path))
  expect_true(file.exists(expected_path))

  manifest <- jsonlite::read_json(manifest_path)
  expected <- jsonlite::read_json(expected_path, simplifyVector = TRUE)

  # 1. Verify SHA-256 integrity of every fixture file in manifest.json
  for (rel_file in names(manifest$files)) {
    f_path <- file.path(fix_dir, rel_file)
    expect_true(file.exists(f_path), info = paste("Missing fixture file:", rel_file))
    actual_sha <- digest::digest(file = f_path, algo = "sha256")
    expect_identical(actual_sha, manifest$files[[rel_file]], info = paste("SHA-256 mismatch:", rel_file))
  }

  # 2. Verify INT2S scaled raster decoding (scale = 0.1, nodata = -9999)
  scaled_r <- terra::rast(file.path(fix_dir, "scaled_int2s_aeti.tif"))
  terra::scoff(scaled_r) <- cbind(0.1, 0)
  detached <- .wapor_detach_source_scale(scaled_r)
  decoded_r <- .wapor_apply_source_scale(detached$raster, detached$scale, detached$offset)
  scaled_vals <- as.numeric(terra::values(decoded_r, mat = FALSE))
  ref_scaled_vals <- as.numeric(expected$scaled_int2s_aeti)
  expect_equal(is.na(scaled_vals), is.na(ref_scaled_vals))
  expect_equal(scaled_vals[!is.na(scaled_vals)], ref_scaled_vals[!is.na(ref_scaled_vals)], tolerance = 1e-5)

  # 3. Verify latitude-aware pixel area (ha) against expected reference
  crop_mask <- terra::rast(file.path(fix_dir, "crop_mask.tif"))
  season_start <- terra::rast(file.path(fix_dir, "season_start.tif"))
  season_end <- terra::rast(file.path(fix_dir, "season_end.tif"))

  area_r <- wapor_pixel_area_ha(crop_mask)
  area_vals <- as.numeric(terra::values(area_r, mat = FALSE))
  expect_equal(area_vals, as.numeric(expected$pixel_area_ha), tolerance = 1e-4)

  # 4. Run wapor_run_seasonal_analysis across memory, stream, and tiled modes
  crop_params <- data.frame(
    class_value = c(1L, 2L, 3L),
    crop_label = c("Wheat", "Maize", "Sorghum"),
    kc_ini = c(0.40, 0.50, 0.35),
    kc_mid = c(1.15, 1.10, 1.05),
    kc_end = c(0.60, 0.50, 0.55),
    l_ini_days = c(15L, 15L, 10L),
    l_mid_days = c(25L, 25L, 20L),
    l_late_days = c(19L, 19L, 11L),
    HI = c(0.40, 0.45, 0.35),
    MC = c(0.15, 0.12, 0.13),
    fc = c(0.45, 0.45, 0.45),
    AOT = c(0.80, 0.85, 0.80),
    stringsAsFactors = FALSE
  )

  req_indicators <- c(
    "agg_aeti", "agg_ret", "agg_pcp", "agg_peff", "agg_npp", "agg_t",
    "etc", "adequacy_etc", "adequacy_p95", "beneficial_fraction",
    "green_water", "blue_water", "et_rain", "rainfall_surplus",
    "agg_biomass_kg", "agg_biomass_t", "yield_npp", "cwp_bwp",
    "nir", "nbwp", "cv_aeti", "theil_aeti"
  )

  expect_raster_matches_ref <- function(r, ref_vec, label, tol = 1e-5) {
    expect_true(inherits(r, "SpatRaster"), info = paste("Not a SpatRaster:", label))
    vals <- as.numeric(terra::values(r, mat = FALSE))
    ref_vec <- as.numeric(ref_vec)
    expect_identical(is.na(vals), is.na(ref_vec), info = paste("NA mask mismatch:", label))
    ok <- !is.na(ref_vec)
    expect_equal(vals[ok], ref_vec[ok], tolerance = tol, info = paste("Value mismatch:", label))
  }

  withr::local_options(list(Rwapor.tile_size = 3L))

  for (mode in c("memory", "stream", "tiled")) {
    out_dir <- withr::local_tempdir()
    cfg <- list(
      period = c("2022-01-01", "2022-02-28"),
      ref_year = 2022L,
      aeti_var = "L1-AETI-D",
      ret_var = "L1-RET-D",
      precip_var = "L1-PCP-D",
      npp_var = "L1-NPP-D",
      t_var = "L1-T-D",
      data_source = "local",
      folder = fix_dir,
      output_dir = out_dir,
      indicators = req_indicators,
      use_crop_mask = TRUE,
      use_season_rasters = TRUE,
      incremental = FALSE,
      processing = mode
    )

    res <- wapor_run_seasonal_analysis(
      config = cfg,
      crop_params = crop_params,
      rasters = list(
        crop_mask = crop_mask,
        season_start = season_start,
        season_end = season_end
      )
    )

    expect_raster_matches_ref(res$seasonal_aeti$raster, expected$rasters$seasonal_aeti, paste(mode, "seasonal_aeti"))
    expect_raster_matches_ref(res$seasonal_ret$raster, expected$rasters$seasonal_ret, paste(mode, "seasonal_ret"))
    expect_raster_matches_ref(res$seasonal_pcp, expected$rasters$seasonal_pcp, paste(mode, "seasonal_pcp"))
    expect_raster_matches_ref(res$seasonal_peff, expected$rasters$seasonal_peff, paste(mode, "seasonal_peff"))
    expect_raster_matches_ref(res$seasonal_npp$raster, expected$rasters$seasonal_npp, paste(mode, "seasonal_npp"))
    expect_raster_matches_ref(res$seasonal_t$raster, expected$rasters$seasonal_t, paste(mode, "seasonal_t"))
    expect_raster_matches_ref(res$seasonal_etc, expected$rasters$seasonal_etc, paste(mode, "seasonal_etc"))
    expect_raster_matches_ref(res$adequacy_etc, expected$rasters$adequacy_etc, paste(mode, "adequacy_etc"))
    expect_raster_matches_ref(res$adequacy_p95, expected$rasters$adequacy_p95, paste(mode, "adequacy_p95"))
    expect_raster_matches_ref(res$beneficial_fraction, expected$rasters$beneficial_fraction, paste(mode, "beneficial_fraction"))
    expect_raster_matches_ref(res$green_water, expected$rasters$green_water, paste(mode, "green_water"))
    expect_raster_matches_ref(res$blue_water, expected$rasters$blue_water, paste(mode, "blue_water"))
    expect_raster_matches_ref(res$et_rain, expected$rasters$et_rain, paste(mode, "et_rain"))
    expect_raster_matches_ref(res$rainfall_surplus, expected$rasters$rainfall_surplus, paste(mode, "rainfall_surplus"))
    expect_raster_matches_ref(res$seasonal_biomass_kg, expected$rasters$seasonal_biomass_kg, paste(mode, "seasonal_biomass_kg"), tol = 1e-4)
    expect_raster_matches_ref(res$seasonal_biomass_t, expected$rasters$seasonal_biomass_t, paste(mode, "seasonal_biomass_t"))
    expect_raster_matches_ref(res$yield_raster, expected$rasters$yield_raster, paste(mode, "yield_raster"))
    expect_raster_matches_ref(res$cwp_raster, expected$rasters$cwp_raster, paste(mode, "cwp_raster"))
    expect_raster_matches_ref(res$bwp_raster, expected$rasters$bwp_raster, paste(mode, "bwp_raster"))
    expect_raster_matches_ref(res$seasonal_nir, expected$rasters$seasonal_nir, paste(mode, "seasonal_nir"))
    expect_raster_matches_ref(res$nbwp_raster, expected$rasters$nbwp_raster, paste(mode, "nbwp_raster"))

    expect_equal(res$cwp, expected$scalars$cwp, tolerance = 1e-4, info = paste(mode, "cwp"))
    expect_equal(res$bwp, expected$scalars$bwp, tolerance = 1e-4, info = paste(mode, "bwp"))
    expect_equal(res$nbwp, expected$scalars$nbwp, tolerance = 1e-4, info = paste(mode, "nbwp"))
    expect_equal(res$cv_aeti$overall, expected$scalars$cv_aeti_overall, tolerance = 1e-5, info = paste(mode, "cv_aeti"))
    expect_equal(res$theil_aeti$overall, expected$scalars$theil_aeti_overall, tolerance = 1e-5, info = paste(mode, "theil_aeti"))
  }
})
