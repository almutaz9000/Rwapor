test_that("full offline seasonal pipeline exports rasters with units and verified SHA-256 provenance sidecar", {
  root <- withr::local_tempdir()
  in_dir <- file.path(root, "inputs")
  out_dir <- file.path(root, "exports")
  dir.create(in_dir, recursive = TRUE)

  make_r <- function(vals) {
    r <- terra::rast(
      nrows = 4, ncols = 4,
      xmin = 30, xmax = 32, ymin = 30, ymax = 32,
      crs = "EPSG:4326"
    )
    terra::values(r) <- vals
    r
  }

  dates <- c("2022-01-01", "2022-01-11", "2022-01-21")
  vars <- list(
    "L1-AETI-D" = c(2.0, 2.5, 3.0),
    "L1-RET-D"  = c(4.0, 4.0, 4.5),
    "L1-PCP-D"  = c(1.0, 2.0, 1.5),
    "L1-NPP-D"  = c(3.5, 4.0, 4.5),
    "L1-T-D"    = c(1.5, 2.0, 2.2)
  )

  for (v in names(vars)) {
    v_dir <- file.path(in_dir, v)
    dir.create(v_dir, recursive = TRUE)
    for (i in seq_along(dates)) {
      base_val <- vars[[v]][[i]]
      vals <- seq(base_val, by = 0.05, length.out = 16)
      p <- file.path(v_dir, sprintf("WAPOR-3.%s.%s.tif", v, dates[[i]]))
      terra::writeRaster(make_r(vals), p, overwrite = TRUE)
    }
  }

  mask_vals <- c(rep(1L, 8), rep(2L, 6), NA_integer_, NA_integer_)
  crop_mask <- make_r(mask_vals)
  season_start <- make_r(rep(1L, 16))
  season_end <- make_r(rep(31L, 16))

  crop_params <- data.frame(
    class_value = c(1L, 2L),
    crop_label = c("Wheat", "Maize"),
    kc_ini = c(0.4, 0.5),
    kc_mid = c(1.15, 1.10),
    kc_end = c(0.6, 0.5),
    l_ini_days = c(10L, 10L),
    l_mid_days = c(10L, 10L),
    l_late_days = c(11L, 11L),
    HI = c(0.40, 0.45),
    MC = c(0.15, 0.12),
    fc = c(0.45, 0.45),
    AOT = c(0.80, 0.85),
    stringsAsFactors = FALSE
  )

  req_indicators <- c(
    "agg_aeti", "agg_ret", "agg_pcp", "agg_peff", "agg_npp", "agg_t",
    "etc", "adequacy_etc", "adequacy_p95", "beneficial_fraction",
    "green_water", "blue_water", "et_rain", "rainfall_surplus",
    "agg_biomass_kg", "agg_biomass_t", "yield_npp", "cwp_bwp",
    "nir", "nbwp", "cv_aeti", "theil_aeti"
  )

  config <- list(
    period = c("2022-01-01", "2022-01-31"),
    ref_year = 2022L,
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    precip_var = "L1-PCP-D",
    npp_var = "L1-NPP-D",
    t_var = "L1-T-D",
    data_source = "local",
    folder = in_dir,
    indicators = req_indicators,
    use_crop_mask = TRUE,
    use_season_rasters = TRUE,
    incremental = FALSE,
    processing = "memory"
  )

  res <- wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = list(
      crop_mask = crop_mask,
      season_start = season_start,
      season_end = season_end
    )
  )

  wapor_export_analysis_outputs(
    results = res,
    folder = out_dir,
    indicators = req_indicators,
    season_label = "S2022"
  )

  season_dir <- file.path(out_dir, "S2022")
  ras_dir <- file.path(season_dir, "seasonal_rasters")
  tab_dir <- file.path(season_dir, "seasonal_tables")

  expected_rasters <- list(
    "S2022_seasonal_aeti.tif"          = "mm",
    "S2022_seasonal_ret.tif"           = "mm",
    "S2022_seasonal_pcp.tif"           = "mm",
    "S2022_seasonal_peff.tif"          = "mm",
    "S2022_seasonal_npp.tif"           = "gC/m2",
    "S2022_seasonal_transpiration.tif" = "mm",
    "S2022_seasonal_etc.tif"           = "mm",
    "S2022_adequacy_etc.tif"           = "1",
    "S2022_adequacy_p95.tif"           = "1",
    "S2022_beneficial_fraction.tif"    = "1",
    "S2022_green_water.tif"            = "mm",
    "S2022_blue_water.tif"             = "mm",
    "S2022_et_rain.tif"                = "mm",
    "S2022_rainfall_surplus.tif"       = "mm",
    "S2022_seasonal_biomass_kg_ha.tif" = "kg/ha",
    "S2022_seasonal_biomass_t_ha.tif"  = "t/ha",
    "S2022_yield_raster_t_ha.tif"      = "t/ha",
    "S2022_cwp.tif"                    = "kg/m3",
    "S2022_bwp.tif"                    = "kg/m3",
    "S2022_seasonal_nir.tif"           = "mm",
    "S2022_nbwp.tif"                   = "kg/m3"
  )

  for (fname in names(expected_rasters)) {
    fpath <- file.path(ras_dir, fname)
    expect_true(file.exists(fpath), info = paste("Missing exported raster:", fname))
    r <- terra::rast(fpath)
    expect_true(terra::same.crs(r, "EPSG:4326"))
    expect_equal(unname(as.vector(terra::ext(r))), c(30, 32, 30, 32))
    expect_equal(terra::nrow(r), 4L)
    expect_equal(terra::ncol(r), 4L)
    expect_equal(terra::units(r), expected_rasters[[fname]], info = paste("Units mismatch for:", fname))
  }

  expect_true(file.exists(file.path(tab_dir, "S2022_cwp_by_class.csv")))
  expect_true(file.exists(file.path(tab_dir, "S2022_summary_metrics.csv")))
  metrics_df <- utils::read.csv(file.path(tab_dir, "S2022_summary_metrics.csv"), stringsAsFactors = FALSE)
  expect_true(all(c("cwp", "bwp", "nbwp", "cv_aeti", "theil_aeti") %in% metrics_df$metric))

  prov_path <- file.path(season_dir, "provenance.json")
  expect_true(file.exists(prov_path))
  prov <- jsonlite::read_json(prov_path)
  expect_equal(prov$schema_version, 1L)
  expect_true(length(prov$files) >= length(expected_rasters))

  for (rel_path in names(prov$files)) {
    entry <- prov$files[[rel_path]]
    full_p <- file.path(season_dir, rel_path)
    expect_true(file.exists(full_p), info = paste("Provenance file missing on disk:", rel_path))
    actual_sha <- digest::digest(file = normalizePath(full_p, winslash = "/", mustWork = TRUE), algo = "sha256")
    expect_identical(entry$sha256, actual_sha, info = paste("SHA-256 mismatch for:", rel_path))
    expect_true(entry$output %in% names(prov$outputs), info = paste("Missing output metadata for:", entry$output))
  }
})
