# =============================================================================
# Tests for Shiny analysis helpers
# =============================================================================

test_that("wapor_parse_batch_periods parses valid batch input", {
  parsed <- Rwapor:::wapor_parse_batch_periods(
    paste(
      "Winter 2023, 2023-10-01, 2024-05-31",
      "Winter 2024, 2024-10-01, 2025-05-31",
      sep = "\n"
    )
  )

  expect_equal(names(parsed$periods), c("Winter 2023", "Winter 2024"))
  expect_equal(parsed$periods[["Winter 2023"]], c("2023-10-01", "2024-05-31"))
  expect_equal(parsed$season_table$label, c("Winter 2023", "Winter 2024"))
})

test_that("wapor_parse_batch_periods rejects malformed input", {
  expect_error(
    Rwapor:::wapor_parse_batch_periods("Winter 2023, 2023-10-01"),
    "Invalid batch line 1"
  )
  expect_error(
    Rwapor:::wapor_parse_batch_periods("Winter 2023, bad-date, 2024-05-31"),
    "Invalid date on batch line 1"
  )
  expect_error(
    Rwapor:::wapor_parse_batch_periods(
      paste(
        "Winter 2023, 2023-10-01, 2024-05-31",
        "Winter 2023, 2024-10-01, 2025-05-31",
        sep = "\n"
      )
    ),
    "Batch labels must be unique"
  )
})

test_that("wapor_generate_shiny_script emits parseable single-season and batch scripts", {
  crop_params <- data.frame(
    class_value = 1L,
    crop_label = "Wheat",
    kc_ini = 0.3,
    kc_mid = 1.15,
    kc_end = 0.25,
    l_ini_days = 30L,
    l_mid_days = 40L,
    l_late_days = 30L,
    HI = 0.45,
    MC = 0.12,
    fc = 1,
    AOT = 0.8,
    stringsAsFactors = FALSE
  )

  single_script <- Rwapor:::wapor_generate_shiny_script(
    config = list(
      period = c("2023-10-01", "2024-05-31"),
      ref_year = 2023,
      aeti_var = "L1-AETI-D",
      ret_var = "L1-RET-D",
      precip_var = "L1-PCP-D",
      npp_var = "L1-NPP-D",
      t_var = "",
      data_source = "local",
      folder = "C:/wapor/project",
      indicators = c("agg_aeti", "etc"),
      use_crop_mask = TRUE,
      use_season_rasters = TRUE,
      season_label = "Winter 2023",
      aoi_region = c(30, 10, 31, 11)
    ),
    crop_params = crop_params
  )

  batch_script <- Rwapor:::wapor_generate_shiny_script(
    config = list(
      period = list(
        "Winter 2023" = c("2023-10-01", "2024-05-31"),
        "Winter 2024" = c("2024-10-01", "2025-05-31")
      ),
      ref_year = NULL,
      aeti_var = "L1-AETI-D",
      ret_var = "L1-RET-D",
      precip_var = "L1-PCP-D",
      npp_var = "L1-NPP-D",
      t_var = "",
      data_source = "local",
      folder = "C:/wapor/project",
      indicators = c("agg_aeti", "etc"),
      use_crop_mask = FALSE,
      use_season_rasters = FALSE,
      season_label = "ignored",
      aoi_region = c(30, 10, 31, 11)
    ),
    crop_params = crop_params
  )

  expect_match(single_script, "period <- c\\(")
  expect_match(single_script, "season_label <- \"Winter 2023\"")
  expect_false(grepl("periods <- list\\(", single_script, fixed = FALSE))
  expect_match(single_script, "wapor_run_seasonal_analysis\\(")
  expect_silent(parse(text = single_script))

  expect_match(batch_script, "periods <- list\\(")
  expect_match(batch_script, "`Winter 2023` = c\\(")
  expect_match(batch_script, "season_label <- NULL")
  expect_match(batch_script, "wapor_run_seasonal_analysis\\(")
  expect_match(single_script, "indicators <- c\\(")
  expect_match(batch_script, "indicators <- c\\(")
  expect_silent(parse(text = batch_script))
})

