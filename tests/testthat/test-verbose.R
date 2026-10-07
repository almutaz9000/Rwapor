verbose_ka_dir <- function() testthat::test_path("fixtures", "known-answer")

verbose_ka_unstack <- function(case) {
  dst <- tempfile(paste0("verbose-ka-", case, "-")); dir.create(dst)
  for (f in list.files(file.path(verbose_ka_dir(), case), "^WAPOR-3\\..*\\.tif$", full.names = TRUE)) {
    v <- sub("^WAPOR-3\\.(.*)\\.[0-9-]+_[0-9-]+\\.tif$", "\\1", basename(f))
    wapor_unstack_map(f, folder = file.path(dst, v))
  }
  dst
}

test_that("verbose option controls progress messages", {
  old <- options(Rwapor.verbose = FALSE)
  on.exit(options(old), add = TRUE)
  expect_no_message(Rwapor:::log_msg("x"))
  expect_no_message(Rwapor:::.wapor_inform("x"))
  options(Rwapor.verbose = NULL)
  expect_message(Rwapor:::log_msg("x"), "x")
  expect_message(Rwapor:::.wapor_inform("x"), "x")
})

test_that("quiet seasonal analysis emits no progress messages", {
  old <- options(Rwapor.verbose = FALSE)
  on.exit(options(old), add = TRUE)
  folder <- verbose_ka_unstack("citrus")
  mask <- terra::rast(file.path(verbose_ka_dir(), "citrus", "crop_mask.tif")); names(mask) <- "crop_mask"
  config <- list(period = c("2024-03-01", "2025-02-28"), data_source = "local", folder = folder,
                 use_crop_mask = TRUE, area_weighted = TRUE, keep_intermediates = FALSE,
                 indicators = c("agg_aeti", "agg_ret", "etc"), output_dir = tempfile("verbose-ka-"),
                 processing = "memory", aeti_var = "L3-AETI-D", ret_var = "L1-RET-D")
  cp <- wapor_create_crop_params(class_value = 1L, crop_name = "Citrus",
    kc_ini = 0.70, kc_mid = 0.65, kc_end = 0.70, l_ini_days = 60L, l_mid_days = 120L,
    l_late_days = 95L, max_height_m = 4.0, region = "Mediterranean")
  expect_no_message(suppressWarnings(wapor_run_seasonal_analysis(config, cp, list(crop_mask = mask))))
})
