# Tests for wapor_fetch_metadata() and wapor_update_metadata()

skip_if_not_installed("jsonlite")
skip_if_not_installed("withr")

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

#' Write small fixture JSON files for the given levels inside a directory
write_fixture_json <- function(dir, levels = c("L1", "L2", "L3")) {
  fixtures <- list(
    L1 = list(
      list(
        code = "L1-AETI-D",
        long_name = "Actual EvapoTranspiration and Interception",
        units = "mm/day",
        scale = 0.1,
        temporal_resolution = "D",
        spatial_extent = list(xmin = -30, xmax = 65, ymin = -40, ymax = 40),
        level = "L1"
      ),
      list(
        code = "L1-NPP-M",
        long_name = "Net Primary Production",
        units = "gC/m2/month",
        scale = 0.001,
        temporal_resolution = "M",
        spatial_extent = NULL,
        level = "L1"
      )
    ),
    L2 = list(
      list(
        code = "L2-AETI-A",
        long_name = "Actual EvapoTranspiration and Interception",
        units = "mm/year",
        scale = 0.1,
        temporal_resolution = "A",
        spatial_extent = list(xmin = 20, xmax = 55, ymin = -5, ymax = 38),
        level = "L2"
      )
    ),
    L3 = list(
      list(
        code = "L3-AETI-D",
        long_name = "Actual EvapoTranspiration and Interception",
        units = "mm/day",
        scale = 0.1,
        temporal_resolution = "D",
        spatial_extent = NULL,
        level = "L3"
      )
    )
  )

  for (lvl in levels) {
    jsonlite::write_json(
      fixtures[[lvl]],
      file.path(dir, sprintf("wapor_%s.json", lvl)),
      pretty = TRUE,
      auto_unbox = TRUE
    )
  }
  invisible(dir)
}

# ---------------------------------------------------------------------------
# 1. wapor_fetch_metadata("L1") returns expected data.frame
# ---------------------------------------------------------------------------

test_that("wapor_fetch_metadata('L1') returns data.frame with expected columns", {
  withr::with_tempdir({
    write_fixture_json(".", levels = "L1")

    # Redirect system.file() to the temp directory
    testthat::local_mocked_bindings(
      system.file = function(..., package = "") {
        # system.file("metadata", "wapor_L1.json", package = "Rwapor")
        args <- list(...)
        if (identical(package, "Rwapor") && length(args) >= 1 &&
            identical(args[[1]], "metadata")) {
          if (length(args) == 1) {
            return(".")     # the metadata dir itself
          }
          return(file.path(".", args[[2]]))
        }
        base::system.file(..., package = package)
      },
      .package = "Rwapor"
    )

    result <- wapor_fetch_metadata("L1")

    expect_s3_class(result, "data.frame")
    expect_named(
      result,
      c("code", "long_name", "units", "scale",
        "temporal_resolution", "spatial_extent", "level"),
      ignore.order = FALSE
    )
    expect_equal(nrow(result), 2L)
    expect_equal(result$level, c("L1", "L1"))
    expect_true("L1-AETI-D" %in% result$code)

    # spatial_extent is a list column; first entry should be a list, second NULL
    expect_type(result$spatial_extent, "list")
    expect_equal(result$spatial_extent[[1]]$xmin, -30)
    expect_null(result$spatial_extent[[2]])
  })
})

# ---------------------------------------------------------------------------
# 2. wapor_fetch_metadata("all") returns rows from all three levels
# ---------------------------------------------------------------------------

test_that("wapor_fetch_metadata('all') combines all three levels", {
  withr::with_tempdir({
    write_fixture_json(".", levels = c("L1", "L2", "L3"))

    testthat::local_mocked_bindings(
      system.file = function(..., package = "") {
        args <- list(...)
        if (identical(package, "Rwapor") && length(args) >= 1 &&
            identical(args[[1]], "metadata")) {
          if (length(args) == 1) return(".")
          return(file.path(".", args[[2]]))
        }
        base::system.file(..., package = package)
      },
      .package = "Rwapor"
    )

    result <- wapor_fetch_metadata("all")

    expect_s3_class(result, "data.frame")
    expect_setequal(result$level, c("L1", "L2", "L3"))
    # 2 L1 + 1 L2 + 1 L3 = 4 rows in the fixture
    expect_equal(nrow(result), 4L)
  })
})

# ---------------------------------------------------------------------------
# 3. wapor_fetch_metadata("L1") stops when file is missing
# ---------------------------------------------------------------------------

test_that("wapor_fetch_metadata stops with informative error when file missing", {
  testthat::local_mocked_bindings(
    system.file = function(..., package = "") {
      # Always return "" (file not found)
      ""
    },
    .package = "Rwapor"
  )

  expect_error(
    wapor_fetch_metadata("L1"),
    regexp = "wapor_L1.json"   # message must mention the file name
  )
})

# ---------------------------------------------------------------------------
# 4. wapor_update_metadata() warns and returns NULL invisibly on network error
# ---------------------------------------------------------------------------

test_that("wapor_update_metadata warns and returns NULL on network error", {
  withr::with_tempdir({
    dest <- "."

    testthat::local_mocked_bindings(
      req_perform = function(...) {
        stop("simulated network failure")
      },
      .package = "httr2"
    )

    result <- withCallingHandlers(
      wapor_update_metadata(level = "L1", dest = dest),
      warning = function(w) {
        # capture but re-signal so expect_warning below can see it
        invokeRestart("muffleWarning")
      }
    )

    # Should return invisibly without error; result is character(0) or NULL
    expect_true(is.null(result) || length(result) == 0)

    # No JSON file should have been written
    expect_false(file.exists(file.path(dest, "wapor_L1.json")))
  })
})

test_that("wapor_update_metadata issues a warning on network error", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(
      req_perform = function(...) {
        stop("simulated network failure")
      },
      .package = "httr2"
    )

    expect_warning(
      wapor_update_metadata(level = "L1", dest = "."),
      regexp = "Network error"
    )
  })
})
