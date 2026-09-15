test_that("L3 mosaic writes a VRT, COG, and coverage manifest", {
  skip_if_not_installed("terra")

  out_dir <- tempfile("rwapor-l3-mosaic-")
  dir.create(out_dir)
  on.exit(unlink(out_dir, recursive = TRUE, force = TRUE), add = TRUE)

  left <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2,
                      crs = "EPSG:4326", vals = 1)
  right <- terra::rast(nrows = 2, ncols = 2, xmin = 2, xmax = 4, ymin = 0, ymax = 2,
                       crs = "EPSG:4326", vals = 2)
  left_path <- file.path(out_dir, "AAA.tif")
  right_path <- file.path(out_dir, "BBB.tif")
  terra::writeRaster(left, left_path, overwrite = TRUE)
  terra::writeRaster(right, right_path, overwrite = TRUE)

  result <- wapor_write_l3_mosaic(
    asset_paths = c(AAA = left_path, BBB = right_path),
    output_dir = out_dir,
    output_stem = "aeti_2023"
  )

  expect_true(file.exists(result$vrt_path))
  expect_true(file.exists(result$cog_path))
  expect_true(file.exists(result$manifest_path))
  expect_equal(result$coverage$l3_codes, c("AAA", "BBB"))
  expect_equal(terra::ncol(terra::rast(result$cog_path)), 4)
})