test_that("wapor_generate_shiny_script batch script with seasons.json parses cleanly", {
  tmp <- tempfile("wapor_seasons_json_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  season_list <- list(
    list(label = "Winter 2023", start = "2023-10-01", end = "2024-05-31"),
    list(label = "Winter 2024", start = "2024-10-01", end = "2025-05-31")
  )
  jsonlite::write_json(season_list, file.path(tmp, "seasons.json"), pretty = TRUE, auto_unbox = TRUE)

  crop_params <- data.frame(
    class_value = 1L, crop_label = "Wheat",
    kc_ini = 0.3, kc_mid = 1.15, kc_end = 0.25,
    l_ini_days = 30L, l_mid_days = 40L, l_late_days = 30L,
    HI = 0.45, MC = 0.12, fc = 1, AOT = 0.8,
    stringsAsFactors = FALSE
  )

  script <- Rwapor:::wapor_generate_shiny_script(
    config = list(
      period = list(
        "Winter 2023" = c("2023-10-01", "2024-05-31"),
        "Winter 2024" = c("2024-10-01", "2025-05-31")
      ),
      ref_year = NULL,
      aeti_var = "L1-AETI-D",
      ret_var = "L1-RET-D",
      precip_var = "L1-PCP-D",
      npp_var = "L1-NPP-D",
      t_var = "",
      data_source = "local",
      folder = tmp,
      indicators = c("agg_aeti", "etc"),
      use_crop_mask = FALSE,
      use_season_rasters = FALSE,
      aoi_region = c(30, 10, 31, 11)
    ),
    crop_params = crop_params
  )

  expect_match(script, "indicators <- c\\(")
  expect_false(grepl("^`Winter", script, perl = TRUE))
  expect_silent(parse(text = script))
})

test_that("wapor_generate_shiny_script escapes Windows paths safely", {
  crop_params <- data.frame(
    class_value = 1L,
    crop_label = "Wheat",
    kc_ini = 0.3,
    kc_mid = 1.15,
    kc_end = 0.25,
    l_ini_days = 30L,
    l_mid_days = 40L,
    l_late_days = 30L,
    stringsAsFactors = FALSE
  )

  script_text <- Rwapor:::wapor_generate_shiny_script(
    config = list(
      period = c("2023-10-01", "2024-05-31"),
      ref_year = 2023,
      aeti_var = "L1-AETI-D",
      ret_var = "L1-RET-D",
      precip_var = "L1-PCP-D",
      npp_var = "L1-NPP-D",
      t_var = "",
      data_source = "local",
      folder = "C:\\Users\\Mohammedal\\OneDrive - Food and Agriculture Organization\\Documents\\GitHub\\Rwapor\\analysis_output",
      indicators = c("agg_aeti", "etc"),
      use_crop_mask = FALSE,
      use_season_rasters = FALSE,
      season_label = "Winter 2023"
    ),
    crop_params = crop_params
  )

  expect_match(script_text, "C:\\\\\\\\Users\\\\\\\\Mohammedal")
  expect_silent(parse(text = script_text))
})

test_that("wapor_detect_folder_seasons finds labeled and unlabeled seasonal windows", {
  project_dir <- tempfile("wapor_season_detect_")
  dir.create(project_dir, recursive = TRUE)
  dir.create(file.path(project_dir, "L1-AETI-D_seasonal"))
  dir.create(file.path(project_dir, "L1-RET-D_seasonal"))

  file.create(file.path(
    project_dir, "L1-AETI-D_seasonal",
    "WAPOR-3.L1-AETI-D.seasonal.Winter2023.2023-10-01_2024-05-31.tif"
  ))
  file.create(file.path(
    project_dir, "L1-RET-D_seasonal",
    "WAPOR-3.L1-RET-D.seasonal.2024-10-01_2025-05-31.tif"
  ))

  detected <- Rwapor:::wapor_detect_folder_seasons(project_dir)

  expect_equal(sort(detected$seasonal_dirs), c("L1-AETI-D_seasonal", "L1-RET-D_seasonal"))
  expect_equal(
    sort(detected$windows),
    sort(c(
      "Winter2023, 2023-10-01, 2024-05-31",
      "Season_2024-10-01_2025-05-31, 2024-10-01, 2025-05-31"
    ))
  )
})

