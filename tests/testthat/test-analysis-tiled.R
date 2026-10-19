# =============================================================================
# Tiled seasonal engine: windows, run manifest, resume, VRT, COG
# =============================================================================

local_tiled_fixture <- function() {
  analysis_dir <- tempfile("rwapor-tiled-src-")
  dir.create(analysis_dir, recursive = TRUE)
  out_dir <- tempfile("rwapor-tiled-out-")
  dir.create(out_dir, recursive = TRUE)

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

  list(
    analysis_dir = analysis_dir,
    out_dir = out_dir,
    crop_mask = crop_mask,
    season_start = season_start,
    season_end = season_end,
    crop_params = crop_params,
    config = config,
    rasters = list(
      crop_mask = crop_mask,
      season_start = season_start,
      season_end = season_end
    )
  )
}

test_that("square tile windows cover the grid without overlap or gaps", {
  wins <- .wapor_tiled_windows(6L, 4L, 2L)
  expect_equal(length(wins), 6L)
  expect_equal(vapply(wins, `[[`, integer(1), "row"), c(1L, 1L, 3L, 3L, 5L, 5L))
  expect_equal(vapply(wins, `[[`, integer(1), "col"), c(1L, 3L, 1L, 3L, 1L, 3L))
  expect_equal(sum(vapply(wins, function(w) w$nrows * w$ncols, integer(1))), 24L)
  expect_equal(unique(vapply(wins, `[[`, character(1), "id")), vapply(wins, `[[`, character(1), "id"))
})

test_that("tiled engine writes a versioned run manifest and per-tile assets", {
  skip_if_not_installed("terra")
  fx <- local_tiled_fixture()
  on.exit(unlink(c(fx$analysis_dir, fx$out_dir), recursive = TRUE, force = TRUE), add = TRUE)

  tiled <- wapor_run_seasonal_analysis_tiled(
    config = fx$config,
    crop_params = fx$crop_params,
    rasters = fx$rasters,
    output_dir = fx$out_dir,
    tile_size = 2L,
    cog = TRUE
  )

  expect_equal(tiled$n_tiles, 6L)
  expect_true(file.exists(tiled$manifest_path))
  man <- jsonlite::fromJSON(tiled$manifest_path, simplifyVector = FALSE)
  expect_equal(man$manifest_version, 1L)
  expect_equal(length(man$tiles), 6L)
  expect_true(nzchar(man$grid$crs))
  expect_equal(man$grid$nrow, 6L)
  expect_equal(man$grid$ncol, 4L)
  expect_true(nzchar(man$config_hash))
  expect_true(!is.null(man$versions$package))
  expect_equal(man$coverage$n_complete, 6L)
  expect_true(isTRUE(man$coverage$complete))

  tile_files <- vapply(man$tiles, function(t) t$outputs$seasonal_aeti, character(1))
  expect_true(all(file.exists(tile_files)))
  expect_true(all(nzchar(vapply(man$tiles, function(t) t$checksums$seasonal_aeti, character(1)))))

  expect_true(file.exists(tiled$saved_files$seasonal_aeti))
  expect_true(file.exists(tiled$saved_files$seasonal_aeti_vrt))
  expect_equal(tiled$n_tiles_resumed, 0L)
})

test_that("tiled engine matches the full engine on the same grid", {
  skip_if_not_installed("terra")
  fx <- local_tiled_fixture()
  on.exit(unlink(c(fx$analysis_dir, fx$out_dir), recursive = TRUE, force = TRUE), add = TRUE)

  full <- wapor_run_seasonal_analysis(
    config = fx$config,
    crop_params = fx$crop_params,
    rasters = fx$rasters
  )
  tiled <- wapor_run_seasonal_analysis_tiled(
    config = fx$config,
    crop_params = fx$crop_params,
    rasters = fx$rasters,
    output_dir = fx$out_dir,
    tile_size = 2L
  )

  full_mean <- as.numeric(terra::global(full$seasonal_aeti$raster, "mean", na.rm = TRUE)$mean)
  tile_mean <- as.numeric(terra::global(tiled$results$seasonal_aeti$raster, "mean", na.rm = TRUE)$mean)
  expect_equal(tile_mean, full_mean, tolerance = 1e-6)
  expect_true(terra::compareGeom(
    tiled$results$seasonal_aeti$raster,
    full$seasonal_aeti$raster,
    stopOnError = FALSE
  ))
})

