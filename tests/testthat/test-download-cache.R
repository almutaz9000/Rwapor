# wapor_download() and config$cache_dir (ti-06): download once, work offline.
# Sources are WaPOR-style files on disk (Int16, GDAL scale 0.1); the URL list is stubbed.

.dl_sources <- function(values = c(25L, 30L, 20L), env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  files <- file.path(dir, sprintf("WAPOR-3.L1-AETI-D.2023-01-D%d.tif", seq_along(values)))
  for (i in seq_along(values)) {
    raw <- file.path(dir, sprintf("raw%d.tif", i))
    terra::writeRaster(
      terra::rast(nrows = 20, ncols = 20, xmin = 35, xmax = 36, ymin = 33, ymax = 34,
                  crs = "EPSG:4326", vals = rep(values[i], 400)),
      raw, datatype = "INT2S"
    )
    sf::gdal_utils("translate", raw, files[i], options = c("-a_scale", "0.1"))
    unlink(raw)
  }
  files
}
.dl_box <- c(35.2, 33.2, 35.8, 33.8)
.dl_period <- c("2023-01-01", "2023-01-31")

test_that("wapor_download saves one scaled file per date and skips what is there", {
  skip_if_not_installed("sf")
  files <- .dl_sources()
  folder <- withr::local_tempdir()
  local_mocked_bindings(
    wapor_generate_urls = function(...) files,
    .wapor_resolve_remote_sources = function(urls, ...) urls
  )
  out <- suppressMessages(wapor_download("L1-AETI-D", .dl_box, .dl_period, folder))
  expect_identical(basename(out), sprintf("WAPOR-3.L1-AETI-D.2023-01-%s.tif", c("01", "11", "21")))
  expect_true(all(file.exists(out)))
  expect_identical(attr(out, "wapor_status")[c("downloaded", "existing", "online")],
                   list(downloaded = 3L, existing = 0L, online = TRUE))
  # The file scale is applied exactly once: Int16 25 x 0.1 = 2.5 mm/day, no dekad conversion.
  means <- vapply(out, function(f) terra::global(terra::rast(f), "mean", na.rm = TRUE)[1, 1], numeric(1))
  expect_equal(unname(means), c(2.5, 3.0, 2.0), tolerance = 1e-6)
  expect_identical(terra::scoff(terra::rast(out[1]))[1, ], c(scale = 1, offset = 0))
  # Cropped to the area, no partial files, and the area is recorded.
  expect_lt(terra::ncell(terra::rast(out[1])), 400)
  expect_length(list.files(file.path(folder, "L1-AETI-D"), "[.]part$"), 0)
  expect_true(file.exists(file.path(folder, "L1-AETI-D", ".wapor_download.json")))
  # The local reader finds exactly these files.
  expect_identical(normalizePath(wapor_local_rasters(folder, "L1-AETI-D", .dl_period[1], .dl_period[2])),
                   normalizePath(as.character(out)))

  # Second call: nothing is read from the sources.
  local_mocked_bindings(.wapor_resolve_remote_sources = function(urls, ...) stop("sources must not be read"))
  again <- suppressMessages(wapor_download("L1-AETI-D", .dl_box, .dl_period, folder))
  expect_identical(attr(again, "wapor_status")$downloaded, 0L)
  expect_identical(as.character(again), as.character(out))
})

test_that("wapor_download fetches only missing files and replaces empty ones", {
  skip_if_not_installed("sf")
  files <- .dl_sources()
  folder <- withr::local_tempdir()
  read <- character()
  local_mocked_bindings(
    wapor_generate_urls = function(...) files,
    .wapor_resolve_remote_sources = function(urls, ...) { read <<- c(read, basename(urls)); urls }
  )
  out <- suppressMessages(wapor_download("L1-AETI-D", .dl_box, .dl_period, folder))
  unlink(out[2])
  file.create(out[3])                       # a zero-byte leftover is not a valid file
  unlink(out[3]); file.create(out[3])
  read <- character()
  again <- suppressMessages(wapor_download("L1-AETI-D", .dl_box, .dl_period, folder))
  expect_identical(attr(again, "wapor_status")$downloaded, 2L)
  expect_identical(read, basename(files[2:3]))
  expect_equal(terra::global(terra::rast(again[3]), "mean", na.rm = TRUE)[1, 1], 2.0, tolerance = 1e-6)

  read <- character()
  forced <- suppressMessages(wapor_download("L1-AETI-D", .dl_box, .dl_period, folder, overwrite = TRUE))
  expect_identical(attr(forced, "wapor_status")$downloaded, 3L)
})

test_that("wapor_download works offline from saved files and says what it could not check", {
  skip_if_not_installed("sf")
  files <- .dl_sources()
  folder <- withr::local_tempdir()
  local_mocked_bindings(
    wapor_generate_urls = function(...) files,
    .wapor_resolve_remote_sources = function(urls, ...) urls
  )
  out <- suppressMessages(wapor_download("L1-AETI-D", .dl_box, .dl_period, folder))

  local_mocked_bindings(wapor_generate_urls = function(...) stop("could not resolve host"))
  expect_warning(
    offline <- wapor_download("L1-AETI-D", .dl_box, .dl_period, folder),
    "Using the 3 file\\(s\\) already saved.*not possible to check that the period is complete"
  )
  expect_identical(normalizePath(as.character(offline)), normalizePath(as.character(out)))
  expect_false(attr(offline, "wapor_status")$online)
  expect_error(
    wapor_download("L1-RET-D", .dl_box, .dl_period, folder),
    "Cannot list L1-RET-D.*could not resolve host.*no saved files"
  )
})

