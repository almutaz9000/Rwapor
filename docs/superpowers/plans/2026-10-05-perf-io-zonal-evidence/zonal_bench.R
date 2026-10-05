# Local (no network) benchmark of wapor_zonal_stats(): time, R memory, and where the time goes.
suppressMessages(pkgload::load_all(".", quiet = TRUE))
cat("free RAM GB:", round(terra::free_RAM() / 1024^2, 1), "\n")
peak_mb <- function(expr) {
  gc(reset = TRUE); t0 <- proc.time()[["elapsed"]]; val <- force(expr)
  g <- gc(); list(val = val, s = proc.time()[["elapsed"]] - t0, mb = sum(g[, 6]))
}
make_case <- function(n, nlyr, nz_side) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 500000, xmax = 500000 + 20 * n,
                   ymin = 3500000, ymax = 3500000 + 20 * n, crs = "EPSG:32636", nlyrs = nlyr)
  set.seed(42); terra::values(r) <- round(runif(n * n * nlyr, 0, 80)) / 10
  names(r) <- sprintf("d%02d", seq_len(nlyr)); terra::units(r) <- "mm/day"
  f <- tempfile(fileext = ".tif"); terra::writeRaster(r, f, datatype = "FLT4S"); r <- terra::rast(f)
  # nz_side^2 zones; each covers 60% of its grid slot so borders cut cells
  step <- 20 * n / nz_side; side <- step * 0.6
  g <- expand.grid(i = seq_len(nz_side) - 1, j = seq_len(nz_side) - 1)
  polys <- lapply(seq_len(nrow(g)), function(k) {
    x0 <- 500000 + g$i[k] * step + 7; y0 <- 3500000 + g$j[k] * step + 7
    sf::st_polygon(list(cbind(x0 + c(0, side, side, 0, 0), y0 + c(0, 0, side, side, 0))))
  })
  z <- sf::st_sf(scheme = paste0("S", g$i %/% max(1, nz_side %/% 4)), farm = sprintf("F%05d", seq_len(nrow(g))),
                 geometry = sf::st_sfc(polys, crs = 32636))
  list(r = r, z = z)
}

# Fast path prototype: exactextractr built-in weighted operations, no per-cell data frames in R.
fast_mean <- function(r, z) {
  ex <- exactextractr::exact_extract(r, z, c("mean", "min", "max", "count"), progress = FALSE)
  ex
}

cases <- list(c(n = 1500, nlyr = 12, nz = 20), c(n = 1500, nlyr = 36, nz = 20), c(n = 1500, nlyr = 12, nz = 45))
out <- list()
for (cs in cases) {
  k <- make_case(cs[["n"]], cs[["nlyr"]], cs[["nz"]])
  lab <- sprintf("%dx%d cells, %d layers, %d zones", cs[["n"]], cs[["n"]], cs[["nlyr"]], nrow(k$z))
  cat("\n==", lab, "\n")
  a <- peak_mb(suppressWarnings(wapor_zonal_stats(k$r, k$z, id = c("scheme", "farm"))))
  b <- peak_mb(suppressWarnings(wapor_zonal_stats(k$r, k$z, id = "farm", dissolve = FALSE, aoi = FALSE)))
  raw <- peak_mb(exactextractr::exact_extract(k$r, k$z, coverage_area = TRUE, progress = FALSE))
  rm(raw); p <- peak_mb(fast_mean(k$r, k$z))
  # same numbers? farm-level mean of layer 1, current vs built-in
  cur <- a$val[a$val$level == 2 & a$val$stat == "mean" & a$val$variable == "d01", ]
  cur <- cur$value[match(toupper(paste(k$z$scheme, k$z$farm, sep = "|")), cur$zone_key)]
  newv <- if (cs[["nlyr"]] > 1) p$val[["mean.d01"]] else p$val[["mean"]]
  cat(sprintf("  max |current - built-in| farm mean d01: %.3g  (n matched %d)\n",
              max(abs(cur - newv), na.rm = TRUE), sum(is.finite(cur))))
  out[[lab]] <- data.frame(case = lab,
    run = c("current, id = scheme+farm, aoi (defaults)", "current, farms only, no dissolve/aoi",
            "built-in ops prototype, farms only"),
    seconds = round(c(a$s, b$s, p$s), 1), peak_R_MB = round(c(a$mb, b$mb, p$mb)),
    rows = c(nrow(a$val), nrow(b$val), nrow(p$val)))
  print(out[[lab]][, -1], row.names = FALSE)
}

# Where the time goes in the current implementation (farms only, 12 layers, 2025 zones)
k <- make_case(1500, 12, 45)
pf <- tempfile(); Rprof(pf, interval = 0.02)
invisible(suppressWarnings(wapor_zonal_stats(k$r, k$z, id = "farm", dissolve = FALSE, aoi = FALSE)))
Rprof(NULL); sp <- summaryRprof(pf)
cat("\n== profile, total time by function (top 14), sampling total", sp$sampling.time, "s\n")
print(utils::head(sp$by.total[, c("total.time", "total.pct")], 14))
want <- c("\"exact_extract\"", "\"add\"", "\"data.frame\"", "\".wapor_wgini\"", "\".wapor_wtheil\"",
          "\".wapor_du_lq\"", "\".wapor_cu\"", "\".wapor_wsd\"", "\".wapor_wmean\"", "\"do.call\"", "\"rbind\"")
cat("\n== selected functions\n"); print(sp$by.total[intersect(want, rownames(sp$by.total)), c("total.time", "total.pct")])

# sf output check (format = 'sf'): does every row get its own zone's geometry?
k <- make_case(300, 1, 3)
s <- suppressWarnings(wapor_zonal_stats(k$r, k$z, id = "farm", dissolve = FALSE, aoi = FALSE, stats = "mean", format = "sf"))
cz <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(k$z)))
cs2 <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(s)))
cat("\n== format='sf': rows", nrow(s), " geometry matches its zone:",
    isTRUE(all.equal(unname(cz[match(s$zone_id, toupper(k$z$farm)), ]), unname(cs2))), "\n")
