# Rwapor live release checks
# =============================================================================
# Checks against the live WaPOR API that a release must pass before it is
# merged or tagged (see docs/superpowers/plans/2026-09-28-production-readiness-plan.md):
#
#   1. wapor_map() output equals the raw COG value x file scale (unit
#      conversion "none") and x days per dekad (default), read independently
#      from the same remote files, for L1 and for L3 (region JVA).
#   2. A seasonal analysis streamed from the API equals the same analysis on
#      files downloaded with wapor_map(separate_files = TRUE).
#   3. The dashboard's download confirmation (file.exists(unlist(result)))
#      passes for single-file and separate-file downloads.
#   4. run_wapor() fetches the L3 region list from the API and serves HTTP 200.
#
# Usage: Rscript live_release_checks.R [pkg_path]
# Needs internet access. Exits with status 1 when any check fails.

args <- commandArgs(trailingOnly = TRUE)
pkg_path <- if (length(args) && nzchar(args[1])) args[1] else NA_character_
if (!is.na(pkg_path)) {
  pkgload::load_all(pkg_path, quiet = TRUE)
} else {
  library(Rwapor)
}

results <- list()
check <- function(name, expr) {
  t0 <- proc.time()[["elapsed"]]
  out <- tryCatch(list(status = "PASS", detail = force(expr)),
                  error = function(e) list(status = "FAIL", detail = conditionMessage(e)))
  out$seconds <- proc.time()[["elapsed"]] - t0
  results[[name]] <<- out
  cat(sprintf("[%s] %-58s %6.1fs  %s\n", out$status, name, out$seconds,
              paste(out$detail, collapse = " ")))
  invisible(out)
}

# Small areas: Bekaa valley (L1) and the North Jordan Valley (L3 region JVA).
l1_box <- c(35.95, 33.80, 36.00, 33.85)
jva_box <- c(35.58, 32.40, 35.60, 32.42)
dekad <- c("2024-06-01", "2024-06-10")  # one dekad, D1 = 10 days

# Read the remote COG independently: raw stored integers and the file scale.
raw_reference <- function(variable, box, l3 = NULL) {
  url <- wapor_generate_urls(variable, l3_region = l3, period = dekad)
  stopifnot(length(url) == 1L)
  r <- terra::rast(paste0("/vsicurl/", url))
  so <- terra::scoff(r)
  terra::scoff(r) <- cbind(1, 0)
  aoi <- terra::project(terra::vect(terra::ext(box[c(1, 3, 2, 4)]), crs = "EPSG:4326"), terra::crs(r))
  list(raw = terra::crop(r, aoi, snap = "out"), scale = so[1, "scale"], offset = so[1, "offset"])
}

map_equals_raw <- function(variable, box, l3 = NULL) {
  ref <- raw_reference(variable, box, l3)
  if (ref$scale == 1) stop("remote file has no scale; expected WaPOR Int16 with scale 0.1")
  expected <- terra::values(ref$raw)[, 1] * ref$scale + ref$offset
  run <- function(uc) {
    out <- suppressMessages(wapor_map(box, variable, dekad, tempfile("live-map-"),
                                      unit_conversion = uc, l3_region = l3))
    terra::values(terra::rast(out))[, 1]
  }
  none <- run("none")
  dekadal <- run(NULL)
  ok <- !is.na(expected)
  if (!any(ok)) stop("no valid pixels in the test box")
  d_none <- max(abs(none[ok] - expected[ok]))
  d_dekad <- max(abs(dekadal[ok] - expected[ok] * 10))
  if (d_none > 1e-4 || d_dekad > 1e-3) {
    stop(sprintf("scale mismatch: max |none - raw*scale| = %.4g, max |dekad - raw*scale*10| = %.4g",
                 d_none, d_dekad))
  }
  sprintf("scale %.3g; %d px; mean raw %.1f -> %.3f mm/day, %.2f mm/dekad; max diff %.1g / %.1g",
          ref$scale, sum(ok), mean(terra::values(ref$raw)[ok, 1]), mean(none[ok]),
          mean(dekadal[ok]), d_none, d_dekad)
}

