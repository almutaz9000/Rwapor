make_test_provenance <- function(period = list(start = "2023-01-01", end = "2023-01-31"),
                                 temporal_resolution = "M",
                                 intervals = NULL,
                                 units = "mm",
                                 value_semantics = "depth_per_interval",
                                 grid = list(nrow = 2L, ncol = 2L, res = c(1, 1), extent = c(0, 0, 2, 2), crs = "EPSG:4326"),
                                 coverage = list(complete = TRUE),
                                 season_definition = list(id = "season-2023")) {
  if (is.null(intervals)) {
    starts <- period$start
    ends <- period$end
    if (is.null(starts) || is.null(ends)) {
      starts <- ends <- NA_character_
    }
    intervals <- data.frame(
      layer = 1L, start_date = starts, end_date = ends,
      temporal_code = temporal_resolution, metadata_source = "test",
      stringsAsFactors = FALSE
    )
  }
  Rwapor:::.wapor_new_provenance(
    variable = paste0("L1-AETI-", temporal_resolution),
    intervals = intervals,
    period = period,
    units = units,
    value_semantics = value_semantics,
    grid = grid,
    coverage = coverage,
    season_definition = season_definition
  )
}

test_that("validator derives temporal and grid metadata from raster inputs", {
  skip_if_not_installed("terra")
  aeti <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2,
                      crs = "EPSG:4326", vals = 1)
  names(aeti) <- "WAPOR-3.L1-AETI-M.2023-01.tif"
  biomass <- aeti
  report <- wapor_validate_compatibility(list(aeti = aeti, biomass = biomass), operation = "same_period")
  expect_equal(report$status, "passed")

  shifted <- terra::rast(nrows = 2, ncols = 2, xmin = 1, xmax = 3, ymin = 0, ymax = 2,
                         crs = "EPSG:4326", vals = 1)
  names(shifted) <- "WAPOR-3.L1-AETI-M.2023-01.tif"
  report_grid <- wapor_validate_compatibility(list(aeti = aeti, biomass = shifted), operation = "same_period")
  expect_equal(report_grid$status, "failed")
  expect_match(paste(report_grid$errors, collapse = " "), "grid")
})

test_that("raster content signatures distinguish season masks on the same grid", {
  skip_if_not_installed("terra")
  mask_a <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2, vals = c(1, 1, 2, 2))
  mask_b <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2, vals = c(1, 2, 2, 2))
  signature_a <- Rwapor:::.wapor_raster_content_signature(mask_a)
  signature_a_copy <- Rwapor:::.wapor_raster_content_signature(mask_a)
  signature_b <- Rwapor:::.wapor_raster_content_signature(mask_b)

  expect_equal(signature_a, signature_a_copy)
  expect_false(identical(signature_a$content_digest, signature_b$content_digest))
  expect_identical(signature_a$grid, signature_b$grid)

  aeti <- make_test_provenance(units = "mm", season_definition = list(
    id = "2023", masks = list(season_end = signature_a)
  ))
  biomass <- make_test_provenance(units = "t/ha", season_definition = list(
    id = "2023", masks = list(season_end = signature_b)
  ))
  report <- wapor_validate_compatibility(
    list(aeti = aeti, biomass = biomass), operation = "water_productivity"
  )
  expect_equal(report$status, "failed")
  expect_match(paste(report$errors, collapse = " "), "Season-definition lineage differs")
})

test_that("same-period ratio accepts compatible inputs at different source resolutions", {
  dekadal_period <- make_test_provenance(
    temporal_resolution = "D", units = "kg/ha",
    intervals = data.frame(
      layer = 1:3,
      start_date = c("2023-01-01", "2023-01-11", "2023-01-21"),
      end_date = c("2023-01-10", "2023-01-20", "2023-01-31"),
      temporal_code = "D", metadata_source = "test"
    )
  )
  monthly_period <- make_test_provenance(
    temporal_resolution = "M", units = "mm",
    intervals = data.frame(
      layer = 1L, start_date = "2023-01-01", end_date = "2023-01-31",
      temporal_code = "M", metadata_source = "test"
    )
  )

  report <- wapor_validate_compatibility(
    list(yield = dekadal_period, water = monthly_period),
    operation = "ratio"
  )
  expect_equal(report$status, "passed")
  expect_length(report$errors, 0L)
})

test_that("known analysis-period mismatch fails in warn and strict modes", {
  a <- make_test_provenance()
  b <- make_test_provenance(period = list(start = "2023-02-01", end = "2023-02-28"))

  report_warn <- wapor_validate_compatibility(list(aeti = a, biomass = b), operation = "ratio")
  report_strict <- wapor_validate_compatibility(
    list(aeti = a, biomass = b), operation = "ratio", mode = "strict"
  )
  expect_equal(report_warn$status, "failed")
  expect_equal(report_strict$status, "failed")
  expect_match(paste(report_warn$errors, collapse = " "), "2023-01-01.*2023-02-01")
})

