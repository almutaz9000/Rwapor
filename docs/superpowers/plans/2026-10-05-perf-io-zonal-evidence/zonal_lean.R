# Prototype of a restructured zonal loop: same extraction, weights and formulas as
# wapor_zonal_stats(), but (1) only requested statistics are computed, (2) results go into
# pre-sized vectors, one data frame at the end, (3) layers are read in chunks to bound memory.
suppressMessages(pkgload::load_all(".", quiet = TRUE))
ns <- asNamespace("Rwapor")
zonal_lean <- function(r, z, id, stats = c("mean", "area_ha", "mask_fraction", "coverage"), probs = c(.1, .9),
                       min_coverage = .5, sd_type = "population", layer_chunk = 6L) {
  z <- sf::st_transform(ns$.wapor_zone_sf(z), terra::crs(r))
  nval <- terra::nlyr(r); nz <- nrow(z); units <- terra::units(r); lyr <- names(r)
  geom_area <- as.numeric(sf::st_area(z)) / 1e4
  key <- toupper(trimws(do.call(paste, c(lapply(sf::st_drop_geometry(z)[id], as.character), sep = "|"))))
  order_stats <- c(intersect(c("area_ha", "mask_fraction", "coverage"), stats),
                   intersect(c("mean", "sd", "cv", "cu", "du_lq", "gini", "theil", "min", "max", "count", "n_eff"), stats),
                   if ("quantiles" %in% stats) paste0("quantile_", probs))
  per <- length(order_stats); n <- nz * nval * per
  o_val <- rep(NA_real_, n); pos <- function(j, k) ((j - 1L) * nval + (k - 1L)) * per
  need <- function(s) s %in% stats
  for (ch in split(seq_len(nval), ceiling(seq_len(nval) / layer_chunk))) {
    ext <- exactextractr::exact_extract(r[[ch]], z, coverage_area = TRUE, progress = FALSE)
    for (j in seq_len(nz)) {
      d <- ext[[j]]; if (is.null(d) || !nrow(d)) next
      w <- d$coverage_area; mask_area <- sum(w, na.rm = TRUE) / 1e4
      for (i in seq_along(ch)) {
        k <- ch[i]; v <- as.numeric(d[[i]]); ok <- is.finite(v) & w > 0
        cov <- if (mask_area > 0) max(0, min(1, sum(w[ok]) / 1e4 / mask_area)) else 0
        blocked <- cov < min_coverage; vo <- v[ok]; wo <- w[ok]; res <- numeric(per); names(res) <- order_stats
        if (need("area_ha")) res[["area_ha"]] <- geom_area[j]
        if (need("mask_fraction")) res[["mask_fraction"]] <- mask_area / geom_area[j]
        if (need("coverage")) res[["coverage"]] <- cov
        mu <- if (blocked) NA_real_ else ns$.wapor_wmean(vo, wo)
        if (need("mean")) res[["mean"]] <- mu
        if (need("sd") || need("cv")) {
          sdv <- if (blocked) NA_real_ else ns$.wapor_wsd(vo, wo, sd_type)
          if (need("sd")) res[["sd"]] <- sdv
          if (need("cv")) res[["cv"]] <- if (is.finite(mu) && mu != 0) sdv / mu else NA_real_
        }
        if (need("gini")) res[["gini"]] <- if (blocked) NA_real_ else ns$.wapor_wgini(vo, wo)
        if (need("min")) res[["min"]] <- if (!blocked && any(ok)) min(vo) else NA_real_
        if (need("max")) res[["max"]] <- if (!blocked && any(ok)) max(vo) else NA_real_
        if (need("quantiles")) res[paste0("quantile_", probs)] <- if (blocked) NA_real_ else ns$.wapor_wquantile(vo, wo, probs)
        o_val[pos(j, k) + seq_len(per)] <- res
      }
    }
  }
  idx <- expand.grid(s = seq_len(per), k = seq_len(nval), j = seq_len(nz))
  stat <- order_stats[idx$s]
  data.frame(level = length(id), zone_id = key[idx$j], zone_key = key[idx$j], season = NA_character_,
             variable = lyr[idx$k], period = NA_character_, stat = stat, class = NA_character_, value = o_val,
             unit = ifelse(stat %in% c("mean", "sd", "min", "max") | grepl("^quantile_", stat), units[idx$k],
                    ifelse(stat == "area_ha", "ha", ifelse(stat %in% c("mask_fraction", "coverage"), "fraction", NA))),
             stringsAsFactors = FALSE)
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
same <- function(a, b) {
  a <- as.data.frame(a); cols <- c("zone_key", "variable", "stat", "value", "unit")
  a <- a[do.call(order, a[c("zone_key", "variable", "stat")]), cols]; b <- b[do.call(order, b[c("zone_key", "variable", "stat")]), cols]
  rownames(a) <- rownames(b) <- NULL; attributes(a)$wapor_zonal_call <- NULL
  isTRUE(all.equal(a, b, tolerance = 1e-12, check.attributes = FALSE))
}
for (st in list(c("mean", "area_ha", "mask_fraction", "coverage"),
                c("mean", "sd", "cv", "gini", "min", "max", "quantiles", "coverage"))) {
  cat("\nstats:", paste(st, collapse = ", "), "\n")
  for (cs in list(c(800, 12, 20), c(800, 36, 20), c(1500, 12, 45))) {
    k <- mk(cs[1], cs[2], cs[3])
    a <- run(suppressWarnings(wapor_zonal_stats(k$r, k$z, id = "farm", dissolve = FALSE, aoi = FALSE, stats = st)))
    b <- run(zonal_lean(k$r, k$z, id = "farm", stats = st))
    cat(sprintf("  %4d^2 cells, %2d layers, %4d zones: current %6.1f s, %5d MB | prototype %5.1f s, %5d MB | rows %d | identical: %s\n",
                cs[1], cs[2], nrow(k$z), a$s, a$mb, b$s, b$mb, nrow(b$v), same(a$v, b$v)))
  }
}
# one zone covering the whole raster (scheme / country case): memory with and without layer chunks
k <- mk(1500, 36, 1); k$z <- sf::st_sf(farm = "ALL", geometry = sf::st_as_sfc(sf::st_bbox(k$z)))
a <- run(suppressWarnings(wapor_zonal_stats(k$r, k$z, id = "farm", dissolve = FALSE, aoi = FALSE)))
b <- run(zonal_lean(k$r, k$z, id = "farm", layer_chunk = 4L))
cat(sprintf("\none zone over 1500^2 x 36 layers: current %.1f s, %d MB | prototype (4 layers per read) %.1f s, %d MB | identical: %s\n",
            a$s, a$mb, b$s, b$mb, same(a$v, b$v)))