check("L1-AETI-D map = raw COG x scale (x 10 days)", map_equals_raw("L1-AETI-D", l1_box))
check("L3-AETI-D (JVA) map = raw COG x scale (x 10 days)", map_equals_raw("L3-AETI-D", jva_box, "JVA"))

check("seasonal analysis: API stream equals local downloads", {
  period <- c("2024-06-01", "2024-06-30")
  folder <- tempfile("live-local-")
  for (v in c("L1-AETI-D", "L1-RET-D")) {
    suppressMessages(wapor_map(l1_box, v, period, folder, separate_files = TRUE))
  }
  cp <- data.frame(class_value = 1L, crop_label = "Crop", kc_ini = 0.5, kc_mid = 1.1, kc_end = 0.7,
                   l_ini_days = 10L, l_mid_days = 10L, l_late_days = 10L,
                   HI = 0.4, MC = 0.1, fc = 1, AOT = 1)
  run <- function(source) {
    cfg <- list(period = period, data_source = source, folder = folder,
                aeti_var = "L1-AETI-D", ret_var = "L1-RET-D",
                indicators = c("agg_aeti", "agg_ret", "etc", "adequacy_etc"),
                use_crop_mask = FALSE, use_season_rasters = FALSE,
                output_dir = tempfile(paste0("live-", source, "-")))
    suppressMessages(wapor_run_seasonal_analysis(cfg, cp, rasters = list(), aoi_region = l1_box))
  }
  api <- run("api")
  loc <- run("local")
  a <- terra::values(api$seasonal_aeti$raster)[, 1]
  b <- terra::values(loc$seasonal_aeti$raster)[, 1]
  d <- max(abs(a - b), na.rm = TRUE)
  if (!identical(is.na(a), is.na(b)) || d > 1e-3) stop(sprintf("API and local differ: max |diff| %.4g", d))
  sprintf("seasonal AETI mean %.2f mm (API) vs %.2f mm (local), max |diff| %.1g",
          mean(a, na.rm = TRUE), mean(b, na.rm = TRUE), d)
})

check("seasonal ETc = daily Kc x RET from raw COGs (season from 1 March)", {
  period <- c("2024-03-01", "2024-05-31")
  cp <- data.frame(class_value = 1L, crop_label = "Crop", kc_ini = 0.4, kc_mid = 1.2, kc_end = 0.6,
                   l_ini_days = 20L, l_mid_days = 30L, l_late_days = 20L,
                   HI = 0.4, MC = 0.1, fc = 1, AOT = 1)
  cfg <- list(period = period, data_source = "api", aeti_var = "L1-AETI-D", ret_var = "L1-RET-D",
              indicators = c("agg_aeti", "agg_ret", "etc", "adequacy_etc"),
              use_crop_mask = FALSE, use_season_rasters = FALSE,
              output_dir = tempfile("live-etc-"))
  api <- suppressMessages(wapor_run_seasonal_analysis(cfg, cp, rasters = list(), aoi_region = l1_box))

  dates <- seq(as.Date(period[1]), as.Date(period[2]), by = "day")
  ret_urls <- wapor_generate_urls("L1-RET-D", period = period)
  ret_daily <- rep(NA_real_, length(dates)); names(ret_daily) <- as.character(dates)
  for (url in ret_urls) {
    r <- terra::rast(paste0("/vsicurl/", url))
    so <- terra::scoff(r)
    terra::scoff(r) <- cbind(1, 0)
    aoi <- terra::project(terra::vect(terra::ext(l1_box[c(1, 3, 2, 4)]), crs = "EPSG:4326"), terra::crs(r))
    raw <- terra::crop(r, aoi, snap = "out")
    ret <- mean(terra::values(raw)[, 1], na.rm = TRUE) * so[1, "scale"] + so[1, "offset"]
    di <- wapor_date_info(url, "D")
    # Third dekads run to the month end (8 to 11 days), so use the real end date
    layer_dates <- seq(max(as.Date(di$start_date), dates[1]),
                       min(as.Date(di$end_date), dates[length(dates)]), by = "day")
    ret_daily[as.character(layer_dates)] <- ret
  }
  if (anyNA(ret_daily)) stop("raw RET COGs did not cover every day in the season")
  # FAO-56 piecewise-linear Kc: each linear stage starts one step after the previous value
  kc <- c(rep(cp$kc_ini, 20L), seq(cp$kc_ini, cp$kc_mid, length.out = 23L)[-1],
          rep(cp$kc_mid, 30L), seq(cp$kc_mid, cp$kc_end, length.out = 21L)[-1])
  etc_formula <- sum(kc * ret_daily)
  etc_raster <- api$etc_by_class[["1"]]$etc_seasonal
  etc_package <- mean(terra::values(etc_raster), na.rm = TRUE)
  if (abs(etc_package - etc_formula) / etc_formula > 1e-3) {
    stop(sprintf("ETc %.2f mm (package) vs %.2f mm (formula)", etc_package, etc_formula))
  }
  adequacy_package <- mean(terra::values(api$adequacy_etc), na.rm = TRUE)
  adequacy_formula <- mean(terra::values(api$seasonal_aeti$raster) / terra::values(etc_raster), na.rm = TRUE)
  if (!isTRUE(all.equal(adequacy_package, adequacy_formula, tolerance = 1e-6))) {
    stop(sprintf("adequacy %.6f (package) vs %.6f (formula)", adequacy_package, adequacy_formula))
  }
  sprintf("ETc %.2f mm (package) vs %.2f mm (formula); adequacy %.3f",
          etc_package, etc_formula, adequacy_package)
})

