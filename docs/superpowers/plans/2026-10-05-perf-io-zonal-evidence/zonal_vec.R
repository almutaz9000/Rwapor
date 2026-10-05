# Second prototype: grouped sums (rowsum) for the additive statistics, no per-zone R loop.
suppressMessages(pkgload::load_all(".", quiet = TRUE))
zonal_vec <- function(r, z, id, min_coverage = .5, layer_chunk = 6L) {
  z <- sf::st_transform(z, terra::crs(r)); nz <- nrow(z); nval <- terra::nlyr(r)
  geom_area <- as.numeric(sf::st_area(z)) / 1e4
  mean_m <- cov_m <- sd_m <- min_m <- max_m <- matrix(NA_real_, nz, nval); mask_area <- rep(0, nz)
  for (ch in split(seq_len(nval), ceiling(seq_len(nval) / layer_chunk))) {
    ext <- exactextractr::exact_extract(r[[ch]], z, coverage_area = TRUE, progress = FALSE)
    zi <- rep.int(seq_len(nz), vapply(ext, nrow, 1L))
    w <- unlist(lapply(ext, `[[`, "coverage_area"), use.names = FALSE)
    g <- sort(unique(zi)); mask_area[g] <- rowsum(w, zi)[, 1] / 1e4
    for (i in seq_along(ch)) {
      v <- unlist(lapply(ext, `[[`, i), use.names = FALSE); ok <- is.finite(v) & w > 0
      wk <- w * ok; vk <- ifelse(ok, v, 0)
      sw <- rowsum(wk, zi)[, 1]; mu <- rowsum(wk * vk, zi)[, 1] / sw
      var <- rowsum(wk * (vk - mu[match(zi, g)])^2, zi)[, 1] / sw
      cov <- pmin(1, pmax(0, sw / 1e4 / mask_area[g])); blocked <- cov < min_coverage
      mean_m[g, ch[i]] <- ifelse(blocked, NA, mu); sd_m[g, ch[i]] <- ifelse(blocked, NA, sqrt(pmax(0, var)))
      cov_m[g, ch[i]] <- cov
      min_m[g, ch[i]] <- ifelse(blocked, NA, tapply(ifelse(ok, v, Inf), zi, min))
      max_m[g, ch[i]] <- ifelse(blocked, NA, tapply(ifelse(ok, v, -Inf), zi, max))
    }
  }
  list(mean = mean_m, sd = sd_m, coverage = cov_m, min = min_m, max = max_m, area_ha = geom_area, mask_fraction = mask_area / geom_area)
}
mk <- function(n, nlyr, nz_side) {
  r <- terra::rast(nrows = n, ncols = n, xmin = 5e5, xmax = 5e5 + 20 * n, ymin = 35e5, ymax = 35e5 + 20 * n,
                   crs = "EPSG:32636", nlyrs = nlyr)
  set.seed(42); x <- round(runif(n * n * nlyr, 0, 80)) / 10; x[sample(length(x), length(x) %/% 50)] <- NA
  terra::values(r) <- x; names(r) <- sprintf("d%02d", seq_len(nlyr)); terra::units(r) <- "mm/day"
  step <- 20 * n / nz_side; side <- step * 0.6
  g <- expand.grid(i = seq_len(nz_side) - 1, j = seq_len(nz_side) - 1)
  z <- sf::st_sf(farm = sprintf("F%05d", seq_len(nrow(g))), geometry = sf::st_sfc(lapply(seq_len(nrow(g)), function(k) {
    x0 <- 5e5 + g$i[k] * step + 7; y0 <- 35e5 + g$j[k] * step + 7
    sf::st_polygon(list(cbind(x0 + c(0, side, side, 0, 0), y0 + c(0, 0, side, side, 0))))
  }), crs = 32636))
  list(r = r, z = z)
}
run <- function(e) { gc(reset = TRUE); t0 <- proc.time()[["elapsed"]]; v <- force(e)
  list(v = v, s = round(proc.time()[["elapsed"]] - t0, 1), mb = round(sum(gc()[, 6]))) }
# correctness on a small case against the current function (all five statistics)
k <- mk(400, 6, 10)
cur <- suppressWarnings(wapor_zonal_stats(k$r, k$z, id = "farm", dissolve = FALSE, aoi = FALSE,
                                          stats = c("mean", "sd", "min", "max", "coverage", "area_ha", "mask_fraction")))
p <- zonal_vec(k$r, k$z, "farm")
pick <- function(st) { d <- cur[cur$stat == st, ]; matrix(d$value[order(d$zone_key, d$variable)], nrow(k$z), byrow = TRUE) }
for (st in c("mean", "sd", "min", "max", "coverage"))
  cat(sprintf("max |current - rowsum| %-9s %.3g\n", st, max(abs(pick(st) - p[[st]]), na.rm = TRUE)))
cat("NA pattern equal (mean):", identical(is.na(pick("mean")), is.na(p$mean)), "\n")
for (cs in list(c(800, 12, 20), c(800, 36, 20), c(1500, 12, 45), c(1500, 36, 45))) {
  k <- mk(cs[1], cs[2], cs[3]); b <- run(zonal_vec(k$r, k$z, "farm"))
  cat(sprintf("%4d^2 cells, %2d layers, %4d zones: rowsum prototype %5.1f s, %4d MB\n", cs[1], cs[2], nrow(k$z), b$s, b$mb))
}
