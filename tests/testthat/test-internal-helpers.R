# Tests for internal helpers added in v0.9.9

test_that("get_url_chunks returns single chunk when batching FALSE", {
  urls <- paste0("url_", 1:20)
  result <- Rwapor:::get_url_chunks(urls, batching = FALSE, batch_size = 5)
  expect_length(result, 1)
  expect_equal(result[[1]], urls)
})

test_that("get_url_chunks returns single chunk when count <= batch_size", {
  urls <- paste0("url_", 1:5)
  result <- Rwapor:::get_url_chunks(urls, batching = TRUE, batch_size = 12)
  expect_length(result, 1)
})

test_that("get_url_chunks splits into correct chunks", {
  urls <- paste0("url_", 1:25)
  result <- Rwapor:::get_url_chunks(urls, batching = TRUE, batch_size = 10)
  expect_equal(length(result), 3)
  expect_equal(length(result[[1]]), 10)
  expect_equal(length(result[[3]]), 5)
  expect_setequal(unlist(result, use.names = FALSE), urls)
})

test_that("resolve_output_unit_conversion returns dekad for dekadal", {
  expect_equal(Rwapor:::resolve_output_unit_conversion("L1-AETI-D", NULL), "dekad")
})

test_that("resolve_output_unit_conversion returns none for monthly", {
  expect_equal(Rwapor:::resolve_output_unit_conversion("L1-AETI-M", NULL), "none")
})

test_that("resolve_output_unit_conversion respects explicit none", {
  expect_equal(Rwapor:::resolve_output_unit_conversion("L1-AETI-D", "none"), "none")
})

test_that("resolve_output_unit_conversion rejects invalid modes", {
  expect_error(Rwapor:::resolve_output_unit_conversion("L1-AETI-D", "dekad"), "must be one of")
})

test_that("map output applies the source file scale exactly once", {
  skip_if_not_installed("terra")
  skip_if_not_installed("sf")
  # A WaPOR-style COG: Int16 value 25 with GDAL scale 0.1 (2.5 mm/day).
  raw_path <- withr::local_tempfile(fileext = ".tif")
  scaled_path <- withr::local_tempfile(fileext = ".tif")
  terra::writeRaster(
    terra::rast(nrows = 20, ncols = 20, xmin = 35, xmax = 36, ymin = 33, ymax = 34,
                crs = "EPSG:4326", vals = rep(25L, 400)),
    raw_path, datatype = "INT2S"
  )
  sf::gdal_utils("translate", raw_path, scaled_path, options = c("-a_scale", "0.1"))
  reg <- Rwapor:::wapor_parse_region(c(35.2, 33.2, 35.8, 33.8))
  url <- "https://x/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-01-D1.tif"

  run_chain <- function(unit_conversion) {
    src <- Rwapor:::.wapor_detach_source_scale(terra::rast(scaled_path))
    r <- Rwapor:::wapor_crop_to_region(src$raster, reg)
    r <- Rwapor:::.wapor_apply_source_scale(r, src$scale, src$offset)
    if (unit_conversion != "none") r <- wapor_convert_raster(r, "L1-AETI-D", url, unit_conversion)
    # Both write paths: single layer directly, and via a temporary stack file.
    direct <- Rwapor:::.wapor_prepare_map_output(r[[1]], "L1-AETI-D", unit_conversion)
    tmp <- withr::local_tempfile(fileext = ".tif", .local_envir = parent.frame())
    terra::writeRaster(r, tmp, NAflag = -9999)
    stacked <- Rwapor:::.wapor_prepare_map_output(terra::rast(tmp), "L1-AETI-D", unit_conversion)
    c(direct = terra::values(direct)[1], stacked = terra::values(stacked)[1])
  }

  expect_equal(unname(run_chain("none")), c(2.5, 2.5), tolerance = 1e-6)
  # D1 dekad = 10 days: 2.5 mm/day -> 25 mm/dekad.
  expect_equal(unname(run_chain("dekad")), c(25, 25), tolerance = 1e-6)
})

test_that("map output does not rescale files without a stored scale", {
  skip_if_not_installed("terra")
  # A local Float32 copy already holds physical values.
  physical <- terra::rast(nrows = 1, ncols = 1, vals = 2.5)
  src <- Rwapor:::.wapor_detach_source_scale(physical)
  r <- Rwapor:::.wapor_apply_source_scale(src$raster, src$scale, src$offset)
  out <- Rwapor:::.wapor_prepare_map_output(r, "L1-AETI-D", "none")
  expect_equal(as.numeric(terra::values(out)), 2.5)
})

test_that("kernel profile keys rebase a historic reference year", {
  skip_if_not_installed("terra")
  template <- terra::rast(nrows = 1, ncols = 1, vals = 1)
  start_1970 <- wapor_continuous_julian("2024-01-01", 1970)
  end_1970 <- wapor_continuous_julian("2024-01-31", 1970)
  job <- Rwapor:::.wapor_build_kernel_job(
    period = c("2024-01-01", "2024-01-31"), reference_year = 1970,
    template = template, h_mask = template,
    h_start = template * 0 + start_1970, h_end = template * 0 + end_1970,
    variables = list(), work_dir = withr::local_tempdir()
  )
  expect_equal(job$profiles$start_jd, 1L)
  expect_equal(job$profiles$end_jd, 31L)
})

test_that("ref_year from config takes precedence over start-date year", {
  cfg_with    <- list(period = c("2018-10-01", "2019-05-31"), ref_year = 2019L)
  cfg_without <- list(period = c("2018-10-01", "2019-05-31"))
  ref_with    <- cfg_with$ref_year    %||% as.integer(format(as.Date(cfg_with$period[1]),    "%Y"))
  ref_without <- cfg_without$ref_year %||% as.integer(format(as.Date(cfg_without$period[1]), "%Y"))
  expect_equal(ref_with,    2019L)
  expect_equal(ref_without, 2018L)
})

test_that("get_url_chunks works with a single URL", {
  result <- Rwapor:::get_url_chunks("url_1", batching = TRUE, batch_size = 12)
  expect_length(result, 1)
  expect_equal(result[[1]], "url_1")
})

test_that("wapor_map returns file paths usable by terra::rast and the dashboard", {
  skip_if_not_installed("terra")
  src <- withr::local_tempdir()
  files <- file.path(src, sprintf("WAPOR-3.L1-AETI-D.2023-01-D%d.tif", 1:3))
  for (i in seq_along(files)) {
    terra::writeRaster(
      terra::rast(nrows = 10, ncols = 10, xmin = 35, xmax = 36, ymin = 33, ymax = 34,
                  crs = "EPSG:4326", vals = i),
      files[i]
    )
  }
  local_mocked_bindings(
    wapor_generate_urls = function(...) files,
    .wapor_resolve_remote_sources = function(urls, ...) urls
  )
  run <- function(...) suppressMessages(wapor_map(
    c(35.2, 33.2, 35.8, 33.8), "L1-AETI-D", c("2023-01-01", "2023-01-31"),
    withr::local_tempdir(.local_envir = parent.frame(2)), ...
  ))

  stack <- run()
  expect_type(stack, "character")
  expect_length(stack, 1L)
  expect_equal(terra::nlyr(terra::rast(stack)), 3)
  expect_identical(attr(stack, "wapor_status")$status, "ok")

  separate <- run(separate_files = TRUE)
  expect_length(separate, 3L)
  # The dashboard checks unlist(result) with file.exists().
  expect_true(all(file.exists(unlist(list(`L1-AETI-D` = separate)))))
})