check("dashboard download confirmation (file.exists(unlist(result)))", {
  period <- c("2024-06-01", "2024-06-30")
  all_out_paths <- list()
  all_out_paths[["stack"]] <- suppressMessages(wapor_map(l1_box, "L1-AETI-D", period, tempfile("dash-")))
  all_out_paths[["separate"]] <- suppressMessages(
    wapor_map(l1_box, "L1-AETI-D", period, tempfile("dash-"), separate_files = TRUE)
  )
  flat_paths <- unlist(all_out_paths)
  if (length(flat_paths) == 0 || !all(file.exists(flat_paths))) {
    stop("dashboard would report 'expected files were not found'")
  }
  sprintf("%d file(s) found", length(flat_paths))
})

check("run_wapor(): live L3 list and HTTP 200", {
  if (!requireNamespace("callr", quietly = TRUE)) stop("callr is required")
  port <- 8799L
  log_file <- tempfile(fileext = ".log")
  app <- callr::r_bg(function(port, pkg_path) {
    if (!is.na(pkg_path)) pkgload::load_all(pkg_path, quiet = TRUE) else library(Rwapor)
    run_wapor(launch.browser = FALSE, port = port, host = "127.0.0.1")
  }, args = list(port = port, pkg_path = pkg_path), stdout = log_file, stderr = "2>&1")
  on.exit(app$kill(), add = TRUE)
  ok <- FALSE
  deadline <- Sys.time() + 180
  while (Sys.time() < deadline && app$is_alive()) {
    status <- tryCatch(httr2::req_perform(httr2::request(sprintf("http://127.0.0.1:%d/", port)))$status_code,
                       error = function(e) NA_integer_)
    if (identical(status, 200L)) { ok <- TRUE; break }
    Sys.sleep(2)
  }
  log <- readLines(log_file, warn = FALSE)
  if (!ok) stop("dashboard did not serve HTTP 200: ", paste(utils::tail(log, 10), collapse = " | "))
  if (any(grepl("built-in L3 region list", log))) stop("L3 regions fell back to the built-in list")
  n_l3 <- nrow(wapor_fetch_l3_regions(timeout = 30))
  sprintf("HTTP 200; L3 list from the API (%d regions)", n_l3)
})

n_fail <- sum(vapply(results, function(r) identical(r$status, "FAIL"), logical(1)))
cat(sprintf("\n%d live check(s), %d failed.\n", length(results), n_fail))
if (n_fail) quit(status = 1, save = "no")