test_that("tiled engine resumes completed tiles and retries only missing ones", {
  skip_if_not_installed("terra")
  fx <- local_tiled_fixture()
  on.exit(unlink(c(fx$analysis_dir, fx$out_dir), recursive = TRUE, force = TRUE), add = TRUE)

  first <- wapor_run_seasonal_analysis_tiled(
    config = fx$config,
    crop_params = fx$crop_params,
    rasters = fx$rasters,
    output_dir = fx$out_dir,
    tile_size = 2L
  )
  man1 <- jsonlite::fromJSON(first$manifest_path, simplifyVector = FALSE)
  keep_path <- man1$tiles[[1]]$outputs$seasonal_aeti
  missing_path <- man1$tiles[[2]]$outputs$seasonal_aeti
  keep_mtime <- file.info(keep_path)$mtime
  keep_checksum <- man1$tiles[[1]]$checksums$seasonal_aeti
  unlink(missing_path, force = TRUE)
  expect_false(file.exists(missing_path))

  second <- wapor_run_seasonal_analysis_tiled(
    config = fx$config,
    crop_params = fx$crop_params,
    rasters = fx$rasters,
    output_dir = fx$out_dir,
    tile_size = 2L,
    resume = TRUE
  )
  expect_true(file.exists(missing_path))
  expect_equal(file.info(keep_path)$mtime, keep_mtime)
  expect_gte(second$n_tiles_resumed, 1L)
  expect_equal(second$n_tiles_written, 1L)
  man2 <- jsonlite::fromJSON(second$manifest_path, simplifyVector = FALSE)
  expect_equal(man2$tiles[[1]]$checksums$seasonal_aeti, keep_checksum)
  expect_true(isTRUE(man2$coverage$complete))
})

test_that("tiled engine rejects a mismatched resume manifest", {
  skip_if_not_installed("terra")
  fx <- local_tiled_fixture()
  on.exit(unlink(c(fx$analysis_dir, fx$out_dir), recursive = TRUE, force = TRUE), add = TRUE)

  wapor_run_seasonal_analysis_tiled(
    config = fx$config,
    crop_params = fx$crop_params,
    rasters = fx$rasters,
    output_dir = fx$out_dir,
    tile_size = 2L
  )
  other <- fx$config
  other$min_coverage <- 0.5
  expect_error(
    wapor_run_seasonal_analysis_tiled(
      config = other,
      crop_params = fx$crop_params,
      rasters = fx$rasters,
      output_dir = fx$out_dir,
      tile_size = 2L,
      resume = TRUE
    ),
    "manifest"
  )
})

test_that("kernel tiles reproduce a full weighted sum exactly", {
  skip_if_not_installed("terra")
  template <- terra::rast(
    nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4,
    crs = "EPSG:4326"
  )
  layers <- lapply(1:3, function(i) terra::setValues(template, i * seq_len(16)))
  stack <- terra::rast(layers)
  weights <- terra::rast(lapply(1:3, function(i) terra::setValues(template, 1)))
  dates <- c("2023-01-01", "2023-01-11", "2023-01-21")
  names(stack) <- names(weights) <- dates
  paths <- vapply(seq_len(3), function(i) {
    p <- tempfile(fileext = ".tif")
    terra::writeRaster(stack[[i]], p, overwrite = TRUE, datatype = "FLT8S")
    p
  }, character(1))
  on.exit(unlink(paths, force = TRUE), add = TRUE)

  full <- wapor_masked_sum(stack, weights, layer_multipliers = c(1, 1, 1), incremental = TRUE)
  ones <- terra::setValues(template, 1L)
  job <- .wapor_build_kernel_job(
    period = c("2023-01-01", "2023-01-30"), reference_year = 2023,
    template = template, h_mask = ones,
    h_start = terra::setValues(template, 1L), h_end = terra::setValues(template, 30L),
    variables = list(x = list(variable = "x", paths = paths, multipliers = c(1, 1, 1)))
  )
  plan <- structure(list(mode = "tiled", tile_size = 2L, batch_size = 1L, workers = 1L),
                    class = "wapor_plan")
  tiled <- .wapor_run_kernel(job, template, plan, output_dir = tempfile("rwapor-kernel-"))
  expect_equal(
    as.numeric(terra::values(tiled$rasters$x__season)),
    as.numeric(terra::values(full))
  )
})

