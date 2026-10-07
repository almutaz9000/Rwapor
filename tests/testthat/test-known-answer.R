ka_dir <- function() testthat::test_path("fixtures", "known-answer")

ka_unstack <- function(case) {
  dst <- tempfile(paste0("ka-", case, "-")); dir.create(dst)
  for (f in list.files(file.path(ka_dir(), case), "^WAPOR-3\\..*\\.tif$", full.names = TRUE)) {
    v <- sub("^WAPOR-3\\.(.*)\\.[0-9-]+_[0-9-]+\\.tif$", "\\1", basename(f))
    wapor_unstack_map(f, folder = file.path(dst, v))
  }
  dst
}

ka_cases <- list(
  citrus = list(period = c("2024-03-01", "2025-02-28"),
    vars = list(aeti_var = "L3-AETI-D", t_var = "L3-T-D", ret_var = "L1-RET-D", precip_var = "L1-PCP-D"),
    ind = c("agg_aeti", "agg_t", "agg_ret", "agg_pcp", "agg_peff", "etc", "adequacy_etc",
            "adequacy_p95", "beneficial_fraction", "green_water", "blue_water"),
    cp = function() wapor_create_crop_params(class_value = 1L, crop_name = "Citrus",
      kc_ini = 0.70, kc_mid = 0.65, kc_end = 0.70, l_ini_days = 60L, l_mid_days = 120L,
      l_late_days = 95L, max_height_m = 4.0, region = "Mediterranean")),
  wheat = list(period = c("2023-11-01", "2024-05-31"),
    vars = list(aeti_var = "L3-AETI-D", t_var = "L3-T-D", npp_var = "L3-NPP-D",
                ret_var = "L1-RET-D", precip_var = "L1-PCP-D"),
    ind = c("agg_aeti", "agg_t", "agg_ret", "agg_pcp", "agg_peff", "etc", "adequacy_etc",
            "adequacy_p95", "beneficial_fraction", "green_water", "blue_water", "agg_npp",
            "agg_biomass_kg", "agg_biomass_t", "yield_npp", "cwp_bwp"),
    cp = function() wapor_custom_crop(base_crop = "Winter Wheat", class_value = 1L,
      crop_name = "Irrigated Winter Wheat", kc_ini = 0.35, kc_mid = 1.15, kc_end = 0.30,
      HI = 0.43, AOT = 0.75, fc = 1.0, MC = 0.15)))

ka_flatten <- function(x, prefix = "") {
  if (inherits(x, "SpatRaster")) return(stats::setNames(list(x), prefix))
  out <- list()
  if (is.list(x) && !is.data.frame(x)) for (n in names(x)) if (nzchar(n)) {
    out <- c(out, ka_flatten(x[[n]], if (nzchar(prefix)) paste0(prefix, "$", n) else n))
  }
  out
}

ka_run <- function(case, mode) {
  spec <- ka_cases[[case]]
  folder <- ka_unstack(case)
  mask <- terra::rast(file.path(ka_dir(), case, "crop_mask.tif")); names(mask) <- "crop_mask"
  config <- c(list(period = spec$period, data_source = "local", folder = folder,
                   use_crop_mask = TRUE, area_weighted = TRUE, keep_intermediates = FALSE,
                   indicators = spec$ind, output_dir = tempfile("ka-out-"), processing = mode), spec$vars)
  if (identical(mode, "tiled")) config$tile_size <- 7L
  suppressWarnings(suppressMessages(wapor_run_seasonal_analysis(config, spec$cp(), list(crop_mask = mask))))
}

ka_assert_golden <- function(case, mode) {
  golden <- utils::read.csv(file.path(ka_dir(), "golden.csv"), stringsAsFactors = FALSE)
  golden <- golden[golden$case == case, , drop = FALSE]
  flat <- ka_flatten(ka_run(case, mode))
  for (i in seq_len(nrow(golden))) {
    output <- golden$output[[i]]
    testthat::expect_true(output %in% names(flat), info = output)
    r <- flat[[output]]
    testthat::expect_equal(terra::nlyr(r), 1L, info = output)
    values <- terra::values(r)[, 1]
    values <- values[is.finite(values)]
    testthat::expect_equal(length(values), golden$n[[i]], info = output)
    testthat::expect_equal(mean(values), golden$mean[[i]], tolerance = 1e-6, info = output)
    testthat::expect_equal(min(values), golden$min[[i]], tolerance = 1e-6, info = output)
    testthat::expect_equal(max(values), golden$max[[i]], tolerance = 1e-6, info = output)
  }
  flat
}

for (case in names(ka_cases)) for (mode in c("memory", "stream", "tiled")) {
  testthat::test_that(sprintf("known answers: %s (%s)", case, mode), {
    if (!identical(mode, "memory")) testthat::skip_on_cran()
    flat <- ka_assert_golden(case, mode)
    if (identical(mode, "memory") && identical(case, "citrus")) {
      testthat::expect_equal(mean(terra::values(flat[["etc_by_class$1$etc_seasonal"]]), na.rm = TRUE),
                             1050.9293, tolerance = 1e-6)
    }
    if (identical(mode, "memory") && identical(case, "wheat")) {
      testthat::expect_equal(mean(terra::values(flat[["etc_by_class$1$etc_seasonal"]]), na.rm = TRUE),
                             466.8898, tolerance = 1e-6)
      testthat::expect_equal(mean(terra::values(flat[["yield_raster"]]), na.rm = TRUE),
                             5.0362, tolerance = 1e-4)
    }
  })
}
