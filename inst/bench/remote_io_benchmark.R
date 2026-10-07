# Rwapor remote I/O benchmark
# =============================================================================
# Measures what a polygon time series costs on the network: seconds, HTTP
# requests, failed side-file requests (404) and megabytes requested. Runs
# wapor_ts() for 150 farm-size polygons and 36 dekads, at Level 3 (small files,
# one per region) and Level 2 (global files), each in a fresh R process:
#
#   package  the settings this version of Rwapor applies
#   old      the settings of Rwapor <= 1.0.5 (10 MB HTTP chunk, no extension
#            filter), for comparison
#
# Usage:
#   Rscript remote_io_benchmark.R [pkg_path] [--no-old]
#
#   pkg_path  Optional package source to load with pkgload (default: the
#             installed Rwapor).
#   --no-old  Skip the comparison runs (the Level 2 one takes about 7 minutes).
#
# Exits with status 1 when a threshold below is missed. Requested megabytes and
# 404 counts are deterministic and have tight limits. Seconds depend on the
# connection (the same run took 5 s at midday and 27 s in the afternoon), so the
# absolute limits are loose and, when the comparison runs are made, the package
# settings must also need at most 60% of the time of the old settings.
# Needs internet access,
# the sf package, and a GDAL build with curl. Background:
# docs/superpowers/plans/2026-10-05-perf-io-zonal.md, ISS-20261005-001.

args <- commandArgs(trailingOnly = TRUE)

thresholds <- list(
  L3 = list(seconds = 60, mb = 15, http_404 = 0),
  L2 = list(seconds = 90, mb = 25, http_404 = 0)
)
max_time_share_of_old <- 0.6

# ---- worker: one configuration and level in this process -------------------
if (length(args) >= 4 && identical(args[1], "--worker")) {
  config <- args[2]; level <- args[3]; out_file <- args[4]
  pkg_path <- if (length(args) >= 5) args[5] else ""
  if (identical(config, "old")) {
    # GDAL reads the chunk size once, at the first remote read: set it before loading.
    Sys.setenv(CPL_VSIL_CURL_CHUNK_SIZE = "10485760")
    options(Rwapor.remote_extension_filter = FALSE)
  }
  if (nzchar(pkg_path)) pkgload::load_all(pkg_path, quiet = TRUE) else library(Rwapor)
  options(Rwapor.verbose = FALSE)

  # 150 squares of 300 m on a regular grid inside the JVA Level 3 region (UTM 36N).
  n <- 150L; nx <- ceiling(sqrt(n / 4)); ny <- ceiling(n / nx)
  g <- expand.grid(x = seq(740500, 749000, length.out = nx),
                   y = seq(3583000, 3618000, length.out = ny))[seq_len(n), ]
  squares <- lapply(seq_len(n), function(i) sf::st_polygon(list(cbind(
    g$x[i] + c(0, 300, 300, 0, 0), g$y[i] + c(0, 0, 300, 300, 0)))))
  farms <- sf::st_transform(sf::st_sf(id = seq_len(n), geometry = sf::st_sfc(squares, crs = 32636)), 4326)
  farm_file <- tempfile(fileext = ".gpkg")
  sf::st_write(farms, farm_file, quiet = TRUE)

  t0 <- proc.time()[["elapsed"]]
  df <- wapor_ts(
    region = farm_file, variable = sprintf("%s-AETI-D", level),
    period = c("2023-01-01", "2023-12-31"), identifier = "id",
    l3_region = if (identical(level, "L3")) "JVA" else NULL
  )
  seconds <- proc.time()[["elapsed"]] - t0
  filter_after <- unname(terra::getGDALconfig("CPL_VSIL_CURL_ALLOWED_EXTENSIONS"))
  saveRDS(list(seconds = seconds, rows = nrow(df), checksum = sum(df$mean, na.rm = TRUE),
               chunk_env = Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE"), filter_after = filter_after),
          out_file)
  quit(save = "no", status = 0)
}

# ---- driver ----------------------------------------------------------------
pkg_path <- if (length(args) && !startsWith(args[1], "--")) normalizePath(args[1], winslash = "/") else ""
run_old <- !("--no-old" %in% args)
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]), winslash = "/")
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

