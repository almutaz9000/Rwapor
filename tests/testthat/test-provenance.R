test_that("raster intervals parse WaPOR monthly, dekadal, annual, and daily names", {
  skip_if_not_installed("terra")

  monthly <- terra::rast(nrows = 1, ncols = 1, vals = 1)
  monthly <- c(monthly, monthly)
  names(monthly) <- c(
    "WAPOR-3.L1-AETI-M.2024-02.tif",
    "WAPOR-3.L1-AETI-M.2024-03.tif"
  )
  m <- Rwapor:::.wapor_raster_intervals(monthly)
  expect_equal(m$start_date, c("2024-02-01", "2024-03-01"))
  expect_equal(m$end_date, c("2024-02-29", "2024-03-31"))
  expect_equal(m$temporal_code, c("M", "M"))
  expect_equal(m$metadata_source, c("layer_name", "layer_name"))

  dekadal <- terra::rast(nrows = 1, ncols = 1, vals = 1)
  names(dekadal) <- "WAPOR-3.L1-AETI-D.2024-02-D3.tif"
  d <- Rwapor:::.wapor_raster_intervals(dekadal)
  expect_equal(d$start_date, "2024-02-21")
  expect_equal(d$end_date, "2024-02-29")
  expect_equal(d$temporal_code, "D")

  annual <- terra::rast(nrows = 1, ncols = 1, vals = 1)
  names(annual) <- "WAPOR-3.L1-AETI-A.2023.tif"
  a <- Rwapor:::.wapor_raster_intervals(annual)
  expect_equal(a$start_date, "2023-01-01")
  expect_equal(a$end_date, "2023-12-31")
  expect_equal(a$temporal_code, "A")

  daily <- terra::rast(nrows = 1, ncols = 1, vals = 1)
  names(daily) <- "WAPOR-3.L1-NPP-E.2024-02-29.tif"
  e <- Rwapor:::.wapor_raster_intervals(daily)
  expect_equal(e$start_date, "2024-02-29")
  expect_equal(e$end_date, "2024-02-29")
  expect_equal(e$temporal_code, "E")
})

test_that("explicit complete terra time metadata takes precedence over layer names", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 1, ncols = 1, vals = 1)
  x <- c(x, x)
  names(x) <- c("AETI_2024-01", "AETI_2024-02")
  terra::time(x) <- as.Date(c("2023-11-01", "2023-12-01"))

  intervals <- Rwapor:::.wapor_raster_intervals(x, variable = "L1-AETI-M")
  expect_equal(intervals$start_date, c("2023-11-01", "2023-12-01"))
  expect_equal(intervals$end_date, c("2023-11-30", "2023-12-31"))
  expect_equal(intervals$metadata_source, c("terra_time", "terra_time"))
})

test_that("partial time metadata falls back to complete parseable layer names", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 1, ncols = 1, vals = 1)
  x <- c(x, x)
  names(x) <- c("WAPOR-3.L1-AETI-M.2023-11.tif", "WAPOR-3.L1-AETI-M.2023-12.tif")
  terra::time(x) <- as.Date(c(NA, NA))

  intervals <- Rwapor:::.wapor_raster_intervals(x)
  expect_equal(intervals$start_date, c("2023-11-01", "2023-12-01"))
  expect_equal(intervals$metadata_source, c("layer_name", "layer_name"))
})

test_that("unknown raster dates remain unknown rather than inferred from stack length", {
  skip_if_not_installed("terra")
  x <- terra::rast(nrows = 1, ncols = 1, vals = 1)
  x <- c(x, x, x)
  names(x) <- c("band_a", "band_b", "band_c")

  intervals <- Rwapor:::.wapor_raster_intervals(x)
  expect_equal(nrow(intervals), 3L)
  expect_true(all(is.na(intervals$start_date)))
  expect_true(all(is.na(intervals$end_date)))
  expect_true(all(is.na(intervals$temporal_code)))
  expect_equal(intervals$metadata_source, rep("unknown", 3))
})

test_that("provenance constructor returns a JSON-safe versioned record", {
  intervals <- data.frame(
    layer = 1L,
    start_date = "2023-01-01",
    end_date = "2023-01-31",
    temporal_code = "M",
    metadata_source = "layer_name",
    stringsAsFactors = FALSE
  )
  provenance <- Rwapor:::.wapor_new_provenance(
    variable = "L1-AETI-M",
    intervals = intervals,
    units = "mm/month",
    value_semantics = "depth_per_interval",
    source = "C:/private/farm/WAPOR-3.L1-AETI-M.2023-01.tif",
    operation = "monthly_source"
  )

  expect_s3_class(provenance, "wapor_provenance")
  expect_equal(provenance$schema_version, 1L)
  expect_equal(provenance$variable, "L1-AETI-M")
  expect_equal(provenance$temporal_resolution, "M")
  expect_equal(provenance$period, list(start = "2023-01-01", end = "2023-01-31"))
  expect_true(is.character(provenance$dataset_id) && nzchar(provenance$dataset_id))
  expect_false(grepl("C:/private/farm", jsonlite::toJSON(provenance, auto_unbox = TRUE)))
  expect_true(jsonlite::validate(jsonlite::toJSON(provenance, auto_unbox = TRUE)))
})