test_that("wapor_run_seasonal_analysis handles named list periods", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("wapor_batch_")
  dir.create(analysis_dir, recursive = TRUE)
  dir.create(file.path(analysis_dir, "L1-AETI-D"), recursive = TRUE)

  template <- terra::rast(
    nrows = 2, ncols = 2, xmin = 0, xmax = 2,
    ymin = 0, ymax = 2, crs = "EPSG:4326", vals = 1
  )
  crop_mask <- template
  terra::values(crop_mask) <- 1L
  season_start <- template
  terra::values(season_start) <- 1L
  season_end <- template
  terra::values(season_end) <- 31L

  write_aeti <- function(date_string, value) {
    r <- template
    terra::values(r) <- value
    path <- file.path(analysis_dir, "L1-AETI-D", paste0("L1-AETI-D.", date_string, ".tif"))
    terra::writeRaster(r, path, overwrite = TRUE)
  }

  for (date_string in c("2023-01-01", "2023-01-11", "2023-01-21")) {
    write_aeti(date_string, 2)
  }
  for (date_string in c("2024-01-01", "2024-01-11", "2024-01-21")) {
    write_aeti(date_string, 3)
  }

  crop_params <- data.frame(
    class_value = 1L,
    crop_label = "Test",
    kc_ini = 1,
    kc_mid = 1,
    kc_end = 1,
    l_ini_days = 10L,
    l_mid_days = 10L,
    l_late_days = 10L,
    HI = 0.45,
    MC = 0.12,
    fc = 1,
    AOT = 0.8,
    stringsAsFactors = FALSE
  )

  config_single_batch <- list(
    period = list(Winter2023 = c("2023-01-01", "2023-01-31")),
    ref_year = NULL,
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    precip_var = "L1-PCP-D",
    npp_var = "L1-NPP-D",
    t_var = "",
    data_source = "local",
    folder = analysis_dir,
    indicators = "agg_aeti",
    use_crop_mask = TRUE,
    use_season_rasters = TRUE,
    incremental = FALSE
  )

  res_single_batch <- Rwapor::wapor_run_seasonal_analysis(
    config = config_single_batch,
    crop_params = crop_params,
    rasters = list(
      crop_mask = crop_mask,
      season_start = season_start,
      season_end = season_end
    )
  )

  expect_true(is.list(res_single_batch))
  expect_true("Winter2023" %in% names(res_single_batch))
  expect_true(!is.null(res_single_batch$Winter2023$seasonal_aeti$raster))

  config_multi_batch <- config_single_batch
  config_multi_batch$period <- list(
    Winter2023 = c("2023-01-01", "2023-01-31"),
    Winter2024 = c("2024-01-01", "2024-01-31")
  )

  res_multi_batch <- Rwapor::wapor_run_seasonal_analysis(
    config = config_multi_batch,
    crop_params = crop_params,
    rasters = list(
      crop_mask = crop_mask,
      season_start = season_start,
      season_end = season_end
    )
  )

  expect_equal(sort(names(res_multi_batch)), c("Winter2023", "Winter2024"))
  expect_true(!is.null(res_multi_batch$Winter2024$seasonal_aeti$raster))
})

