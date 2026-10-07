# Frozen copy of wapor_zonal_stats() as committed in 3bd6966 (P2 B2), before the
# perf-b restructuring. It is the oracle for the equivalence tests in
# test-zonal-stats.R: the restructured function must return an identical table.
# Do not edit it to follow later changes of the real function; a deliberate change
# of results needs its own test. Known defect kept on purpose: format = "sf"
# attaches wrong geometries with more than one statistic (ISS-20261005-003).

reference_zonal_stats <- function(x, zones, id, stats = c("mean", "area_ha", "mask_fraction", "coverage"),
                               probs = c(.1, .9), mask = NULL, weights = NULL, dissolve = TRUE, aoi = TRUE,
                               classes = NULL, breaks = NULL, labels = NULL, method = NULL, scheme = NULL,
                               min_coverage = .5, min_cell_fraction = 0, min_mask_area_ha = 0,
                               sd_type = c("population", "sample"), days = NULL, season = NULL,
                               normalize_id = TRUE, layers = NULL, format = c("long", "wide", "sf")) {
  sd_type <- match.arg(sd_type); format <- match.arg(format)
  r <- if (inherits(x, "SpatRaster")) x else x$raster
  if (!inherits(r, "SpatRaster")) stop("x must contain a SpatRaster", call. = FALSE)
  if (!is.null(layers)) r <- r[[layers]]
  z <- .wapor_zone_sf(zones)
  if (missing(id) || !length(id) || any(!id %in% names(z))) stop(sprintf("id columns missing; available columns: %s", paste(names(z), collapse = ", ")), call. = FALSE)
  if (isTRUE(dissolve)) {
    levels <- lapply(seq_along(id), function(ll) {
      zz <- .wapor_dissolve(z, id[seq_len(ll)])
      for (nm in setdiff(id, names(zz))) zz[[nm]] <- NA_character_
      zz$.level <- ll
      zz
    })
    z <- do.call(rbind, levels)
  } else {
    z$.level <- length(id)
  }
  if (isTRUE(aoi)) {
    ao <- sf::st_sf(setNames(as.list(rep(NA_character_, length(id))), id), geometry = sf::st_union(sf::st_geometry(z)))
    ao[[id[1]]] <- "AOI"; ao$.level <- 0L
    z <- rbind(z, ao)
  }
  z <- sf::st_transform(z, terra::crs(r))
  if (!is.null(mask)) mask <- terra::resample(if (inherits(mask, "SpatRaster")) mask else terra::rast(mask), r, method = "near")
  if (!is.null(weights)) weights <- terra::resample(if (inherits(weights, "SpatRaster")) weights else terra::rast(weights), r, method = "bilinear")
  if (!is.null(weights) && any(terra::values(weights)[,1] < 0 | terra::values(weights)[,1] > 1, na.rm = TRUE)) stop("weights must be between 0 and 1", call. = FALSE)
  units <- tryCatch(terra::units(r), error = function(e) rep(NA_character_, terra::nlyr(r)))
  if (length(units) != terra::nlyr(r)) units <- rep(NA_character_, terra::nlyr(r))
  ext_stack <- c(r, mask, weights)
  names(ext_stack) <- paste0("zonal_", seq_len(terra::nlyr(ext_stack)))
  ext <- exactextractr::exact_extract(ext_stack, z, coverage_area = TRUE,
    max_cells_in_memory = max(1, floor(.wapor_memory_budget_bytes()/8)), progress = FALSE)
  nval <- terra::nlyr(r); nzone <- nrow(z); out <- list(); oi <- 0L
  old_s2 <- sf::sf_use_s2()
  on.exit(sf::sf_use_s2(old_s2), add = TRUE)
  if (terra::is.lonlat(r)) sf::sf_use_s2(FALSE)
  geom_area <- as.numeric(sf::st_area(z)) / 1e4
  cov_warn <- character(); n_eff_warn <- character(); vol_warn <- character()
  for (j in seq_len(nzone)) {
    d <- ext[[j]]
    if (is.null(d) || !is.data.frame(d) || !nrow(d)) {
      warning("no overlap (coverage 0) for one or more zones", call. = FALSE)
      next
    }
    a <- d$coverage_area
    frac <- d$coverage_fraction
    if (is.null(frac)) {
      cell_a <- abs(terra::xres(r) * terra::yres(r))
      frac <- pmin(1, a / cell_a)
    }
    m <- if (!is.null(mask)) d[[nval + 1L]] else rep(1, length(a))
    f <- if (!is.null(weights)) d[[nval + 1L + !is.null(mask)]] else rep(1, length(a))
    keep <- frac >= min_cell_fraction; a <- a[keep]; m <- as.numeric(m[keep]); f <- as.numeric(f[keep]); frac <- frac[keep]
    w <- a * ifelse(is.na(m), 0, m) * ifelse(is.na(f), 0, f)
    mask_area <- sum(w, na.rm = TRUE)/1e4
    zone_vals <- as.data.frame(sf::st_drop_geometry(z[j, id, drop = FALSE]))
    zone_key <- paste(as.character(unlist(zone_vals)), collapse = "|")
    if (normalize_id) zone_key <- toupper(trimws(zone_key))
    for (k in seq_len(nval)) {
      v <- as.numeric(d[[k]][keep]); ok <- is.finite(v) & w > 0; valid_area <- sum(w[ok])/1e4; cov <- if (mask_area > 0) max(0, min(1, valid_area/mask_area)) else 0
      blocked <- cov < min_coverage || mask_area < min_mask_area_ha
      if (blocked && cov < min_coverage) cov_warn <- c(cov_warn, zone_key)
      add <- function(stat, value, unit = NA_character_, class = NA_character_) { oi <<- oi + 1L; out[[oi]] <<- data.frame(level = z$.level[j], zone_id = zone_key, zone_key = zone_key, season = if (is.null(season)) NA_character_ else as.character(season), variable = names(r)[k], period = NA_character_, stat = stat, class = class, value = value, unit = unit, stringsAsFactors = FALSE) }
      if ("area_ha" %in% stats) add("area_ha", geom_area[j], "ha"); if ("mask_fraction" %in% stats) add("mask_fraction", mask_area/geom_area[j], "fraction"); if ("coverage" %in% stats) add("coverage", cov, "fraction")
      mu <- if (blocked) NA_real_ else .wapor_wmean(v[ok], w[ok]); sd <- if (blocked) NA_real_ else .wapor_wsd(v[ok], w[ok], sd_type); vals <- list(mean=mu, sd=sd, cv=ifelse(is.finite(mu)&&mu!=0,sd/mu,NA), cu=if (!blocked) .wapor_cu(v[ok],w[ok]) else NA, du_lq=if (!blocked) .wapor_du_lq(v[ok],w[ok]) else NA, gini=if (!blocked) .wapor_wgini(v[ok],w[ok]) else NA, theil=if (!blocked) .wapor_wtheil(v[ok],w[ok]) else NA, min=if (!blocked&&any(ok)) min(v[ok]) else NA, max=if (!blocked&&any(ok)) max(v[ok]) else NA, count=sum(ok), n_eff=sum(frac[ok]))
      if (vals$n_eff < 9 && any(c("sd","cv","cu","du_lq","gini","theil","quantiles") %in% stats)) n_eff_warn <- c(n_eff_warn, zone_key)
      for (nm in intersect(names(vals), stats)) add(nm, vals[[nm]], ifelse(nm %in% c("mean","sd","min","max"), units[k], NA_character_))
      if ("quantiles" %in% stats && !blocked) for (q in seq_along(probs)) add(paste0("quantile_", probs[q]), .wapor_wquantile(v[ok],w[ok],probs[q]), units[k])
      if ("sum_volume" %in% stats) {
        u <- tolower(as.character(units[k]))
        dd <- if (grepl("mm/day", u, fixed = TRUE)) {
          if (is.null(days)) { vol_warn <- c(vol_warn, names(r)[k]); NULL } else v * as.numeric(days)[min(k, length(days))]
        } else if (u %in% c("mm", "mm/season", "mm/month", "mm/year", "mm/dekad")) v else { vol_warn <- c(vol_warn, names(r)[k]); NULL }
        if (!is.null(dd) && any(is.finite(dd[ok])) && !blocked) add("sum_volume", sum(dd[ok]/1000*w[ok]), "m3")
      }
      if ("class_share" %in% stats) {
        if (is.null(breaks) && is.null(scheme) && !all(v[ok] == as.integer(v[ok]))) {
          stop("class_share needs an integer classified layer, or breaks/scheme to classify first", call. = FALSE)
        }
        codes <- if (!is.null(scheme) || !is.null(breaks)) {
          cl <- wapor_classify(v, breaks = breaks, labels = labels, method = if (is.null(method)) "fixed" else method, scheme = scheme)
          as.integer(cl)
        } else as.integer(v)
        labs <- if (!is.null(labels)) labels else if (!is.null(scheme)) wapor_class_defaults(scheme)$labels else as.character(sort(unique(codes[ok])))
        den <- sum(w[ok])
        used <- if (!is.null(labels) || !is.null(scheme)) seq_along(labs) else sort(unique(codes[ok]))
        for (code in used) {
          lab <- if (!is.null(labs) && code <= length(labs)) labs[code] else as.character(code)
          add("class_area_ha", sum(w[ok & codes == code])/1e4, "ha", lab)
          add("class_pct", if (den > 0) 100 * sum(w[ok & codes == code]) / den else NA_real_, "percent", lab)
        }
        add("class_area_ha", mask_area - valid_area, "ha", "no data")
      }
    }
  }
  if (length(cov_warn)) warning(sprintf("zones below min_coverage: %s", paste(unique(utils::head(cov_warn, 5)), collapse = ", ")), call. = FALSE)
  if (length(n_eff_warn)) warning("fewer than about 3 x 3 whole cells: spread statistics are unreliable at this resolution", call. = FALSE)
  if (length(unique(vol_warn))) warning(sprintf("sum_volume skipped for rate layers without days: %s", paste(unique(vol_warn), collapse = ", ")), call. = FALSE)
  ans <- if (length(out)) do.call(rbind,out) else data.frame(); class(ans) <- c("wapor_zonal", "data.frame"); attr(ans,"wapor_zonal_call") <- list(stats=stats, sd_type=sd_type)
  if (format == "wide") return(wapor_zonal_wide(ans)); if (format == "sf") return(sf::st_sf(ans, geometry = sf::st_geometry(z)[match(ans$zone_key, ans$zone_key)]))
  ans
}