test_that("a download folder belongs to one area", {
  skip_if_not_installed("sf")
  files <- .dl_sources()
  folder <- withr::local_tempdir()
  local_mocked_bindings(
    wapor_generate_urls = function(...) files,
    .wapor_resolve_remote_sources = function(urls, ...) urls
  )
  suppressMessages(wapor_download("L1-AETI-D", .dl_box, .dl_period, folder))
  expect_error(wapor_download("L1-AETI-D", c(35.1, 33.1, 35.9, 33.9), .dl_period, folder), "another area")
  expect_error(wapor_download("L1-AETI-D", .dl_box, .dl_period, folder, mask = TRUE), "another 'mask' setting")
  # An area inside the saved one is served by the same (unmasked) files.
  inner <- suppressMessages(wapor_download("L1-AETI-D", c(35.3, 33.3, 35.7, 33.7), .dl_period, folder))
  expect_identical(attr(inner, "wapor_status")$downloaded, 0L)
  # overwrite = TRUE replaces files of the same area; it does not allow mixing areas.
  expect_error(wapor_download("L1-AETI-D", c(35.1, 33.1, 35.9, 33.9), .dl_period, folder, overwrite = TRUE),
               "another area")
  same <- suppressMessages(wapor_download("L1-AETI-D", .dl_box, .dl_period, folder, overwrite = TRUE))
  expect_identical(attr(same, "wapor_status")$downloaded, 3L)
})

test_that("wapor_download validates its arguments and refuses several files per date", {
  folder <- withr::local_tempdir()
  expect_error(wapor_download(character(0), .dl_box, .dl_period, folder), "variable")
  expect_error(wapor_download("L1-AETI-D", .dl_box, "2023-01-01", folder), "period")
  expect_error(wapor_download("L1-AETI-D", .dl_box, c("2023-01-01", "soon"), folder), "period")
  expect_error(wapor_download("L1-AETI-D", .dl_box, .dl_period, folder, mask = NA), "mask")
  local_mocked_bindings(
    wapor_generate_urls = function(...) c("https://x/L3-AETI-D/WAPOR-3.L3-AETI-D.AAA.2023-01-D1.tif",
                                          "https://x/L3-AETI-D/WAPOR-3.L3-AETI-D.BBB.2023-01-D1.tif")
  )
  expect_error(wapor_download("L3-AETI-D", .dl_box, .dl_period, folder), "more than one file per date")
})

test_that("config$cache_dir fills the cache and gives the result of a local run on it", {
  skip_if_not_installed("sf")
  aeti <- .dl_sources(c(25L, 30L, 20L))
  ret_dir <- withr::local_tempdir()
  ret <- file.path(ret_dir, sub("AETI", "RET", basename(aeti)))
  file.copy(aeti, ret)
  local_mocked_bindings(
    wapor_generate_urls = function(variable, ...) if (grepl("RET", variable)) ret else aeti,
    .wapor_resolve_remote_sources = function(urls, ...) urls
  )
  cache <- withr::local_tempdir()
  cp <- data.frame(class_value = 1L, crop_label = "Crop", kc_ini = 0.5, kc_mid = 1.1, kc_end = 0.7,
                   l_ini_days = 10L, l_mid_days = 10L, l_late_days = 10L, HI = 0.4, MC = 0.1, fc = 1, AOT = 1)
  run <- function(...) {
    cfg <- utils::modifyList(list(
      period = .dl_period, aeti_var = "L1-AETI-D", ret_var = "L1-RET-D",
      indicators = c("agg_aeti", "agg_ret", "etc", "adequacy_etc"),
      use_crop_mask = FALSE, use_season_rasters = FALSE, output_dir = withr::local_tempdir(.local_envir = parent.frame())
    ), list(...))
    suppressWarnings(suppressMessages(wapor_run_seasonal_analysis(cfg, cp, rasters = list(), aoi_region = .dl_box)))
  }
  cached <- run(data_source = "api", cache_dir = cache)
  expect_length(list.files(file.path(cache, "L1-AETI-D"), "[.]tif$"), 3)
  expect_length(list.files(file.path(cache, "L1-RET-D"), "[.]tif$"), 3)
  local <- run(data_source = "local", folder = cache)
  expect_identical(terra::values(cached$seasonal_aeti$raster), terra::values(local$seasonal_aeti$raster))
  expect_identical(terra::values(cached$adequacy_etc), terra::values(local$adequacy_etc))
  # 10 days x 2.5 + 10 x 3.0 + 11 x 2.0 mm/day
  expect_equal(mean(terra::values(cached$seasonal_aeti$raster), na.rm = TRUE), 77, tolerance = 1e-5)

  # Later runs do not touch the server data, and work when it cannot be listed.
  local_mocked_bindings(wapor_generate_urls = function(...) stop("offline"))
  offline <- run(data_source = "api", cache_dir = cache)
  expect_identical(terra::values(offline$seasonal_aeti$raster), terra::values(cached$seasonal_aeti$raster))

  expect_error(run(data_source = "api", cache_dir = cache, l3_mode = "mosaic_all"), "mosaic_all")
})