test_that("wapor_run_seasonal_analysis batch mode with agg_peff uses terra::subset correctly", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("wapor_batch_peff_")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  template <- terra::rast(
    nrows = 4, ncols = 4, xmin = 0, xmax = 4,
    ymin = 0, ymax = 4, crs = "EPSG:4326", vals = 1
  )
  crop_mask    <- terra::setValues(template, c(rep(1L, 8), rep(2L, 8)))
  season_start <- terra::setValues(template, rep(1L, terra::ncell(template)))
  season_end   <- terra::setValues(template, rep(31L, terra::ncell(template)))

  write_var <- function(variable, date_strings, value) {
    var_dir <- file.path(analysis_dir, variable)
    dir.create(var_dir, recursive = TRUE, showWarnings = FALSE)
    for (d in date_strings) {
      r <- terra::setValues(template, value)
      terra::writeRaster(
        r, file.path(var_dir, paste0(variable, ".", d, ".tif")), overwrite = TRUE
      )
    }
  }

  dates_2023 <- c("2023-01-01", "2023-01-11", "2023-01-21")
  dates_2024 <- c("2024-01-01", "2024-01-11", "2024-01-21")
  write_var("L1-AETI-D", c(dates_2023, dates_2024), 3)
  write_var("L1-PCP-D",  c(dates_2023, dates_2024), 1)

  crop_params <- data.frame(
    class_value = c(1L, 2L), crop_label = c("A", "B"),
    kc_ini = c(1, 1), kc_mid = c(1, 1), kc_end = c(1, 1),
    l_ini_days = c(10L, 10L), l_mid_days = c(10L, 10L), l_late_days = c(10L, 10L),
    HI = c(0.45, 0.45), MC = c(0.12, 0.12), fc = c(1, 1), AOT = c(0.8, 0.8),
    stringsAsFactors = FALSE
  )

  config <- list(
    period = list(
      Winter2023 = c("2023-01-01", "2023-01-31"),
      Winter2024 = c("2024-01-01", "2024-01-31")
    ),
    ref_year    = NULL,
    aeti_var    = "L1-AETI-D",
    ret_var     = "L1-RET-D",
    precip_var  = "L1-PCP-D",
    npp_var     = "L1-NPP-D",
    t_var       = "",
    data_source = "local",
    folder      = analysis_dir,
    indicators  = c("agg_aeti", "agg_peff"),
    use_crop_mask     = TRUE,
    use_season_rasters = TRUE,
    incremental = FALSE
  )

  result <- Rwapor::wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = list(crop_mask = crop_mask, season_start = season_start, season_end = season_end)
  )

  expect_equal(sort(names(result)), c("Winter2023", "Winter2024"))
  expect_true(inherits(result$Winter2023$seasonal_aeti$raster, "SpatRaster"))
  expect_true(inherits(result$Winter2024$seasonal_aeti$raster, "SpatRaster"))
  expect_true(inherits(result$Winter2023$seasonal_peff, "SpatRaster"))
  expect_true(inherits(result$Winter2024$seasonal_peff, "SpatRaster"))
  expect_false(all(is.na(terra::values(result$Winter2023$seasonal_peff))))
  expect_false(all(is.na(terra::values(result$Winter2024$seasonal_peff))))

  # Both seasons should have the same peff (same PCP=1mm/day input)
  peff_2023 <- as.numeric(terra::global(result$Winter2023$seasonal_peff, "mean", na.rm = TRUE)$mean)
  peff_2024 <- as.numeric(terra::global(result$Winter2024$seasonal_peff, "mean", na.rm = TRUE)$mean)
  expect_equal(peff_2023, peff_2024, tolerance = 1e-4)
  expect_true(peff_2023 > 0 && peff_2023 < 31)  # peff <= total_pcp = 31mm
})

