test_that("remote operation retry covers a forced operation", {
  attempts <- 0L
  result <- Rwapor:::.wapor_retry_remote_operation(
    function() {
      attempts <<- attempts + 1L
      if (attempts < 3L) stop("transient pixel read")
      "read complete"
    },
    label = "fixture crop",
    max_retries = 3L,
    retry_delay = 0
  )
  expect_identical(result, "read complete")
  expect_equal(attempts, 3L)
})

test_that("remote operation retry reports the final error", {
  attempts <- 0L
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(
      function() {
        attempts <<- attempts + 1L
        stop("persistent pixel read")
      },
      label = "fixture extraction",
      max_retries = 2L,
      retry_delay = 0
    ),
    "fixture extraction failed after 2 attempt\\(s\\): persistent pixel read"
  )
  expect_equal(attempts, 2L)
})

test_that("remote operation retry validates its controls", {
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(NULL),
    "operation.*function"
  )
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(identity, max_retries = 0),
    "max_retries.*positive"
  )
  expect_error(
    Rwapor:::.wapor_retry_remote_operation(identity, retry_delay = -1),
    "retry_delay.*non-negative"
  )
})

test_that("datatype probing reads a bounded leading window", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 2000, ncols = 20, vals = 1)
  expect_identical(Rwapor:::.wapor_probe_datatype(r), "INT4U")
})

test_that("datatype probing does not truncate floats hidden below integer rows", {
  skip_if_not_installed("terra")
  # Top rows are exact zeros (e.g. a masked edge); fractional values below.
  vals <- c(rep(0, 20000), seq(0.01, 4.99, length.out = 980000))
  r <- terra::rast(nrows = 1000, ncols = 1000, vals = vals)
  expect_identical(Rwapor:::.wapor_probe_datatype(r), "FLT4S")

  # A later layer with fractional values must also force a float type.
  r2 <- c(terra::rast(nrows = 50, ncols = 50, vals = 1),
          terra::rast(nrows = 50, ncols = 50, vals = 0.5))
  expect_identical(Rwapor:::.wapor_probe_datatype(r2), "FLT4S")
})
