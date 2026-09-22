testthat::test_that("normalization keeps level and temporal resolution separate", {
  item <- list(
    code = "L3-AETI-D",
    caption = "Actual evapotranspiration (Irrigation scheme - Dekadal - 20 m)",
    measureCaption = "Actual EvapoTranspiration and Interception",
    measureUnit = "mm/day",
    scale = 0.1
  )

  meta <- Rwapor:::.normalize_metadata_item(item, source = "api")

  testthat::expect_identical(meta$level, "L3")
  testthat::expect_identical(meta$temporal_resolution, "D")
  testthat::expect_identical(meta$spatial_resolution, "20 m")
  testthat::expect_false(identical(meta$spatial_resolution, meta$temporal_resolution))
  testthat::expect_identical(meta$units, "mm/day")
})

testthat::test_that("catalog filtering excludes non-core products by exact level", {
  items <- list(
    list(code = "L1-AETI-D", measureUnit = "mm/day", scale = 0.1),
    list(code = "L1-UTM-AETI-D", measureUnit = "mm/day", scale = 0.1),
    list(code = "L1-QUAL-LST-D", measureUnit = "K", scale = 0.01),
    list(code = "L2-AETI-D", measureUnit = "mm/day", scale = 0.1),
    list(code = "L3-AETI-D", measureUnit = "mm/day", scale = 0.1)
  )

  result <- Rwapor:::.normalize_metadata_items(items, "L1")

  testthat::expect_length(result, 1)
  testthat::expect_identical(result[[1]]$code, "L1-AETI-D")
  testthat::expect_true(all(vapply(result, function(x) x$level == "L1", logical(1))))
  testthat::expect_identical(result[[1]]$temporal_resolution, "D")
})

testthat::test_that("variable lookup uses the validated catalogue before static fallback", {
  testthat::local_mocked_bindings(
    .load_metadata_catalog = function(level = "all") {
      data.frame(
        code = "L1-AETI-D", long_name = "Catalogue name", units = "mm/day",
        scale = 0.25, temporal_resolution = "D", spatial_resolution = "300 m",
        spatial_extent = I(list(NULL)), level = "L1", source = "cache",
        stringsAsFactors = FALSE
      )
    },
    .package = "Rwapor"
  )

  meta <- Rwapor:::get_variable_metadata_internal("L1-AETI-D")

  testthat::expect_identical(meta$long_name, "Catalogue name")
  testthat::expect_identical(meta$scale, 0.25)
  testthat::expect_identical(meta$source, "cache")
})

testthat::test_that("fallback metadata preserves requested and resolved codes", {
  testthat::local_mocked_bindings(
    .load_metadata_catalog = function(level = "all") {
      data.frame(
        code = character(), long_name = character(), units = character(),
        scale = numeric(), temporal_resolution = character(),
        spatial_resolution = character(), spatial_extent = I(list()),
        level = character(), source = character(), stringsAsFactors = FALSE
      )
    },
    .fetch_metadata_api_variable = function(variable) NULL,
    .package = "Rwapor"
  )

  meta <- Rwapor:::get_variable_metadata_internal("L3-RET-D")

  testthat::expect_identical(meta$requested_code, "L3-RET-D")
  testthat::expect_identical(meta$resolved_code, "L1-RET-D")
  testthat::expect_true(isTRUE(meta$fallback_used))
  testthat::expect_identical(meta$level, "L1")
})

testthat::test_that("resolution keys use cached spatial metadata without temporal confusion", {
  testthat::expect_identical(Rwapor:::wapor_res_key("L3-AETI-D"), "L3_20m")
  testthat::expect_identical(Rwapor:::wapor_res_key("L3-AETI-E"), "L3_10m")
  testthat::expect_identical(Rwapor:::wapor_res_key("L1-AETI-D"), "L1_300m")
  testthat::expect_identical(Rwapor:::wapor_res_key("L1-RET-D"), "L1_30000m")
})

testthat::test_that("invalid metadata cannot replace an existing cache file", {
  td <- tempfile("metadata-atomic-")
  dir.create(td)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)
  path <- file.path(td, "wapor_L1.json")
  writeLines("original", path)

  testthat::local_mocked_bindings(
    .fetch_all_pages = function(...) list(),
    .package = "Rwapor"
  )

  testthat::expect_warning(
    Rwapor::wapor_update_metadata("L1", dest = td),
    "No valid metadata records"
  )
  testthat::expect_identical(readLines(path), "original")
})

testthat::test_that("temporal availability comes from cache and can be region-filtered", {
  testthat::expect_identical(Rwapor:::wapor_temporal_codes("L3-AETI-E"), c("A", "M", "D", "E"))

  testthat::local_mocked_bindings(
    wapor_generate_urls = function(variable, l3_region = NULL, period = NULL) {
      if (variable == "L3-AETI-D" && identical(l3_region, "AWA")) "url" else character()
    },
    .package = "Rwapor"
  )
  testthat::expect_identical(
    Rwapor:::wapor_temporal_codes("L3-AETI-E", l3_region = "AWA",
                                   period = c("2023-01-01", "2023-01-10")),
    "D"
  )
})

testthat::test_that("catalog records expose numeric spatial resolution and product type", {
  catalog <- Rwapor:::.load_metadata_catalog("all")
  testthat::expect_true(all(c("spatial_resolution_m", "product_type") %in% names(catalog)))
  aeti <- catalog[catalog$code == "L1-AETI-D", , drop = FALSE]
  l3_daily <- catalog[catalog$code == "L3-AETI-E", , drop = FALSE]
  testthat::expect_identical(aeti$spatial_resolution_m, 300)
  testthat::expect_identical(aeti$product_type, "mapset")
  testthat::expect_identical(l3_daily$spatial_resolution_m, 10)
  testthat::expect_identical(l3_daily$product_type, "mosaicset")
})

testthat::test_that("bundled metadata has a valid manifest", {
  manifest_path <- Rwapor:::.get_metadata_path("wapor_metadata_manifest.json")
  testthat::expect_true(nzchar(manifest_path))
  manifest <- jsonlite::fromJSON(manifest_path)
  testthat::expect_identical(manifest$schema_version, 1L)
  testthat::expect_identical(manifest$levels$L1$records, 23L)
  testthat::expect_identical(manifest$levels$L2$records, 15L)
  testthat::expect_identical(manifest$levels$L3$records, 21L)
})

testthat::test_that("available variable discovery combines cache and AgERA5 fallback", {
  vars <- Rwapor::wapor_available_variables()
  testthat::expect_true(all(c("L1-AETI-D", "L3-AETI-E", "AGERA5-ET0-E") %in% vars))
  testthat::expect_error(Rwapor::wapor_available_variables(NA), "single logical")
  testthat::expect_false("AGERA5-ET0-E" %in% Rwapor::wapor_available_variables(FALSE))
})

testthat::test_that("static WaPOR metadata agrees with bundled JSON on shared codes", {
  catalog <- Rwapor:::.load_metadata_catalog("all")
  static <- Rwapor::WAPOR3_VARS
  shared <- intersect(names(static), catalog$code)
  testthat::expect_gt(length(shared), 0)
  for (code in shared) {
    row <- catalog[catalog$code == code, , drop = FALSE][1, ]
    testthat::expect_identical(as.character(static[[code]]$units), row$units)
    testthat::expect_equal(as.numeric(static[[code]]$scale), row$scale)
    testthat::expect_identical(strsplit(code, "-", fixed = TRUE)[[1]][1], row$level)
    testthat::expect_identical(tail(strsplit(code, "-", fixed = TRUE)[[1]], 1), row$temporal_resolution)
  }
})
