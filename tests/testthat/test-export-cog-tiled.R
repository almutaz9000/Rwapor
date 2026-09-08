# =============================================================================
# Canonical export allow-list, COG writer, tiled windows, reference_layer
# =============================================================================

test_that("canonical export filter drops kc products and columns", {
  expect_true(wapor_canonical_export_is_kc("kc_dekad"))
  expect_true(wapor_canonical_export_is_kc("seasonal_kc"))
  expect_true(wapor_canonical_export_is_kc("Kc_mid"))
  expect_false(wapor_canonical_export_is_kc("seasonal_aeti"))
  expect_false(wapor_canonical_export_is_kc("adequacy_etc"))
  expect_equal(
    wapor_filter_canonical_export_names(c("seasonal_aeti", "kc_ini", "green_water")),
    c("seasonal_aeti", "green_water")
  )

  skip_if_not_installed("terra")
  export_dir <- tempfile("wapor_kc_export_")
  dir.create(export_dir, recursive = TRUE)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE), add = TRUE)

  template <- terra::rast(
    nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2,
    crs = "EPSG:4326", vals = 1:4
  )
  fake <- list(
    seasonal_aeti = list(
      raster = template,
      by_class = data.frame(class_value = 1L, mean = 4, kc_mid = 1.15)
    ),
    dekadal_stacks = list(kc = template, aeti = template)
  )

  expect_warning(
    wapor_export_analysis_outputs(
      results = fake,
      folder = export_dir,
      indicators = "agg_aeti",
      season_label = "Winter2024",
      include_dekadal = TRUE,
      include_monthly = FALSE,
      include_seasonal_tables = TRUE
    ),
    "Kc is internal only"
  )

  written <- list.files(export_dir, recursive = TRUE)
  expect_true(any(grepl("seasonal_aeti", written)))
  expect_true(any(grepl("dekadal_aeti", written)))
  expect_false(any(grepl("(^|[._-])kc([._-]|$)", basename(written), ignore.case = TRUE)))

  csv_path <- file.path(export_dir, "Winter2024", "seasonal_tables", "Winter2024_seasonal_aeti_by_class.csv")
  expect_true(file.exists(csv_path))
  tbl <- utils::read.csv(csv_path)
  expect_false(any(grepl("(^|[._-])kc([._-]|$)", names(tbl), ignore.case = TRUE)))
  expect_true("mean" %in% names(tbl))
})

test_that("wapor_write_cog writes a readable GeoTIFF", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 8, ymin = 0, ymax = 8, crs = "EPSG:4326", vals = 1:64)
  path <- tempfile(fileext = ".tif")
  on.exit(unlink(path, force = TRUE), add = TRUE)
  out <- wapor_write_cog(r, path)
  expect_equal(out, path)
  expect_true(file.exists(path))
  got <- terra::rast(path)
  expect_equal(terra::ncell(got), 64)
  expect_equal(as.numeric(terra::values(got)), 1:64)
})

test_that("tiled row windows cover the grid without overlap", {
  wins <- .wapor_tiled_row_windows(10L, 4L)
  expect_equal(length(wins), 3L)
  expect_equal(vapply(wins, `[[`, integer(1), "row"), c(1L, 5L, 9L))
  expect_equal(sum(vapply(wins, `[[`, integer(1), "nrows")), 10L)
})