test_that("tiled manifest records how each source was aggregated", {
  skip_if_not_installed("terra")
  fx <- local_tiled_fixture()
  on.exit(unlink(c(fx$analysis_dir, fx$out_dir), recursive = TRUE, force = TRUE), add = TRUE)

  tiled <- wapor_run_seasonal_analysis_tiled(
    config = fx$config,
    crop_params = fx$crop_params,
    rasters = fx$rasters,
    output_dir = fx$out_dir,
    tile_size = 2L
  )
  man <- jsonlite::fromJSON(tiled$manifest_path, simplifyVector = FALSE)
  first_sources <- man$tiles[[1]]$sources
  expect_equal(first_sources$aeti$variable, "L1-AETI-D")
  expect_equal(first_sources$aeti$path, "aligned")
  # Sources are read in windows; no per-tile copies are written.
  expect_false(dir.exists(file.path(fx$out_dir, "tiles", man$tiles[[1]]$id, "sources")))
})

test_that("COG writer publishes atomically and remains readable", {
  skip_if_not_installed("terra")
  r <- terra::rast(
    nrows = 8, ncols = 8, xmin = 0, xmax = 8, ymin = 0, ymax = 8,
    crs = "EPSG:4326", vals = 1:64
  )
  path <- tempfile(fileext = ".tif")
  on.exit(unlink(c(path, paste0(path, ".partial.tif")), force = TRUE), add = TRUE)
  out <- wapor_write_cog(r, path, overwrite = TRUE)
  expect_equal(out, path)
  expect_true(file.exists(path))
  expect_false(file.exists(paste0(path, ".partial.tif")))
  got <- terra::rast(path)
  expect_equal(as.numeric(terra::values(got)), 1:64)
  expect_true(isTRUE(.wapor_validate_tile_asset(path, r)))
})

test_that("tiled engine matches the full engine pixel by pixel for AETI and adequacy", {
  skip_if_not_installed("terra")
  fx <- local_tiled_fixture()
  on.exit(unlink(c(fx$analysis_dir, fx$out_dir), recursive = TRUE, force = TRUE), add = TRUE)

  full <- wapor_run_seasonal_analysis(
    config = fx$config,
    crop_params = fx$crop_params,
    rasters = fx$rasters
  )
  tiled <- wapor_run_seasonal_analysis_tiled(
    config = fx$config,
    crop_params = fx$crop_params,
    rasters = fx$rasters,
    output_dir = fx$out_dir,
    tile_size = 2L
  )
  expect_equal(
    as.numeric(terra::values(tiled$results$seasonal_aeti$raster)),
    as.numeric(terra::values(full$seasonal_aeti$raster))
  )
  expect_equal(
    as.numeric(terra::values(tiled$results$adequacy_etc)),
    as.numeric(terra::values(full$adequacy_etc))
  )
})

test_that("tiled engine records block-reducer execution in the manifest", {
  skip_if_not_installed("terra")
  fx <- local_tiled_fixture()
  on.exit(unlink(c(fx$analysis_dir, fx$out_dir), recursive = TRUE, force = TRUE), add = TRUE)

  tiled <- wapor_run_seasonal_analysis_tiled(
    config = fx$config,
    crop_params = fx$crop_params,
    rasters = fx$rasters,
    output_dir = fx$out_dir,
    tile_size = 2L
  )
  man <- jsonlite::fromJSON(tiled$manifest_path, simplifyVector = FALSE)
  expect_true(isTRUE(man$tiles[[1]]$reducer == "block"))
  expect_false(isTRUE(man$tiles[[1]]$used_full_engine))
})

