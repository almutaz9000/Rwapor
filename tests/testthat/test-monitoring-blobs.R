test_that("monitoring blobs apply source scale exactly once and report outcomes", {
  skip_if_not_installed("duckdb")

  make_raster <- function(date, path = NULL) {
    path <- path %||% file.path(tempdir(), paste0("WAPOR-3.L1-AETI-D.", date, ".tif"))
    r <- terra::rast(nrows = 8, ncols = 8, xmin = 35.95, xmax = 36.05, ymin = 33.80, ymax = 33.90,
                     crs = "EPSG:4326", vals = 250)
    tmp <- tempfile(fileext = ".tif")
    on.exit(unlink(tmp), add = TRUE)
    terra::writeRaster(r, tmp, datatype = "INT2S", overwrite = TRUE)
    if (file.exists(path)) unlink(path)
    sf::gdal_utils("translate", tmp, path, options = c("-a_scale", "0.1", "-a_offset", "0"))
    expect_equal(unname(terra::scoff(terra::rast(path))[1, "scale"]), 0.1)
    path
  }
  farms <- sf::st_as_sf(data.frame(farm_id = "farm", wkt = "POLYGON((35.97 33.82, 36.03 33.82, 36.03 33.88, 35.97 33.88, 35.97 33.82))"),
                        wkt = "wkt", crs = 4326)
  first <- make_raster("2023-01-D1")
  second <- make_raster("2023-01-D2")
  urls <- c(first, second)
  testthat::local_mocked_bindings(
    wapor_generate_urls = function(...) urls,
    .wapor_resolve_remote_sources = function(x) x,
    .package = "Rwapor"
  )
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  wapor_init_monitoring_db(con)
  period <- c("2023-01-01", "2023-01-20")

  res <- wapor_save_raster_blobs(con, farms, "L1-AETI-D", period, log_fn = function(...) NULL)
  blobs <- DBI::dbGetQuery(con, "SELECT raster_blob FROM monitoring_rasters ORDER BY date_key")$raster_blob
  conversion <- if (identical(resolve_output_unit_conversion("L1-AETI-D", NULL), "dekad")) 10 else 1
  for (blob in blobs) {
    r <- wapor_raster_from_blob(blob)
    # This equality also rejects values scaled twice (2.5 * conversion) or not at all (250 * conversion).
    expect_equal(range(terra::values(r), na.rm = TRUE), rep(25 * conversion, 2), tolerance = 1e-4)
  }
  expect_equal(res$saved, 2L)
  expect_equal(res$existing, 0L)
  expect_length(res$failed, 0)

  existing <- wapor_save_raster_blobs(con, farms, "L1-AETI-D", period, log_fn = function(...) NULL)
  expect_equal(existing$saved, 0L)
  expect_equal(existing$existing, 2L)
})

test_that("monitoring blobs warn for failed layers and never invent dates", {
  skip_if_not_installed("duckdb")

  make_raster <- function(path) {
    r <- terra::rast(nrows = 8, ncols = 8, xmin = 35.95, xmax = 36.05, ymin = 33.80, ymax = 33.90,
                     crs = "EPSG:4326", vals = 250)
    terra::writeRaster(r, path, datatype = "INT2S", overwrite = TRUE)
    path
  }
  farms <- sf::st_as_sf(data.frame(farm_id = "farm", wkt = "POLYGON((35.97 33.82, 36.03 33.82, 36.03 33.88, 35.97 33.88, 35.97 33.82))"),
                        wkt = "wkt", crs = 4326)
  first <- make_raster(file.path(tempdir(), "WAPOR-3.L1-AETI-D.2023-01-D1.tif"))
  second <- make_raster(file.path(tempdir(), "WAPOR-3.L1-AETI-D.2023-01-D2.tif"))
  missing <- file.path(tempdir(), "WAPOR-3.L1-AETI-D.2023-01-D3.tif")
  urls <- c(first, second, missing)
  testthat::local_mocked_bindings(
    wapor_generate_urls = function(...) urls,
    .wapor_resolve_remote_sources = function(x) x,
    .package = "Rwapor"
  )
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  wapor_init_monitoring_db(con)
  expect_warning(
    res <- wapor_save_raster_blobs(con, farms, "L1-AETI-D", c("2023-01-01", "2023-01-31"), log_fn = function(...) NULL),
    "not saved"
  )
  expect_true("2023-01-21" %in% res$failed)
  expect_equal(res$saved, 2L)

  undated <- make_raster(file.path(tempdir(), "nodate.tif"))
  testthat::local_mocked_bindings(
    wapor_generate_urls = function(...) undated,
    .wapor_resolve_remote_sources = function(x) x,
    .package = "Rwapor"
  )
  con2 <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con2, shutdown = TRUE), add = TRUE)
  wapor_init_monitoring_db(con2)
  expect_warning(
    undated_res <- wapor_save_raster_blobs(con2, farms, "L1-AETI-D", c("2023-01-01", "2023-01-31"), log_fn = function(...) NULL),
    "not saved"
  )
  expect_true("undated:nodate.tif" %in% undated_res$failed)
  expect_false(any(DBI::dbGetQuery(con2, "SELECT CAST(date_key AS VARCHAR) AS date_key FROM monitoring_rasters")$date_key == as.character(Sys.Date())))
})