test_that("tiled engine windows a grid larger than tile_size", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("rwapor-tiled-")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)
  out_dir <- tempfile("rwapor-tiled-out-")
  dir.create(out_dir, recursive = TRUE)
  on.exit(unlink(out_dir, recursive = TRUE, force = TRUE), add = TRUE)

  dates <- c("2023-01-01", "2023-01-11", "2023-01-21")
  template <- terra::rast(
    nrows = 6, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 6,
    crs = "EPSG:4326", vals = 1
  )
  crop_mask <- terra::setValues(template, 1L)
  season_start <- terra::setValues(template, 1L)
  season_end <- terra::setValues(template, 31L)

  write_stack <- function(variable, layer_values) {
    var_dir <- file.path(analysis_dir, variable)
    dir.create(var_dir, recursive = TRUE)
    for (i in seq_along(dates)) {
      r <- terra::setValues(template, layer_values[i])
      terra::writeRaster(
        r,
        file.path(var_dir, sprintf("WAPOR-3.%s.%s.tif", variable, dates[i])),
        overwrite = TRUE
      )
    }
  }
  write_stack("L1-AETI-D", c(2, 3, 4))
  write_stack("L1-RET-D", c(1, 1, 1))
  write_stack("L1-PCP-D", c(1, 1, 1))

  crop_params <- data.frame(
    class_value = 1L, crop_label = "Wheat",
    kc_ini = 1, kc_mid = 1, kc_end = 1,
    l_ini_days = 10L, l_mid_days = 10L, l_late_days = 11L,
    HI = 1, MC = 0, fc = 1, AOT = 1,
    stringsAsFactors = FALSE
  )
  config <- list(
    period = c("2023-01-01", "2023-01-31"),
    ref_year = 2023,
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    precip_var = "L1-PCP-D",
    npp_var = NULL,
    t_var = NULL,
    data_source = "local",
    folder = analysis_dir,
    indicators = c("agg_aeti", "agg_ret", "agg_pcp", "etc", "adequacy_etc"),
    use_crop_mask = TRUE,
    use_season_rasters = TRUE,
    incremental = FALSE
  )

  full <- wapor_run_seasonal_analysis(
    config = config,
    crop_params = crop_params,
    rasters = list(crop_mask = crop_mask, season_start = season_start, season_end = season_end)
  )
  tiled <- wapor_run_seasonal_analysis_tiled(
    config = config,
    crop_params = crop_params,
    rasters = list(crop_mask = crop_mask, season_start = season_start, season_end = season_end),
    output_dir = out_dir,
    tile_size = 2L
  )

  expect_equal(tiled$n_tiles, 3L)
  expect_true(file.exists(file.path(out_dir, "seasonal_aeti.tif")))
  full_mean <- as.numeric(terra::global(full$seasonal_aeti$raster, "mean", na.rm = TRUE)$mean)
  tile_mean <- as.numeric(terra::global(tiled$results$seasonal_aeti$raster, "mean", na.rm = TRUE)$mean)
  expect_equal(tile_mean, full_mean, tolerance = 1e-6)
})

test_that("reference_layer crop_mask changes template dimensions", {
  skip_if_not_installed("terra")

  analysis_dir <- tempfile("rwapor-ref-")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  dates <- c("2023-01-01", "2023-01-11", "2023-01-21")
  aeti_template <- terra::rast(
    nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4,
    crs = "EPSG:4326", vals = 1
  )
  mask_template <- terra::rast(
    nrows = 2, ncols = 2, xmin = 0, xmax = 4, ymin = 0, ymax = 4,
    crs = "EPSG:4326", vals = 1L
  )
  crop_mask <- terra::setValues(mask_template, 1L)
  season_start <- terra::setValues(mask_template, 1L)
  season_end <- terra::setValues(mask_template, 31L)

  write_stack <- function(variable, layer_values) {
    var_dir <- file.path(analysis_dir, variable)
    dir.create(var_dir, recursive = TRUE)
    for (i in seq_along(dates)) {
      r <- terra::setValues(aeti_template, layer_values[i])
      terra::writeRaster(
        r,
        file.path(var_dir, sprintf("WAPOR-3.%s.%s.tif", variable, dates[i])),
        overwrite = TRUE
      )
    }
  }
  write_stack("L1-AETI-D", c(2, 2, 2))
  write_stack("L1-RET-D", c(1, 1, 1))

  crop_params <- data.frame(
    class_value = 1L, crop_label = "Wheat",
    kc_ini = 1, kc_mid = 1, kc_end = 1,
    l_ini_days = 10L, l_mid_days = 10L, l_late_days = 11L,
    HI = 1, MC = 0, fc = 1, AOT = 1,
    stringsAsFactors = FALSE
  )
  base_config <- list(
    period = c("2023-01-01", "2023-01-31"),
    ref_year = 2023,
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    precip_var = NULL,
    npp_var = NULL,
    t_var = NULL,
    data_source = "local",
    folder = analysis_dir,
    indicators = c("agg_aeti", "etc"),
    use_crop_mask = TRUE,
    use_season_rasters = TRUE,
    incremental = FALSE
  )

  aeti_ref <- wapor_run_seasonal_analysis(
    config = base_config,
    crop_params = crop_params,
    rasters = list(crop_mask = crop_mask, season_start = season_start, season_end = season_end)
  )
  mask_config <- base_config
  mask_config$reference_layer <- "crop_mask"
  mask_ref <- wapor_run_seasonal_analysis(
    config = mask_config,
    crop_params = crop_params,
    rasters = list(crop_mask = crop_mask, season_start = season_start, season_end = season_end)
  )

  expect_equal(terra::nrow(aeti_ref$template_r), 4)
  expect_equal(terra::ncol(aeti_ref$template_r), 4)
  expect_equal(terra::nrow(mask_ref$template_r), 2)
  expect_equal(terra::ncol(mask_ref$template_r), 2)
})