with_env <- function(vars, code) {
  old <- Sys.getenv(names(vars), unset = NA)
  do.call(Sys.setenv, as.list(vars))
  on.exit({
    for (nm in names(old)) {
      if (is.na(old[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, stats::setNames(list(old[[nm]]), nm))
    }
  }, add = TRUE)
  force(code)
}

run_one <- function(config, level) {
  out_file <- tempfile(fileext = ".rds"); log_file <- tempfile(fileext = ".log")
  on.exit(unlink(c(out_file, log_file)), add = TRUE)
  # libcurl writes one block per request to stderr; counting needs no GDAL internals.
  status <- with_env(c(CPL_CURL_VERBOSE = "YES"), system2(
    rscript, shQuote(c(script, "--worker", config, level, out_file, pkg_path)),
    stdout = FALSE, stderr = log_file
  ))
  log <- if (file.exists(log_file)) readLines(log_file, warn = FALSE) else character(0)
  ranges <- regmatches(log, regexec("^Range: bytes=([0-9]+)-([0-9]+)", log))
  ranges <- ranges[lengths(ranges) == 3L]
  mb <- sum(vapply(ranges, function(m) as.numeric(m[3]) - as.numeric(m[2]) + 1, numeric(1))) / 1024^2
  res <- if (file.exists(out_file)) {
    readRDS(out_file)
  } else {
    list(seconds = NA_real_, rows = NA_integer_, checksum = NA_real_, chunk_env = NA_character_,
         filter_after = NA_character_)
  }
  data.frame(
    config = config, level = level, exit = as.integer(status), seconds = round(res$seconds, 1),
    get = sum(grepl("^> GET ", log)), head = sum(grepl("^> HEAD ", log)),
    http_404 = sum(grepl("^< HTTP/[0-9.]+ 404", log)), mb = round(mb, 1),
    checksum = res$checksum, rows = res$rows, chunk_env = res$chunk_env, filter_after = res$filter_after,
    stringsAsFactors = FALSE
  )
}

configs <- c("package", if (run_old) "old")
runs <- do.call(rbind, lapply(c("L3", "L2"), function(level) {
  do.call(rbind, lapply(configs, function(config) {
    cat(sprintf("Running %s / %s ...\n", level, config))
    run_one(config, level)
  }))
}))
cat("\n")
print(runs[, c("config", "level", "seconds", "get", "head", "http_404", "mb", "checksum", "rows")], row.names = FALSE)

failures <- character(0)
fail <- function(...) failures <<- c(failures, sprintf(...))
for (level in c("L3", "L2")) {
  p <- runs[runs$config == "package" & runs$level == level, ]
  th <- thresholds[[level]]
  if (!identical(p$exit, 0L) || !is.finite(p$seconds)) {
    fail("%s: the run failed (exit %s)", level, p$exit)
    next
  }
  if (p$rows != 150L * 36L) fail("%s: %s rows, expected %d", level, p$rows, 150L * 36L)
  if (p$seconds > th$seconds) fail("%s: %.1f s, limit %.0f s", level, p$seconds, th$seconds)
  if (p$mb > th$mb) fail("%s: %.1f MB requested, limit %.0f MB", level, p$mb, th$mb)
  if (p$http_404 > th$http_404) fail("%s: %d failed (404) requests, limit %d", level, p$http_404, th$http_404)
  if (nzchar(p$chunk_env)) {
    fail("%s: CPL_VSIL_CURL_CHUNK_SIZE is set to '%s' after loading the package", level, p$chunk_env)
  }
  if (nzchar(p$filter_after)) {
    fail("%s: the extension filter was left set ('%s') after wapor_ts()", level, p$filter_after)
  }
  o <- runs[runs$config == "old" & runs$level == level, ]
  if (nrow(o) && is.finite(o$checksum) && !isTRUE(all.equal(o$checksum, p$checksum, tolerance = 0))) {
    fail("%s: values differ between old and new settings (%.10g vs %.10g)", level, o$checksum, p$checksum)
  }
  if (nrow(o) && is.finite(o$seconds) && p$seconds > max_time_share_of_old * o$seconds) {
    fail("%s: %.1f s is more than %.0f%% of the %.1f s with the old settings", level, p$seconds,
         100 * max_time_share_of_old, o$seconds)
  }
  if (nrow(o) && is.finite(o$seconds)) {
    cat(sprintf(paste0("%s: %.1f s and %.1f MB now; %.1f s and %.1f MB with the old settings ",
                       "(%.1f times faster, %.0f times less data)\n"),
                level, p$seconds, p$mb, o$seconds, o$mb, o$seconds / p$seconds, o$mb / max(p$mb, 0.1)))
  }
}
if (length(failures)) {
  cat("\nFAILED:\n", paste0("  - ", failures, collapse = "\n"), "\n", sep = "")
  quit(save = "no", status = 1)
}
cat("\nAll thresholds met.\n")