test_that("wapor_run_seasonal_analysis batch mode with full indicator set and crop mask completes", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("wapor_batch_full_")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  template <- terra::rast(
    nrows = 4, ncols = 4, xmin = 0, xmax = 4,
    ymin = 0, ymax = 4, crs = "EPSG:4326", vals = 1
  )
  crop_mask    <- terra::setValues(template, rep(1L, terra::ncell(template)))
  season_start <- terra::setValues(template, rep(1L, terra::ncell(template)))
  season_end   <- terra::setValues(template, rep(31L, terra::ncell(template)))

  write_var <- function(variable, date_strings, value) {
    var_dir <- file.path(analysis_dir, variable)
    dir.create(var_dir, recursive = TRUE, showWarnings = FALSE)
    for (d in date_strings) {
      r <- terra::setValues(template, value)
      terra::writeRaster(
        r, file.path(var_dir, paste0(variable, ".", d, ".tif")), overwrite = TRUE
      )
    }
  }

  dates_2023 <- c("2023-01-01", "2023-01-11", "2023-01-21")
  dates_2024 <- c("2024-01-01", "2024-01-11", "2024-01-21")
  all_dates  <- c(dates_2023, dates_2024)
  write_var("L1-AETI-D", all_dates, 3)
  write_var("L1-RET-D",  all_dates, 2)
  write_var("L1-PCP-D",  all_dates, 1)
  write_var("L1-NPP-D",  all_dates, 5)
  write_var("L1-T-D",    all_dates, 1)

  crop_params <- data.frame(
    class_value = 1L, crop_label = "Wheat",
    kc_ini = 1, kc_mid = 1, kc_end = 1,
    l_ini_days = 10L, l_mid_days = 10L, l_late_days = 10L,
    HI = 0.45, MC = 0.12, fc = 1, AOT = 0.8,
    stringsAsFactors = FALSE
  )

  config <- list(
    period = list(
      Winter2023 = c("2023-01-01", "2023-01-31"),
      Winter2024 = c("2024-01-01", "2024-01-31")
    ),
    ref_year    = NULL,
    aeti_var    = "L1-AETI-D",
    ret_var     = "L1-RET-D",
    precip_var  = "L1-PCP-D",
    npp_var     = "L1-NPP-D",
    t_var       = "L1-T-D",
    data_source = "local",
    folder      = analysis_dir,
    indicators  = c(
      "agg_aeti", "agg_ret", "agg_pcp", "agg_peff", "etc",
      "adequacy_etc", "adequacy_p95", "agg_t", "beneficial_fraction",
      "agg_biomass_kg", "agg_biomass_t", "yield_npp",
      "green_water", "blue_water", "cwp_bwp"
    ),
    use_crop_mask      = TRUE,
    use_season_rasters = TRUE,
    incremental        = FALSE
  )

  result <- Rwapor::wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = list(crop_mask = crop_mask, season_start = season_start, season_end = season_end)
  )

  expect_equal(sort(names(result)), c("Winter2023", "Winter2024"))

  for (nm in c("Winter2023", "Winter2024")) {
    s <- result[[nm]]
    expect_true(inherits(s$seasonal_aeti$raster,  "SpatRaster"), info = paste(nm, "aeti"))
    expect_true(inherits(s$seasonal_ret$raster,   "SpatRaster"), info = paste(nm, "ret"))
    expect_true(inherits(s$seasonal_peff,          "SpatRaster"), info = paste(nm, "peff"))
    expect_true(inherits(s$seasonal_t$raster,      "SpatRaster"), info = paste(nm, "t"))
    expect_true(inherits(s$beneficial_fraction,    "SpatRaster"), info = paste(nm, "bf"))
    expect_true(inherits(s$green_water,            "SpatRaster"), info = paste(nm, "gw"))
    expect_true(inherits(s$blue_water,             "SpatRaster"), info = paste(nm, "bw"))
    expect_true(!is.null(s$cwp),                                  info = paste(nm, "cwp"))
    expect_true(!is.null(s$bwp),                                  info = paste(nm, "bwp"))
    expect_false(all(is.na(terra::values(s$seasonal_peff))),      info = paste(nm, "peff non-NA"))
  }

  # AETI values: 3 mm/day * (10+10+11) days = 93 mm per season
  raster_mean <- function(x) as.numeric(terra::global(x, "mean", na.rm = TRUE)$mean)
  expect_equal(raster_mean(result$Winter2023$seasonal_aeti$raster), 93, tolerance = 1e-4)
  expect_equal(raster_mean(result$Winter2024$seasonal_aeti$raster), 93, tolerance = 1e-4)
})

