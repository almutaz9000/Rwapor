# Rwapor zonal statistics benchmark
# =============================================================================
# Times wapor_zonal_stats() on synthetic 20 m rasters whose zones cut cell
# borders, and reports peak R memory. Background and the timings of the
# implementation before 1.0.6: docs/superpowers/plans/2026-10-05-perf-io-zonal.md
# (ISS-20261005-002).
#
# Usage: Rscript zonal_benchmark.R [pkg_path]
# Exits with status 1 when a limit below is missed. No internet needed.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) && nzchar(args[1])) pkgload::load_all(args[1], quiet = TRUE) else library(Rwapor)

make_case <- function(n, nlyr, nz_side) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 5e5, xmax = 5e5 + 20 * n, ymin = 35e5, ymax = 35e5 + 20 * n,
                   crs = "EPSG:32636", nlyrs = nlyr)
  set.seed(42)
  x <- round(stats::runif(n * n * nlyr, 0, 80)) / 10
  x[sample(length(x), length(x) %/% 50)] <- NA
  terra::values(r) <- x
  names(r) <- sprintf("d%02d", seq_len(nlyr))
  terra::units(r) <- "mm/day"
  f <- tempfile(fileext = ".tif")
  terra::writeRaster(r, f, datatype = "FLT4S")
  step <- 20 * n / nz_side; side <- step * 0.6
  g <- expand.grid(i = seq_len(nz_side) - 1, j = seq_len(nz_side) - 1)
  z <- sf::st_sf(
    scheme = paste0("S", g$i %/% max(1, nz_side %/% 4)), farm = sprintf("F%05d", seq_len(nrow(g))),
    geometry = sf::st_sfc(lapply(seq_len(nrow(g)), function(k) {
      x0 <- 5e5 + g$i[k] * step + 7; y0 <- 35e5 + g$j[k] * step + 7
      sf::st_polygon(list(cbind(x0 + c(0, side, side, 0, 0), y0 + c(0, 0, side, side, 0))))
    }), crs = 32636)
  )
  list(r = terra::rast(f), z = z, file = f)
}
# Peak R memory is reported above what was in use before the call, so that
# whatever the session already holds does not count against the function.
measure <- function(expr) {
  base <- sum(gc(reset = TRUE)[, 2]); t0 <- proc.time()[["elapsed"]]
  value <- suppressWarnings(force(expr))
  list(rows = nrow(value), seconds = proc.time()[["elapsed"]] - t0, mb = sum(gc()[, 6]) - base)
}

# label, cells per side, layers, zones per side, arguments, limits (seconds, MB), before 1.0.6
runs <- list(
  list("farms only, default statistics", 800, 12, 20, list(id = "farm", dissolve = FALSE, aoi = FALSE), 10, NA, "56 s"),
  list("farms only, default statistics", 800, 36, 20, list(id = "farm", dissolve = FALSE, aoi = FALSE), 30, NA, "153 s"),
  list("farms only, default statistics", 1500, 12, 45, list(id = "farm", dissolve = FALSE, aoi = FALSE), 35, NA, "237 s"),
  list("farms only, eight statistics", 800, 12, 20,
       list(id = "farm", dissolve = FALSE, aoi = FALSE,
            stats = c("mean", "sd", "cv", "gini", "min", "max", "quantiles", "coverage")), 20, NA, "106 s"),
  list("two id levels and AOI (defaults)", 1500, 12, 20, list(id = c("scheme", "farm")), 60, NA, "140 s"),
  list("one zone over the whole raster, 512 MB budget", 900, 72, 1, list(id = "farm", dissolve = FALSE, aoi = FALSE),
       90, 800, "118 s, 1120 MB")
)
out <- do.call(rbind, lapply(runs, function(x) {
  k <- make_case(x[[2]], x[[3]], x[[4]])
  on.exit(unlink(k$file), add = TRUE)
  if (x[[4]] == 1) {
    e <- as.vector(terra::ext(k$r)) + c(7, -7, 7, -7)     # xmin, xmax, ymin, ymax
    k$z <- sf::st_sf(farm = "ALL", geometry = sf::st_as_sfc(sf::st_bbox(
      c(xmin = e[[1]], ymin = e[[3]], xmax = e[[2]], ymax = e[[4]]), crs = sf::st_crs(k$z))))
    old <- options(Rwapor.memory_budget_mb = 512); on.exit(options(old), add = TRUE)
  }
  m <- measure(do.call(wapor_zonal_stats, c(list(x = k$r, zones = k$z), x[[5]])))
  data.frame(case = x[[1]], raster = sprintf("%d^2 x %d", x[[2]], x[[3]]), zones = nrow(k$z), rows = m$rows,
             seconds = round(m$seconds, 1), limit_s = x[[6]], peak_MB_above_start = round(m$mb), limit_MB = x[[7]],
             before_1.0.6 = x[[8]], stringsAsFactors = FALSE)
}))
print(out, row.names = FALSE)
missed <- out$seconds > out$limit_s | (!is.na(out$limit_MB) & out$peak_MB_above_start > out$limit_MB)
if (any(missed)) {
  cat("\nFAILED:", paste(sprintf("%s (%s)", out$case[missed], out$raster[missed]), collapse = "; "), "\n")
  quit(save = "no", status = 1)
}
cat("\nAll limits met.\n")
