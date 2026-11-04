make_map_source_files <- function(dir, dates = c("D1", "D3")) {
  paths <- file.path(dir, paste0("WAPOR-3.L1-AETI-D.2023-01-", dates, ".tif"))
  for (i in seq_along(paths)) {
    terra::writeRaster(
      terra::rast(
        nrows = 10, ncols = 10, xmin = 35, xmax = 36, ymin = 33, ymax = 34,
        crs = "EPSG:4326", vals = rep(i, 100)
      ),
      paths[[i]], overwrite = TRUE
    )
  }
  paths
}

run_local_map_sources <- function(source_urls, output_dir, partial, separate_files = TRUE) {
  local_mocked_bindings(
    wapor_generate_urls = function(...) source_urls,
    .wapor_resolve_remote_sources = function(urls, ...) urls,
    .package = "Rwapor"
  )
  wapor_map(
    region = c(35.1, 33.1, 35.9, 33.9),
    variable = "L1-AETI-D",
    period = c("2023-01-01", "2023-01-31"),
    folder = output_dir,
    separate_files = separate_files,
    unit_conversion = "none",
    batching = TRUE,
    batch_size = 1L,
    partial = partial
  )
}

test_that("partial separate-file map publishes valid layers and reports coverage", {
  source_dir <- withr::local_tempdir()
  output_dir <- withr::local_tempdir()
  good <- make_map_source_files(source_dir)
  missing <- file.path(source_dir, "WAPOR-3.L1-AETI-D.2023-01-D2.tif")

  expect_warning(
    result <- run_local_map_sources(c(good[[1]], missing, good[[2]]), output_dir, partial = TRUE),
    "Returning partial output"
  )
  status <- attr(result, "wapor_status")
  expect_identical(status$status, "partial")
  expect_false(status$complete)
  expect_equal(status$expected_layers, 3L)
  expect_equal(status$received_layers, 2L)
  expect_equal(length(status$failed_layers), 1L)
  expect_equal(status$coverage_fraction, 2 / 3)
  expect_identical(status$requested_period, c("2023-01-01", "2023-01-31"))
  expect_true(all(file.exists(result)))
  expect_length(result, 2L)
  expect_true(file.exists(file.path(output_dir, "L1-AETI-D", "L1-AETI-D_failed_layers.csv")))
})

test_that("strict separate-file map leaves no final files when a chunk fails", {
  source_dir <- withr::local_tempdir()
  output_dir <- withr::local_tempdir()
  good <- make_map_source_files(source_dir)
  missing <- file.path(source_dir, "WAPOR-3.L1-AETI-D.2023-01-D2.tif")

  expect_error(
    run_local_map_sources(c(good[[1]], missing, good[[2]]), output_dir, partial = FALSE),
    "raster batch.*failed.*partial = TRUE"
  )
  final_dir <- file.path(output_dir, "L1-AETI-D")
  published <- list.files(final_dir, pattern = "[.]tif$", recursive = TRUE, full.names = TRUE)
  expect_length(published, 0L)
})

test_that("strict stack-mode chunk failures clean all staged raster files", {
  source_dir <- withr::local_tempdir()
  output_dir <- withr::local_tempdir()
  good <- make_map_source_files(source_dir)
  missing <- file.path(source_dir, "WAPOR-3.L1-AETI-D.2023-01-D2.tif")
  tif_files <- function() list.files(tempdir(), pattern = "[.]tif$", full.names = TRUE)
  before <- tif_files()
  on.exit({
    created <- setdiff(tif_files(), before)
    if (length(created)) unlink(created, force = TRUE)
  }, add = TRUE)

  expect_error(
    run_local_map_sources(
      c(good[[1]], missing, good[[2]]), output_dir,
      partial = FALSE, separate_files = FALSE
    ),
    "raster batch.*failed.*partial = TRUE"
  )
  after <- tif_files()
  expect_setequal(after, before)
  expect_length(list.files(file.path(output_dir, "L1-AETI-D"), pattern = "[.]tif$", recursive = TRUE), 0L)
})