test_that("analysis indicator normalization keeps peff scripts compatible", {
  expect_equal(
    wapor_normalize_analysis_indicators(c("agg_aeti", "peff", "green_water", "peff")),
    c("agg_aeti", "agg_peff", "green_water")
  )
})

test_that("beneficial_fraction works without explicitly selecting agg_t", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("wapor_beneficial_fraction_")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  template <- terra::rast(
    nrows = 4, ncols = 4, xmin = 0, xmax = 4,
    ymin = 0, ymax = 4, crs = "EPSG:4326", vals = 1
  )
  crop_mask <- terra::setValues(template, rep(1L, terra::ncell(template)))

  write_var <- function(variable, date_strings, value) {
    var_dir <- file.path(analysis_dir, variable)
    dir.create(var_dir, recursive = TRUE, showWarnings = FALSE)
    for (d in date_strings) {
      r <- terra::setValues(template, value)
      terra::writeRaster(
        r, file.path(var_dir, paste0(variable, ".", d, ".tif")), overwrite = TRUE
      )
    }
  }

  dates <- c("2024-04-11", "2024-04-21", "2024-05-01")
  write_var("L1-AETI-D", dates, 4)
  write_var("L1-T-D", dates, 2)

  crop_params <- data.frame(
    class_value = 1L,
    crop_label = "Wheat",
    kc_ini = 1, kc_mid = 1, kc_end = 1,
    l_ini_days = 10L, l_mid_days = 10L, l_late_days = 10L,
    HI = 0.45, MC = 0.12, fc = 1, AOT = 0.8,
    stringsAsFactors = FALSE
  )

  config <- list(
    period = list(Winter2024 = c("2024-04-11", "2024-05-10")),
    ref_year = NULL,
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    precip_var = "L1-PCP-D",
    npp_var = "L1-NPP-D",
    t_var = "L1-T-D",
    data_source = "local",
    folder = analysis_dir,
    indicators = "beneficial_fraction",
    use_crop_mask = TRUE,
    use_season_rasters = FALSE,
    incremental = FALSE
  )

  result <- Rwapor::wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = list(crop_mask = crop_mask, season_start = NULL, season_end = NULL)
  )

  expect_true(inherits(result$Winter2024$beneficial_fraction, "SpatRaster"))
  bf_mean <- as.numeric(terra::global(result$Winter2024$beneficial_fraction, "mean", na.rm = TRUE)$mean)
  expect_equal(bf_mean, 0.5, tolerance = 1e-6)
})

