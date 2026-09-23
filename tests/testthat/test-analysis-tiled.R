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
  plan <- structure(list(mode = "tiled", tile_size = 2L, batch_size = 1L, workers = 1L,
                         gdal_chunk_bytes = 1e6), class = "wapor_plan")
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