test_that("remote COG fixture windows /vsicurl/ sources without downloading the full file", {
  skip_if_not_installed("terra")
  skip_on_cran()

  fx <- .wapor_remote_cog_fixture()
  on.exit(fx$cleanup(), add = TRUE)

  expect_true(all(grepl("^/vsicurl/", fx$urls)))
  batch <- .wapor_read_native_batch(fx$urls, terra::ext(0, 2, 126, 128), remote = TRUE)
  expect_equal(terra::nrow(batch$geom), 2)
  expect_equal(terra::ncol(batch$geom), 2)
  expect_equal(nrow(batch$X), 4L)
  stats <- fx$http_stats()
  expect_gte(stats$requests, 1L)
  expect_true(stats$range_requests >= 1L || stats$bytes < fx$full_file_bytes)
})

test_that("tiled engine memory stays bounded by tile size rather than AOI size", {
  skip_if_not_installed("terra")
  skip_on_cran()

  bench <- .wapor_tiled_memory_benchmark(
    nrow = 16L,
    ncol = 16L,
    tile_size = 4L,
    n_layers = 3L
  )
  expect_true(is.numeric(bench$peak_bytes))
  expect_lt(bench$peak_bytes, bench$full_aoi_bytes)
  expect_equal(bench$n_tiles, 16L)
})

test_that("unsupported indicator fails loudly in tiled and seasonal engines", {
  skip_if_not_installed("terra")
  fx <- local_tiled_fixture()
  on.exit(unlink(c(fx$analysis_dir, fx$out_dir), recursive = TRUE, force = TRUE), add = TRUE)

  bad_cfg <- fx$config
  bad_cfg$indicators <- c("agg_aeti", "unknown_indicator_xyz")
  expect_error(
    wapor_run_seasonal_analysis_tiled(
      config = bad_cfg,
      crop_params = fx$crop_params,
      rasters = fx$rasters,
      output_dir = fx$out_dir,
      tile_size = 2L
    ),
    "not supported by the tiled engine"
  )
  expect_error(
    wapor_run_seasonal_analysis(
      config = bad_cfg,
      crop_params = fx$crop_params,
      rasters = fx$rasters
    ),
    "not supported by the tiled engine"
  )
})

test_that("changing the indicator set on a resumed tiled run raises an error", {
  skip_if_not_installed("terra")
  fx <- local_tiled_fixture()
  on.exit(unlink(c(fx$analysis_dir, fx$out_dir), recursive = TRUE, force = TRUE), add = TRUE)

  cfg1 <- fx$config
  cfg1$indicators <- c("agg_aeti", "agg_ret")
  wapor_run_seasonal_analysis_tiled(
    config = cfg1,
    crop_params = fx$crop_params,
    rasters = fx$rasters,
    output_dir = fx$out_dir,
    tile_size = 2L,
    resume = FALSE
  )

  cfg2 <- fx$config
  cfg2$indicators <- c("agg_aeti", "agg_ret", "etc", "adequacy_etc")
  expect_error(
    wapor_run_seasonal_analysis_tiled(
      config = cfg2,
      crop_params = fx$crop_params,
      rasters = fx$rasters,
      output_dir = fx$out_dir,
      tile_size = 2L,
      resume = TRUE
    ),
    "Existing tiled run manifest does not match this configuration"
  )
})