test_that("wapor_export_analysis_outputs writes structured seasonal, dekadal, and monthly outputs", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("wapor_export_outputs_")
  export_dir <- tempfile("wapor_export_dir_")
  dir.create(analysis_dir, recursive = TRUE)
  dir.create(export_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE), add = TRUE)

  template <- terra::rast(
    nrows = 4, ncols = 4, xmin = 0, xmax = 4,
    ymin = 0, ymax = 4, crs = "EPSG:4326", vals = 1
  )
  crop_mask <- terra::setValues(template, rep(1L, terra::ncell(template)))

  write_var <- function(variable, date_strings, value) {
    var_dir <- file.path(analysis_dir, variable)
    dir.create(var_dir, recursive = TRUE, showWarnings = FALSE)
    for (d in date_strings) {
      r <- terra::setValues(template, value)
      terra::writeRaster(
        r, file.path(var_dir, paste0(variable, ".", d, ".tif")), overwrite = TRUE
      )
    }
  }

  dates <- c("2024-01-01", "2024-01-11", "2024-01-21")
  write_var("L1-AETI-D", dates, 3)
  write_var("L1-RET-D", dates, 2)
  write_var("L1-PCP-D", dates, 1)
  write_var("L1-NPP-D", dates, 5)
  write_var("L1-T-D", dates, 1)

  crop_params <- data.frame(
    class_value = 1L, crop_label = "Wheat",
    kc_ini = 1, kc_mid = 1, kc_end = 1,
    l_ini_days = 10L, l_mid_days = 10L, l_late_days = 10L,
    HI = 0.45, MC = 0.12, fc = 1, AOT = 0.8,
    stringsAsFactors = FALSE
  )

  config <- list(
    period = list(Winter2024 = c("2024-01-01", "2024-01-31")),
    ref_year = NULL,
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    precip_var = "L1-PCP-D",
    npp_var = "L1-NPP-D",
    t_var = "L1-T-D",
    data_source = "local",
    folder = analysis_dir,
    indicators = c(
      "agg_aeti", "agg_ret", "agg_pcp", "agg_peff", "agg_t",
      "agg_biomass_t", "yield_npp", "beneficial_fraction", "etc",
      "green_water", "blue_water", "cwp_bwp", "adequacy_p95"
    ),
    use_crop_mask = TRUE,
    use_season_rasters = FALSE,
    incremental = FALSE
  )

  result <- Rwapor::wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = list(crop_mask = crop_mask, season_start = NULL, season_end = NULL)
  )

  Rwapor::wapor_export_analysis_outputs(
    results = result,
    folder = export_dir,
    indicators = config$indicators
  )

  season_dir <- file.path(export_dir, "Winter2024")
  expect_true(dir.exists(file.path(season_dir, "seasonal_rasters")))
  expect_true(dir.exists(file.path(season_dir, "seasonal_tables")))
  expect_true(dir.exists(file.path(season_dir, "dekadal_stacks")))
  expect_true(dir.exists(file.path(season_dir, "monthly_summaries")))
  expect_true(dir.exists(file.path(season_dir, "monthly_rasters")))

  expect_true(file.exists(file.path(season_dir, "seasonal_rasters", "Winter2024_seasonal_aeti.tif")))
  expect_true(file.exists(file.path(season_dir, "seasonal_rasters", "Winter2024_seasonal_peff.tif")))
  expect_true(file.exists(file.path(season_dir, "dekadal_stacks", "Winter2024_dekadal_aeti.tif")))
  expect_true(file.exists(file.path(season_dir, "monthly_summaries", "Winter2024_monthly_pcp_peff.csv")))
  expect_true(file.exists(file.path(season_dir, "monthly_summaries", "Winter2024_monthly_aeti.csv")))
  expect_true(file.exists(file.path(season_dir, "monthly_summaries", "Winter2024_monthly_etc.csv")))
  expect_true(file.exists(file.path(season_dir, "monthly_rasters", "monthly_aeti", "Winter2024_monthly_aeti_2024_01.tif")))
  expect_true(file.exists(file.path(season_dir, "monthly_rasters", "monthly_peff", "Winter2024_monthly_peff_2024_01.tif")))
  expect_true(file.exists(file.path(season_dir, "monthly_rasters", "monthly_etc", "Winter2024_monthly_etc_2024_01.tif")))
  expect_true(file.exists(file.path(season_dir, "monthly_rasters", "monthly_green_water", "Winter2024_monthly_green_water_2024_01.tif")))
  expect_true(file.exists(file.path(season_dir, "monthly_rasters", "monthly_blue_water", "Winter2024_monthly_blue_water_2024_01.tif")))
  expect_true(file.exists(file.path(season_dir, "seasonal_tables", "Winter2024_summary_metrics.csv")))
  expect_true(file.exists(file.path(season_dir, "seasonal_tables", "Winter2024_seasonal_aeti_by_class.csv")))
})
