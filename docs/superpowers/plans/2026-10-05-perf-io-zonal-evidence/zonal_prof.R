# Small profile of wapor_zonal_stats(): where does the time go, and how does it scale?
suppressMessages(pkgload::load_all(".", quiet = TRUE))
mk <- function(n, nlyr, nz_side) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 5e5, xmax = 5e5 + 20 * n, ymin = 35e5, ymax = 35e5 + 20 * n,
                   crs = "EPSG:32636", nlyrs = nlyr)
  set.seed(42); terra::values(r) <- round(runif(n * n * nlyr, 0, 80)) / 10
  names(r) <- sprintf("d%02d", seq_len(nlyr)); terra::units(r) <- "mm/day"
  step <- 20 * n / nz_side; side <- step * 0.6
  g <- expand.grid(i = seq_len(nz_side) - 1, j = seq_len(nz_side) - 1)
  z <- sf::st_sf(scheme = paste0("S", g$i %/% max(1, nz_side %/% 4)), farm = sprintf("F%05d", seq_len(nrow(g))),
    geometry = sf::st_sfc(lapply(seq_len(nrow(g)), function(k) {
      x0 <- 5e5 + g$i[k] * step + 7; y0 <- 35e5 + g$j[k] * step + 7
      sf::st_polygon(list(cbind(x0 + c(0, side, side, 0, 0), y0 + c(0, 0, side, side, 0))))
    }), crs = 32636))
  list(r = r, z = z)
}
tm <- function(e) { t0 <- proc.time()[["elapsed"]]; force(e); round(proc.time()[["elapsed"]] - t0, 1) }
cat("scaling, farms only (dissolve = FALSE, aoi = FALSE), stats = default:\n")
for (cs in list(c(400, 12, 10), c(800, 12, 10), c(800, 12, 20), c(800, 36, 20))) {
  k <- mk(cs[1], cs[2], cs[3])
  s <- tm(suppressWarnings(wapor_zonal_stats(k$r, k$z, id = "farm", dissolve = FALSE, aoi = FALSE)))
  f <- tm(exactextractr::exact_extract(k$r, k$z, c("mean", "min", "max", "count"), progress = FALSE))
  cat(sprintf("  %4d^2 cells, %2d layers, %4d zones: current %6.1f s | built-in ops %5.1f s\n", cs[1], cs[2], nrow(k$z), s, f))
}
k <- mk(800, 12, 10)
cat("\nwith defaults (id = scheme + farm, dissolve, aoi), 800^2, 12 layers, 100 farms:",
    tm(suppressWarnings(wapor_zonal_stats(k$r, k$z, id = c("scheme", "farm")))), "s\n")
pf <- tempfile(); Rprof(pf, interval = 0.02)
invisible(suppressWarnings(wapor_zonal_stats(k$r, k$z, id = c("scheme", "farm"))))
Rprof(NULL); sp <- summaryRprof(pf)
cat("profile total", sp$sampling.time, "s; by.total top 22:\n")
print(utils::head(sp$by.total[, c("total.time", "total.pct")], 22))
cat("by.self top 8:\n"); print(utils::head(sp$by.self[, c("self.time", "self.pct")], 8))