test_that("tiled engine supports all built-in indicators and matches in-memory across tile sizes 16, 32, 64", {
  skip_if_not_installed("terra")
  analysis_dir <- tempfile("rwapor-tiled-fullsrc-")
  dir.create(analysis_dir, recursive = TRUE)
  on.exit(unlink(analysis_dir, recursive = TRUE, force = TRUE), add = TRUE)

  dates <- c("2023-01-01", "2023-01-11", "2023-01-21")
  template <- terra::rast(
    nrows = 36, ncols = 36, xmin = 30, xmax = 31, ymin = 30, ymax = 31,
    crs = "EPSG:4326"
  )
  nc <- terra::ncell(template)
  mask_vals <- rep(c(1L, 2L), length.out = nc)
  crop_mask <- terra::setValues(template, mask_vals)
  season_start <- terra::setValues(template, 1L)
  season_end <- terra::setValues(template, 31L)

  write_var <- function(variable, base_vals) {
    var_dir <- file.path(analysis_dir, variable)
    dir.create(var_dir, recursive = TRUE)
    for (i in seq_along(dates)) {
      vals <- base_vals[i] + seq_len(nc) * 0.002
      r <- terra::setValues(template, vals)
      terra::writeRaster(
        r,
        file.path(var_dir, sprintf("WAPOR-3.%s.%s.tif", variable, dates[i])),
        overwrite = TRUE
      )
    }
  }
  write_var("L1-AETI-D", c(2.5, 3.2, 4.1))
  write_var("L1-RET-D", c(4.0, 4.5, 5.0))
  write_var("L1-PCP-D", c(1.5, 2.0, 1.0))
  write_var("L1-NPP-D", c(3.0, 3.5, 4.0))
  write_var("L1-T-D", c(1.8, 2.4, 3.1))

  crop_params <- data.frame(
    class_value = c(1L, 2L),
    crop_label = c("Wheat", "Maize"),
    kc_ini = c(0.4, 0.35),
    kc_mid = c(1.15, 1.20),
    kc_end = c(0.30, 0.35),
    l_ini_days = c(10L, 10L),
    l_mid_days = c(10L, 10L),
    l_late_days = c(11L, 11L),
    HI = c(0.45, 0.50),
    MC = c(0.12, 0.14),
    fc = c(1.0, 1.0),
    AOT = c(0.80, 0.85),
    stringsAsFactors = FALSE
  )

  all_ind <- c(
    "agg_aeti", "agg_ret", "agg_pcp", "agg_t", "agg_npp",
    "peff_green_blue", "etc", "adequacy_etc", "adequacy_p95",
    "beneficial_fraction", "et_rain", "rainfall_surplus",
    "agg_biomass_kg", "agg_biomass_t", "yield_npp",
    "cwp_bwp", "nir", "nbwp", "variability"
  )

  cfg <- list(
    period = c("2023-01-01", "2023-01-31"),
    ref_year = 2023,
    aeti_var = "L1-AETI-D",
    ret_var = "L1-RET-D",
    precip_var = "L1-PCP-D",
    npp_var = "L1-NPP-D",
    t_var = "L1-T-D",
    data_source = "local",
    folder = analysis_dir,
    indicators = all_ind,
    use_crop_mask = TRUE,
    use_season_rasters = TRUE,
    incremental = FALSE
  )
  rasters <- list(crop_mask = crop_mask, season_start = season_start, season_end = season_end)

  mem <- wapor_run_seasonal_analysis(config = cfg, crop_params = crop_params, rasters = rasters)

  out_dir_16 <- tempfile("rwapor-tiled-16-")
  on.exit(unlink(out_dir_16, recursive = TRUE, force = TRUE), add = TRUE)
  tiled_16 <- wapor_run_seasonal_analysis_tiled(
    config = cfg, crop_params = crop_params, rasters = rasters,
    output_dir = out_dir_16, tile_size = 16L
  )

  raster_checks <- list(
    seasonal_aeti = list(mem = mem$seasonal_aeti$raster, tiled = tiled_16$results$seasonal_aeti$raster),
    seasonal_ret = list(mem = mem$seasonal_ret$raster, tiled = tiled_16$results$seasonal_ret$raster),
    seasonal_pcp = list(mem = mem$seasonal_pcp, tiled = tiled_16$results$seasonal_pcp),
    seasonal_peff = list(mem = mem$seasonal_peff, tiled = tiled_16$results$seasonal_peff),
    seasonal_t = list(mem = mem$seasonal_t$raster, tiled = tiled_16$results$seasonal_t$raster),
    seasonal_npp = list(mem = mem$seasonal_npp$raster, tiled = tiled_16$results$seasonal_npp$raster),
    seasonal_biomass_kg = list(mem = mem$seasonal_biomass_kg, tiled = tiled_16$results$seasonal_biomass_kg),
    seasonal_biomass_t = list(mem = mem$seasonal_biomass_t, tiled = tiled_16$results$seasonal_biomass_t),
    seasonal_etc = list(mem = mem$seasonal_etc, tiled = tiled_16$results$seasonal_etc),
    adequacy_etc = list(mem = mem$adequacy_etc, tiled = tiled_16$results$adequacy_etc),
    adequacy_p95 = list(mem = mem$adequacy_p95, tiled = tiled_16$results$adequacy_p95),
    beneficial_fraction = list(mem = mem$beneficial_fraction, tiled = tiled_16$results$beneficial_fraction),
    green_water = list(mem = mem$green_water, tiled = tiled_16$results$green_water),
    blue_water = list(mem = mem$blue_water, tiled = tiled_16$results$blue_water),
    et_rain = list(mem = mem$et_rain, tiled = tiled_16$results$et_rain),
    rainfall_surplus = list(mem = mem$rainfall_surplus, tiled = tiled_16$results$rainfall_surplus),
    yield_raster = list(mem = mem$yield_raster, tiled = tiled_16$results$yield_raster),
    cwp_raster = list(mem = mem$cwp_raster, tiled = tiled_16$results$cwp_raster),
    bwp_raster = list(mem = mem$bwp_raster, tiled = tiled_16$results$bwp_raster),
    seasonal_nir = list(mem = mem$seasonal_nir, tiled = tiled_16$results$seasonal_nir),
    nbwp_raster = list(mem = mem$nbwp_raster, tiled = tiled_16$results$nbwp_raster)
  )

  for (nm in names(raster_checks)) {
    pair <- raster_checks[[nm]]
    expect_true(inherits(pair$mem, "SpatRaster"), info = paste("mem", nm))
    expect_true(inherits(pair$tiled, "SpatRaster"), info = paste("tiled", nm))
    expect_equal(
      as.numeric(terra::values(pair$tiled)),
      as.numeric(terra::values(pair$mem)),
      tolerance = 1e-6,
      info = paste("parity", nm)
    )
    expect_true(!is.null(tiled_16$saved_files[[nm]]), info = paste("saved_files", nm))
    expect_true(file.exists(tiled_16$saved_files[[nm]]), info = paste("file exists", nm))
  }

  expect_equal(tiled_16$results$p95_table$p95_aeti, mem$p95_table$p95_aeti, tolerance = 1e-6)
  expect_equal(tiled_16$results$cwp, mem$cwp, tolerance = 1e-6)
  expect_equal(tiled_16$results$bwp, mem$bwp, tolerance = 1e-6)
  expect_equal(tiled_16$results$cwp_summary$cwp_kg_m3, mem$cwp_summary$cwp_kg_m3, tolerance = 1e-6)
  expect_equal(tiled_16$results$nbwp, mem$nbwp, tolerance = 1e-6)
  expect_equal(tiled_16$results$cv_aeti$cv_pct, mem$cv_aeti$cv_pct, tolerance = 1e-6)
  expect_equal(tiled_16$results$theil_aeti$theil_t, mem$theil_aeti$theil_t, tolerance = 1e-6)

  # Verify adequacy_p95 invariance across tile sizes 32 and 64 (R-02)
  for (ts in c(32L, 64L)) {
    od <- tempfile(paste0("rwapor-tiled-", ts, "-"))
    on.exit(unlink(od, recursive = TRUE, force = TRUE), add = TRUE)
    cfg_p95 <- cfg
    cfg_p95$indicators <- c("agg_aeti", "adequacy_p95")
    t_run <- wapor_run_seasonal_analysis_tiled(
      config = cfg_p95, crop_params = crop_params, rasters = rasters,
      output_dir = od, tile_size = ts
    )
    expect_equal(t_run$results$p95_table$p95_aeti, mem$p95_table$p95_aeti, tolerance = 1e-6, info = paste("p95 table ts=", ts))
    expect_equal(
      as.numeric(terra::values(t_run$results$adequacy_p95)),
      as.numeric(terra::values(mem$adequacy_p95)),
      tolerance = 1e-6,
      info = paste("adequacy_p95 raster ts=", ts)
    )
  }
})
