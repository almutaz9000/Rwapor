test_that("wapor_export_netcdf writes a structured NetCDF cube from local GeoTIFFs", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("terra")
  skip_if_not_installed("withr")

  root <- withr::local_tempdir()
  var <- "L1-AETI-D"
  dir.create(file.path(root, var))
  dates <- as.Date(c("2023-01-01", "2023-01-11", "2023-01-21"))
  vals <- c(1.5, 2.5, 3.5)
  for (i in seq_along(dates)) {
    r <- terra::rast(
      nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4,
      crs = "EPSG:4326", vals = vals[i]
    )
    terra::units(r) <- "mm/day"
    terra::writeRaster(
      r,
      file.path(root, var, sprintf("WAPOR-3.%s.%s.tif", var, dates[i])),
      overwrite = TRUE
    )
  }

  out <- wapor_export_netcdf(root, var)
  expect_true(file.exists(out))
  expect_equal(basename(dirname(out)), var)
  expect_equal(basename(dirname(dirname(out))), "netcdf")
  expect_identical(basename(out), "L1-AETI-D.2023-01-01_2023-01-21.nc")

  cube <- terra::rast(out)
  expect_equal(terra::nlyr(cube), 3L)
  expect_equal(as.Date(terra::time(cube)), dates)
  expect_equal(
    as.numeric(terra::global(cube, "mean", na.rm = TRUE)[, 1]),
    vals,
    tolerance = 1e-6
  )
})

test_that("wapor_export_netcdf carries the correct units attribute", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("terra")
  skip_if_not_installed("withr")

  root <- withr::local_tempdir()
  var <- "L1-AETI-D"
  dir.create(file.path(root, var))
  r <- terra::rast(nrows = 2, ncols = 2, crs = "EPSG:4326", vals = 1.0)
  terra::units(r) <- "mm/day"
  terra::writeRaster(r, file.path(root, var, "WAPOR-3.L1-AETI-D.2023-01-01.tif"), overwrite = TRUE)
  out <- wapor_export_netcdf(root, var)
  nc <- ncdf4::nc_open(out)
  on.exit(ncdf4::nc_close(nc), add = TRUE)
  v <- nc$var[[grep("L1|AETI", names(nc$var), value = TRUE)[1]]]
  expect_true(!is.null(v))
  expect_equal(v$units, "mm/day")
})

test_that("wapor_export_netcdf writes CF attributes and time_bnds", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("terra")
  skip_if_not_installed("withr")

  root <- withr::local_tempdir()
  var <- "L1-AETI-D"
  dir.create(file.path(root, var))
  r <- terra::rast(nrows = 2, ncols = 2, crs = "EPSG:4326", vals = 5.0)
  for (d in c("2023-01-01", "2023-01-21")) {
    terra::writeRaster(
      r, file.path(root, var, sprintf("WAPOR-3.%s.%s.tif", var, d)), overwrite = TRUE
    )
  }
  out <- wapor_export_netcdf(root, var, add_time_bounds = TRUE)
  nc <- ncdf4::nc_open(out)
  on.exit(ncdf4::nc_close(nc), add = TRUE)

  atts <- ncdf4::ncatt_get(nc, 0)
  expect_equal(atts$Conventions, "CF-1.6")
  expect_equal(atts$source, "FAO WaPOR v3")
  expect_true(!is.null(atts$institution))
  expect_true(!is.null(atts$created_by))

  expect_true("time_bnds" %in% names(nc$var))
  bnds <- ncdf4::ncvar_get(nc, "time_bnds")
  # 2 rows x 2 times; each row is start/end day-offset
  expect_equal(dim(bnds), c(2L, 2L))
  # start of first dekad is before its end
  expect_lt(bnds[1, 1], bnds[2, 1])
  # last dekad (Jan 21) ends on Jan 31
  epoch <- as.Date("1970-01-01")
  expected_end <- as.numeric(as.Date("2023-01-31") - epoch)
  expect_equal(bnds[2, 2], expected_end, tolerance = 0.5)
})

test_that("wapor_export_netcdf respects period filter", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("terra")
  skip_if_not_installed("withr")

  root <- withr::local_tempdir()
  var <- "L1-AETI-D"
  dir.create(file.path(root, var))
  r <- terra::rast(nrows = 2, ncols = 2, crs = "EPSG:4326", vals = 1.0)
  for (d in c("2023-01-01", "2023-01-11", "2023-01-21", "2023-02-01")) {
    terra::writeRaster(
      r, file.path(root, var, sprintf("WAPOR-3.%s.%s.tif", var, d)), overwrite = TRUE
    )
  }
  out <- wapor_export_netcdf(root, var, period = c("2023-01-01", "2023-01-31"))
  cube <- terra::rast(out)
  expect_equal(terra::nlyr(cube), 3L)
  expect_true(all(as.Date(terra::time(cube)) <= as.Date("2023-01-31")))
})

test_that("wapor_export_netcdf refuses to overwrite without flag", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("terra")
  skip_if_not_installed("withr")

  root <- withr::local_tempdir()
  var <- "L1-AETI-D"
  dir.create(file.path(root, var))
  r <- terra::rast(nrows = 2, ncols = 2, crs = "EPSG:4326", vals = 1.0)
  terra::writeRaster(r, file.path(root, var, "WAPOR-3.L1-AETI-D.2023-01-01.tif"), overwrite = TRUE)

  wapor_export_netcdf(root, var)
  expect_error(wapor_export_netcdf(root, var), "overwrite")
  expect_no_error(wapor_export_netcdf(root, var, overwrite = TRUE))
})

test_that("wapor_export_netcdf produces a cube readable by wapor_local_rasters via its TIF cache", {
  # The NC file does NOT replace the TIF cache; both coexist.
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("terra")
  skip_if_not_installed("withr")

  root <- withr::local_tempdir()
  var <- "L1-AETI-D"
  dir.create(file.path(root, var))
  r <- terra::rast(nrows = 3, ncols = 3, crs = "EPSG:4326",
                   xmin = 35, xmax = 36, ymin = 32, ymax = 33, vals = 2.0)
  dates <- c("2023-01-01", "2023-01-11", "2023-01-21")
  tif_paths <- file.path(root, var, sprintf("WAPOR-3.%s.%s.tif", var, dates))
  for (p in tif_paths) terra::writeRaster(r, p, overwrite = TRUE)

  nc_path <- wapor_export_netcdf(root, var)

  # TIF cache still intact
  local_paths <- wapor_local_rasters(root, var, "2023-01-01", "2023-01-31")
  expect_equal(length(local_paths), 3L)

  # NC is readable and values match TIF
  nc_stack <- terra::rast(nc_path)
  tif_stack <- terra::rast(tif_paths)
  expect_equal(terra::nlyr(nc_stack), terra::nlyr(tif_stack))
  nc_means  <- as.numeric(terra::global(nc_stack,  "mean", na.rm = TRUE)[, 1])
  tif_means <- as.numeric(terra::global(tif_stack, "mean", na.rm = TRUE)[, 1])
  expect_equal(nc_means, tif_means, tolerance = 1e-5)
})

test_that("wapor_export_netcdf raises informative errors on bad input", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("terra")
  expect_error(wapor_export_netcdf("", "L1-AETI-D"), "'folder'")
  expect_error(wapor_export_netcdf(tempdir(), ""), "'variable'")
  expect_error(wapor_export_netcdf(tempdir(), "L1-AETI-D"), "No GeoTIFF files found")
})
