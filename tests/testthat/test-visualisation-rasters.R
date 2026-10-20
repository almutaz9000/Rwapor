test_that("seasonal path detector matches WaPOR download and analysis names", {
  expect_true(wapor_is_seasonal_raster_path(
    "L3-AETI-D_seasonal/WAPOR-3.L3-AETI-D.seasonal.2023-03-01_2024-02-28.tif"
  ))
  expect_true(wapor_is_seasonal_raster_path(
    "L1-AETI-D_seasonal/WAPOR-3.L1-AETI-D.seasonal.sum.Season_1.2023-01-01_2023-04-30.tif"
  ))
  expect_true(wapor_is_seasonal_raster_path(
    "season_2023/seasonal_rasters/scheme_seasonal_aeti.tif"
  ))
  expect_true(wapor_is_seasonal_raster_path(
    "L3-AETI-D_seasonal/components/seasonal_component_D.tif"
  ))
  expect_true(wapor_is_seasonal_raster_path(
    "downloads/WAPOR-3.L3-AETI-D.seasonal.2023-03-01_2024-02-28.tif"
  ))

  expect_false(wapor_is_seasonal_raster_path(
    "L3-AETI-D/WAPOR-3.L3-AETI-D.2018-01-01.tif"
  ))
  expect_false(wapor_is_seasonal_raster_path("season_start.tif"))
  expect_false(wapor_is_seasonal_raster_path("analysis/crop_mask.tif"))
})

test_that("visualisation listing includes every raster in the project folder", {
  root <- tempfile("vis-rasters-")
  dir.create(file.path(root, "L3-AETI-D"), recursive = TRUE)
  dir.create(file.path(root, "L3-AETI-D_seasonal"), recursive = TRUE)
  dir.create(file.path(root, "season_2023", "seasonal_rasters"), recursive = TRUE)

  files <- c(
    file.path(root, "L3-AETI-D", "WAPOR-3.L3-AETI-D.2018-01-01.tif"),
    file.path(root, "L3-AETI-D", "WAPOR-3.L3-AETI-D.2018-01-11.tif"),
    file.path(root, "L3-AETI-D_seasonal", "WAPOR-3.L3-AETI-D.seasonal.2018-01-01_2018-12-31.tif"),
    file.path(root, "season_2023", "seasonal_rasters", "scheme_seasonal_aeti.tif"),
    file.path(root, "notes.tiff")
  )
  file.create(files)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  all_files <- wapor_list_visualisation_rasters(root)
  expect_true(all(c(
    "L3-AETI-D/WAPOR-3.L3-AETI-D.2018-01-01.tif",
    "L3-AETI-D/WAPOR-3.L3-AETI-D.2018-01-11.tif",
    "L3-AETI-D_seasonal/WAPOR-3.L3-AETI-D.seasonal.2018-01-01_2018-12-31.tif",
    "season_2023/seasonal_rasters/scheme_seasonal_aeti.tif",
    "notes.tiff"
  ) %in% all_files))

  seasonal_only <- wapor_list_visualisation_rasters(root, only_seasonal = TRUE)
  expect_true("L3-AETI-D_seasonal/WAPOR-3.L3-AETI-D.seasonal.2018-01-01_2018-12-31.tif" %in% seasonal_only)
  expect_true("season_2023/seasonal_rasters/scheme_seasonal_aeti.tif" %in% seasonal_only)
  expect_false("L3-AETI-D/WAPOR-3.L3-AETI-D.2018-01-01.tif" %in% seasonal_only)
  expect_false("notes.tiff" %in% seasonal_only)
})

test_that("visualisation choices group files so seasonal folders stay visible", {
  root <- tempfile("vis-choices-")
  dir.create(file.path(root, "L3-AETI-D"), recursive = TRUE)
  dir.create(file.path(root, "L3-AETI-D_seasonal"), recursive = TRUE)
  file.create(file.path(root, "L3-AETI-D", "dekad.tif"))
  file.create(file.path(root, "L3-AETI-D_seasonal", "season.tif"))
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  choices <- wapor_visualisation_raster_choices(root)
  expect_type(choices, "list")
  expect_true("L3-AETI-D" %in% names(choices))
  expect_true("L3-AETI-D_seasonal" %in% names(choices))
  expect_equal(unname(choices[["L3-AETI-D_seasonal"]]), "L3-AETI-D_seasonal/season.tif")
})

test_that("overlay plan does not clear the map until a raster is ready", {
  expect_false(wapor_vis_overlay_ready("single", r1 = NULL))
  expect_true(wapor_vis_overlay_ready("single", r1 = TRUE))
  expect_false(wapor_vis_overlay_ready("dual", r1 = TRUE, r2 = NULL))
  expect_true(wapor_vis_overlay_ready("dual", r1 = TRUE, r2 = TRUE))
  expect_false(wapor_vis_overlay_ready("query", query = NULL))
  expect_true(wapor_vis_overlay_ready("query", query = list(success = TRUE, raster = TRUE)))

  expect_equal(
    wapor_vis_overlay_clear_groups("single"),
    c("raster", "raster1", "raster2", "raster_intersection", "raster_query")
  )
  expect_false("lyr_crop_mask" %in% wapor_vis_overlay_clear_groups("single"))
})

test_that("dual map sync waits until both maps have a zoom", {
  expect_false(wapor_dual_map_can_sync(TRUE, NULL, 3))
  expect_false(wapor_dual_map_can_sync(TRUE, 3, NULL))
  expect_false(wapor_dual_map_can_sync(FALSE, 3, 3))
  expect_true(wapor_dual_map_can_sync(TRUE, 3, 4))
  expect_false(wapor_dual_map_can_sync(TRUE, NA, 3))
})

test_that("dual map namespaced ids match leaflet DOM ids", {
  ns <- shiny::NS("vis-dual")
  ids <- wapor_dual_map_dom_ids(ns)
  expect_equal(unname(ids[["left"]]), "vis-dual-map_left")
  expect_equal(unname(ids[["right"]]), "vis-dual-map_right")
})

test_that("dual map module attaches sync after maps exist and does not poll then give up", {
  src_path <- testthat::test_path("..", "..", "inst", "shiny", "mod_dual_map.R")
  src <- paste(readLines(src_path), collapse = "\n")
  expect_match(src, "wapor_dual_map_can_sync")
  expect_match(src, "map_left_zoom")
  expect_match(src, "map_right_zoom")
  expect_false(grepl("attempts > 30", src, fixed = TRUE))
})

test_that("visualisation module lists with the helper and does not blank the map first", {
  src_path <- testthat::test_path("..", "..", "inst", "shiny", "mod_visualisation.R")
  src <- paste(readLines(src_path), collapse = "\n")
  expect_match(src, "wapor_visualisation_raster_choices")
  expect_match(src, "wapor_vis_overlay_ready")
  expect_false(grepl("clearImages", src, fixed = TRUE))
  expect_match(src, "isolate\\(input\\$raster_file\\)")
})