test_that("time-series contract rejects reordered intervals", {
  a <- make_test_provenance(
    period = list(start = "2023-01-01", end = "2023-02-28"),
    intervals = data.frame(
      layer = 1:2,
      start_date = c("2023-01-01", "2023-02-01"),
      end_date = c("2023-01-31", "2023-02-28"),
      temporal_code = "M", metadata_source = "test"
    )
  )
  b <- make_test_provenance(
    period = list(start = "2023-01-01", end = "2023-02-28"),
    intervals = data.frame(
      layer = 1:2,
      start_date = c("2023-02-01", "2023-01-01"),
      end_date = c("2023-02-28", "2023-01-31"),
      temporal_code = "M", metadata_source = "test"
    )
  )

  report <- wapor_validate_compatibility(list(a = a, b = b), operation = "time_series")
  expect_equal(report$status, "failed")
  expect_match(paste(report$errors, collapse = " "), "interval")
})

test_that("grid mismatches fail while missing grids warn by default", {
  a <- make_test_provenance()
  b <- make_test_provenance(grid = list(nrow = 2L, ncol = 2L, res = c(1, 1), extent = c(0, 0, 2, 2), crs = "EPSG:32636"))
  mismatch <- wapor_validate_compatibility(list(a = a, b = b), operation = "same_period")
  expect_equal(mismatch$status, "failed")
  expect_match(paste(mismatch$errors, collapse = " "), "grid")

  unknown <- make_test_provenance(grid = NULL)
  expect_warning(
    wapor_validate_compatibility(list(a = a, b = unknown), operation = "same_period"),
    "[Gg]rid.*unknown"
  )
  warned <- suppressWarnings(wapor_validate_compatibility(
    list(a = a, b = unknown), operation = "same_period"
  ))
  expect_equal(warned$status, "warning")
})

test_that("add requires equal known units and ratio requires recognized units", {
  a <- make_test_provenance(units = "mm")
  depth_rate <- make_test_provenance(units = "mm/day")
  unequal_add <- wapor_validate_compatibility(list(a = a, b = depth_rate), operation = "add")
  expect_equal(unequal_add$status, "failed")
  expect_match(paste(unequal_add$errors, collapse = " "), "unit")

  ratio <- wapor_validate_compatibility(
    list(yield = make_test_provenance(units = "t/ha"), water = a),
    operation = "ratio"
  )
  expect_equal(ratio$status, "passed")

  unknown_unit <- make_test_provenance(units = "widgets")
  expect_warning(
    wapor_validate_compatibility(list(a = a, b = unknown_unit), operation = "ratio"),
    "unit.*unrecognized"
  )
  unknown <- suppressWarnings(wapor_validate_compatibility(
    list(a = a, b = unknown_unit), operation = "ratio"
  ))
  expect_equal(unknown$status, "warning")
})

test_that("water-productivity contract checks mass-per-area against water depth", {
  valid <- wapor_validate_compatibility(
    list(yield = make_test_provenance(units = "t/ha"), aeti = make_test_provenance(units = "mm")),
    operation = "water_productivity"
  )
  expect_equal(valid$status, "passed")

  invalid <- wapor_validate_compatibility(
    list(yield = make_test_provenance(units = "mm"), aeti = make_test_provenance(units = "kg/m3")),
    operation = "water_productivity"
  )
  expect_equal(invalid$status, "failed")
  expect_match(paste(invalid$errors, collapse = " "), "mass_per_area.*water_depth")
})

test_that("strict mode turns unknown required metadata into errors", {
  a <- make_test_provenance(period = list(start = NULL, end = NULL), grid = NULL, units = NULL)
  b <- make_test_provenance(period = list(start = NULL, end = NULL), grid = NULL, units = NULL)

  report <- wapor_validate_compatibility(list(a = a, b = b), operation = "ratio", mode = "strict")
  expect_equal(report$status, "failed")
  expect_gte(length(report$errors), 1L)
})

test_that("complete-series contract rejects known incomplete coverage", {
  a <- make_test_provenance(coverage = list(complete = TRUE))
  b <- make_test_provenance(coverage = list(complete = FALSE))

  report <- wapor_validate_compatibility(list(a = a, b = b), operation = "complete_series")
  expect_equal(report$status, "failed")
  expect_match(paste(report$errors, collapse = " "), "coverage")
})