test_that("partial stack output contains only received layers and records coverage", {
  source_dir <- withr::local_tempdir()
  output_dir <- withr::local_tempdir()
  good <- make_map_source_files(source_dir)
  missing <- file.path(source_dir, "WAPOR-3.L1-AETI-D.2023-01-D2.tif")

  expect_warning(
    result <- run_local_map_sources(
      c(good[[1]], missing, good[[2]]), output_dir,
      partial = TRUE, separate_files = FALSE
    ),
    "Returning partial output"
  )
  status <- attr(result, "wapor_status")
  raster <- terra::rast(result)
  expect_identical(status$status, "partial")
  expect_false(status$complete)
  expect_equal(terra::nlyr(raster), 2L)
  expect_equal(status$expected_layers, 3L)
  expect_equal(status$received_layers, 2L)
  expect_equal(status$coverage_fraction, 2 / 3)
  expect_length(list.files(
    file.path(output_dir, "L1-AETI-D"), pattern = "^\\.wapor-map-stage-",
    all.files = TRUE, recursive = TRUE, include.dirs = TRUE
  ), 0L)
})

test_that("wapor_map rolls back existing per-date files if a later publication fails", {
  source_dir <- withr::local_tempdir()
  output_dir <- withr::local_tempdir()
  source_urls <- make_map_source_files(source_dir, dates = c("D1", "D2", "D3"))
  variable_dir <- file.path(output_dir, "L1-AETI-D")
  dir.create(variable_dir)
  targets <- file.path(variable_dir, paste0(
    "bb_WAPOR-3.L1-AETI-D.", c("2023-01-01", "2023-01-11", "2023-01-21"), ".tif"
  ))
  for (i in seq_along(targets)) writeLines(paste("old output", i), targets[[i]])

  publisher <- Rwapor:::.wapor_publish_file_set
  rename_calls <- 0L
  fail_fourth_rename <- function(from, to) {
    rename_calls <<- rename_calls + 1L
    if (rename_calls == 4L) return(FALSE)
    file.rename(from, to)
  }
  local_mocked_bindings(
    wapor_generate_urls = function(...) source_urls,
    .wapor_resolve_remote_sources = function(urls, ...) urls,
    .wapor_publish_file_set = function(staged_paths, target_paths) {
      publisher(staged_paths, target_paths, rename_fn = fail_fourth_rename)
    },
    .package = "Rwapor"
  )

  expect_error(
    wapor_map(
      region = c(35.1, 33.1, 35.9, 33.9),
      variable = "L1-AETI-D",
      period = c("2023-01-01", "2023-01-31"),
      folder = output_dir,
      separate_files = TRUE,
      unit_conversion = "none",
      batching = TRUE,
      batch_size = 1L,
      partial = FALSE
    ),
    "Could not publish completed output"
  )

  expect_identical(lapply(targets, readLines), lapply(seq_along(targets), function(i) paste("old output", i)))
  expect_length(list.files(variable_dir, pattern = "[.]backup$", all.files = TRUE), 0L)
  expect_length(list.files(variable_dir, pattern = "^\\.wapor-map-stage-", all.files = TRUE,
                           recursive = TRUE, include.dirs = TRUE), 0L)
})

test_that("all-failed partial map returns failed coverage with no outputs", {
  source_dir <- withr::local_tempdir()
  output_dir <- withr::local_tempdir()
  missing <- file.path(source_dir, paste0("WAPOR-3.L1-AETI-D.2023-01-", c("D1", "D2"), ".tif"))

  expect_warning(
    result <- run_local_map_sources(missing, output_dir, partial = TRUE),
    "All chunks failed"
  )
  status <- attr(result, "wapor_status")
  expect_length(result, 0L)
  expect_identical(status$status, "failed")
  expect_false(status$complete)
  expect_equal(status$expected_layers, 2L)
  expect_equal(status$received_layers, 0L)
  expect_equal(status$coverage_fraction, 0)
  expect_length(list.files(output_dir, pattern = "[.]tif$", recursive = TRUE), 0L)
})
