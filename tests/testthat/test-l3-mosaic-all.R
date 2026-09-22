# Network guard: skip when WaPOR API is not reachable (CI offline, air-gapped)
skip_if_wapor_offline()

test_that("wapor_map mosaic_all accepts multiple variables and periods", {
  skip_if_not_installed("terra")

  left <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2,
                      crs = "EPSG:4326", vals = 1)
  right <- terra::rast(nrows = 2, ncols = 2, xmin = 2, xmax = 4, ymin = 0, ymax = 2,
                       crs = "EPSG:4326", vals = 2)
  out_dir <- tempfile("rwapor-map-mosaic-")
  dir.create(out_dir)
  on.exit(unlink(out_dir, recursive = TRUE, force = TRUE), add = TRUE)

  local_mocked_bindings(
    wapor_guess_region = function(...) c("AAA", "BBB"),
    wapor_map = function(region, variable, period, folder, filename = NULL,
                         separate_files = FALSE, unit_conversion = NULL,
                         seasonal = FALSE, mask = FALSE, parallel = FALSE,
                         batching = TRUE, batch_size = 12L,
                         l3_region = NULL, l3_mode = c("select", "mosaic_all"),
                         partial = FALSE, cog = FALSE, fun = NULL) {
      path <- file.path(folder, sprintf("%s_%s.tif", variable, l3_region))
      dir.create(folder, recursive = TRUE, showWarnings = FALSE)
      r <- if (identical(l3_region, "AAA")) left else right
      terra::writeRaster(r, path, overwrite = TRUE)
      path
    },
    .package = "Rwapor"
  )

  result <- wapor_map_mosaic_all(
    region = c(0, 0, 4, 2),
    variable = c("L3-AETI-D", "L3-NPP-D"),
    period = list(c("2023-01-01", "2023-01-10"), c("2023-02-01", "2023-02-10")),
    folder = out_dir
  )

  expect_true(is.list(result))
  expect_true(length(result) >= 2L)
  expect_true(all(vapply(result, function(x) file.exists(x$cog_path), logical(1))))
})

test_that("wapor_ts mosaic_all extracts from every intersecting L3 source", {
  local_mocked_bindings(
    wapor_guess_region = function(...) c("AAA", "BBB"),
    wapor_ts = function(region, variable, period, identifier = NULL,
                        unit_conversion = NULL, seasonal = FALSE,
                        download_locally = FALSE, parallel = FALSE,
                        batching = TRUE, batch_size = 12L,
                        l3_region = NULL, l3_mode = c("select", "mosaic_all"),
                        partial = FALSE, fun = NULL) {
      data.frame(
        date = as.Date("2023-01-01"),
        value = if (identical(l3_region, "AAA")) 1 else 2,
        l3_region = l3_region,
        stringsAsFactors = FALSE
      )
    },
    .package = "Rwapor"
  )

  result <- wapor_ts_mosaic_all(
    region = c(0, 0, 4, 2),
    variable = "L3-AETI-D",
    period = c("2023-01-01", "2023-01-10")
  )

  expect_true(is.data.frame(result))
  expect_true("l3_region" %in% names(result))
  expect_equal(sort(unique(result$l3_region)), c("AAA", "BBB"))
})

test_that("Shiny L3 policy never preselects the first of several codes", {
  expect_equal(
    wapor_shiny_l3_selection(c("AAA", "BBB"), current = NULL),
    ""
  )
  expect_equal(
    wapor_shiny_l3_selection(c("AAA"), current = NULL),
    "AAA"
  )
  expect_true("Mosaic all intersecting L3 regions" %in% names(wapor_shiny_l3_choices(c("AAA", "BBB"))))
})
