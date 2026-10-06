# Weighted zonal statistics for WaPOR rasters.

.wapor_wmean <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (!any(ok)) return(NA_real_)
  sum(w[ok] * x[ok]) / sum(w[ok])
}

.wapor_wsd <- function(x, w, sd_type = "population") {
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (!any(ok)) return(NA_real_)
  x <- x[ok]; w <- w[ok]; v1 <- sum(w); mu <- sum(w * x) / v1
  var <- sum(w * (x - mu)^2) / v1
  if (sd_type == "sample") {
    v2 <- sum(w^2)
    if (v1^2 <= v2) return(NA_real_)
    var <- var * v1^2 / (v1^2 - v2)
  }
  sqrt(max(0, var))
}

.wapor_wquantile <- function(x, w, probs) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (!any(ok)) return(rep(NA_real_, length(probs)))
  o <- order(x[ok]); x <- x[ok][o]; w <- w[ok][o]
  if (length(x) == 1L) return(rep(x, length(probs)))
  pos <- (cumsum(w) - w) / (sum(w) - tail(w, 1L))
  vapply(probs, function(p) approx(pos, x, xout = p, method = "linear", ties = "ordered", rule = 2)$y, numeric(1))
}

.wapor_cu <- function(x, w) {
  mu <- .wapor_wmean(x, w); if (!is.finite(mu) || mu == 0) return(NA_real_)
  1 - sum(w * abs(x - mu), na.rm = TRUE) / (mu * sum(w, na.rm = TRUE))
}

.wapor_du_lq <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (!any(ok)) return(NA_real_)
  o <- order(x[ok]); x <- x[ok][o]; w <- w[ok][o]; target <- sum(w) * .25
  take <- pmin(w, pmax(0, target - c(0, cumsum(w)[-length(w)])))
  mu <- sum(x * take) / sum(take); overall <- sum(x * w) / sum(w)
  if (overall == 0) NA_real_ else mu / overall
}

.wapor_wgini <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  if (!any(ok)) return(NA_real_)
  o <- order(x[ok]); x <- x[ok][o]; w <- w[ok][o]; sw <- sum(w); mu <- sum(w*x)/sw
  if (mu == 0) return(NA_real_)
  2 * sum(w * x * (cumsum(w) - w/2)) / (sw^2 * mu) - 1
}

.wapor_wtheil <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & w > 0 & x > 0
  if (!any(ok)) return(NA_real_)
  mu <- .wapor_wmean(x[ok], w[ok]); sum(w[ok] * (x[ok]/mu) * log(x[ok]/mu)) / sum(w[ok])
}

.wapor_zone_sf <- function(zones) {
  if (is.character(zones) && length(zones) == 1L) zones <- sf::st_read(zones, quiet = TRUE)
  if (inherits(zones, "SpatVector")) zones <- sf::st_as_sf(zones)
  if (!inherits(zones, "sf")) stop("zones must be sf, SpatVector, or a vector file path", call. = FALSE)
  zones <- sf::st_make_valid(zones)
  empty <- sf::st_is_empty(zones)
  if (any(empty)) { warning("empty zone geometries were dropped", call. = FALSE); zones <- zones[!empty, ] }
  zones
}

.wapor_dissolve <- function(zones, ids) {
  key <- do.call(paste, c(lapply(zones[ids], as.character), sep = "\034"))
  groups <- split(seq_len(nrow(zones)), key)
  out <- lapply(groups, function(ii) {
    g <- sf::st_union(sf::st_geometry(zones[ii, ]))
    vals <- zones[ii[1], ids, drop = FALSE]
    sf::st_sf(vals, geometry = g)
  })
  do.call(rbind, out)
}

.wapor_extract_layer_names <- function(x) {
  if (inherits(x, "SpatRaster")) return(names(x))
  if (is.list(x) && inherits(x$raster, "SpatRaster")) return(names(x$raster))
  stop("x must be a terra SpatRaster or an analysis result containing $raster", call. = FALSE)
}

#' Calculate weighted statistics for raster values by polygon zones.
#' @param x SpatRaster or analysis result containing a raster.
#' @param zones Polygon zones.
#' @param id Character vector of zone columns, from coarse to fine.
#' @param stats Statistics to return.
#' @param probs Quantile probabilities.
#' @param mask Optional binary raster.
#' @param weights Optional fractional raster in 0 to 1.
#' @param dissolve Dissolve duplicate zone ids.
#' @param aoi Include the union of all zones.
#' @param classes Optional pre-classified raster.
#' @param breaks,labels,method,scheme Classification arguments.
#' @param min_coverage Minimum valid share of masked area.
#' @param min_cell_fraction Minimum covered cell fraction.
#' @param min_mask_area_ha Minimum masked area.
#' @param sd_type Population or sample standard deviation.
#' @param days Days for mm/day layers.
#' @param season Optional season identifier.
#' @param normalize_id Normalize ids for `zone_key`.
#' @param layers Optional layer names or indices.
#' @param format Output format: long, wide, or sf.
#' @return A long data frame with class `wapor_zonal`.
#' @export
wapor_zonal_stats <- function(x, zones, id, stats = c("mean", "area_ha", "mask_fraction", "coverage"),
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
  if (!is.null(weights)) {
    # Range from the first layer, read block-wise by terra rather than as one vector.
    w_range <- as.numeric(unlist(terra::global(weights[[1]], "range", na.rm = TRUE)))
    if (any(is.finite(w_range)) && (min(w_range, na.rm = TRUE) < 0 || max(w_range, na.rm = TRUE) > 1)) stop("weights must be between 0 and 1", call. = FALSE)
  }
  units <- tryCatch(terra::units(r), error = function(e) rep(NA_character_, terra::nlyr(r)))
  if (length(units) != terra::nlyr(r)) units <- rep(NA_character_, terra::nlyr(r))
  nval <- terra::nlyr(r); nzone <- nrow(z)
  old_s2 <- sf::sf_use_s2()
  on.exit(sf::sf_use_s2(old_s2), add = TRUE)
  if (terra::is.lonlat(r)) sf::sf_use_s2(FALSE)
  geom_area <- as.numeric(sf::st_area(z)) / 1e4
  zone_key <- vapply(seq_len(nzone), function(j) {
    key <- paste(as.character(unlist(as.data.frame(sf::st_drop_geometry(z[j, id, drop = FALSE])))), collapse = "|")
    if (normalize_id) toupper(trimws(key)) else key
  }, character(1))
  season_value <- if (is.null(season)) NA_character_ else as.character(season)
  n_extra <- (!is.null(mask)) + (!is.null(weights))
  spread_stats <- any(c("sd", "cv", "cu", "du_lq", "gini", "theil", "quantiles") %in% stats)
  need <- function(s) s %in% stats

  # Layers are read in groups so that memory follows the layers held at once,
  # not the whole stack. Cells are estimated from the zone bounding boxes. One
  # group's table of cell values is sized to an eighth of the memory budget:
  # measured peak use is about 2.5 times that table (ISS-20261005-002).
  zone_cells <- sum(vapply(sf::st_geometry(z), function(g) {
    if (sf::st_is_empty(g)) return(0)
    b <- sf::st_bbox(g)
    (as.numeric(b[["xmax"]] - b[["xmin"]]) / terra::xres(r) + 1) * (as.numeric(b[["ymax"]] - b[["ymin"]]) / terra::yres(r) + 1)
  }, numeric(1)))
  zone_cells <- min(max(zone_cells, 1), as.numeric(terra::ncell(r)) * nzone)
  layer_chunk <- floor(0.125 * .wapor_memory_budget_bytes() / (8 * zone_cells)) - n_extra - 2
  layer_chunk <- as.integer(max(1, min(nval, layer_chunk)))
  chunks <- split(seq_len(nval), ceiling(seq_len(nval) / layer_chunk))

  # One slot per zone and layer, filled in any order and read back zone by zone.
  slots <- vector("list", nzone * nval)
  no_overlap <- logical(nzone)
  cov_flag <- vol_flag <- matrix(FALSE, nzone, nval)
  n_eff_flag <- FALSE
  ext <- NULL
  for (ch in chunks) {
    # Release the previous group before reading the next, so that peak memory
    # follows one group and not how late the garbage collector runs.
    ext <- d <- NULL
    if (length(chunks) > 1L) invisible(gc(verbose = FALSE))
    ext_stack <- c(r[[ch]], mask, weights)
    names(ext_stack) <- paste0("zonal_", seq_len(terra::nlyr(ext_stack)))
    ext <- exactextractr::exact_extract(ext_stack, z, coverage_area = TRUE,
      max_cells_in_memory = max(1, floor(.wapor_memory_budget_bytes()/8)), progress = FALSE)
    nch <- length(ch)
    for (j in seq_len(nzone)) {
      d <- ext[[j]]
      if (is.null(d) || !is.data.frame(d) || !nrow(d)) {
        # Once per zone, at the point the original loop raised it.
        if (!no_overlap[j]) warning("no overlap (coverage 0) for one or more zones", call. = FALSE)
        no_overlap[j] <- TRUE
        next
      }
      a <- d$coverage_area
      frac <- d$coverage_fraction
      if (is.null(frac)) {
        cell_a <- abs(terra::xres(r) * terra::yres(r))
        frac <- pmin(1, a / cell_a)
      }
      m <- if (!is.null(mask)) d[[nch + 1L]] else rep(1, length(a))
      f <- if (!is.null(weights)) d[[nch + 1L + !is.null(mask)]] else rep(1, length(a))
      keep <- frac >= min_cell_fraction; a <- a[keep]; m <- as.numeric(m[keep]); f <- as.numeric(f[keep]); frac <- frac[keep]
      w <- a * ifelse(is.na(m), 0, m) * ifelse(is.na(f), 0, f)
      mask_area <- sum(w, na.rm = TRUE)/1e4
      for (i in seq_len(nch)) {
        k <- ch[i]
        v <- as.numeric(d[[i]][keep]); ok <- is.finite(v) & w > 0; valid_area <- sum(w[ok])/1e4; cov <- if (mask_area > 0) max(0, min(1, valid_area/mask_area)) else 0
        blocked <- cov < min_coverage || mask_area < min_mask_area_ha
        if (blocked && cov < min_coverage) cov_flag[j, k] <- TRUE
        st <- character(0); cl <- character(0); un <- character(0); va <- list()
        add <- function(stat, value, unit = NA_character_, class = NA_character_) {
          n <- length(st) + 1L
          st[n] <<- stat; cl[n] <<- class; un[n] <<- unit; va[[n]] <<- value
        }
        if (need("area_ha")) add("area_ha", geom_area[j], "ha"); if (need("mask_fraction")) add("mask_fraction", mask_area/geom_area[j], "fraction"); if (need("coverage")) add("coverage", cov, "fraction")
        vo <- v[ok]; wo <- w[ok]
        n_eff <- sum(frac[ok])
        if (n_eff < 9 && spread_stats) n_eff_flag <- TRUE
        # Only the requested statistics are computed; the order below is the output order.
        mu <- if ((need("mean") || need("cv")) && !blocked) .wapor_wmean(vo, wo) else NA_real_
        sdv <- if ((need("sd") || need("cv")) && !blocked) .wapor_wsd(vo, wo, sd_type) else NA_real_
        if (need("mean")) add("mean", mu, units[k])
        if (need("sd")) add("sd", sdv, units[k])
        if (need("cv")) add("cv", ifelse(is.finite(mu) && mu != 0, sdv/mu, NA))
        if (need("cu")) add("cu", if (!blocked) .wapor_cu(vo, wo) else NA)
        if (need("du_lq")) add("du_lq", if (!blocked) .wapor_du_lq(vo, wo) else NA)
        if (need("gini")) add("gini", if (!blocked) .wapor_wgini(vo, wo) else NA)
        if (need("theil")) add("theil", if (!blocked) .wapor_wtheil(vo, wo) else NA)
        if (need("min")) add("min", if (!blocked && any(ok)) min(vo) else NA, units[k])
        if (need("max")) add("max", if (!blocked && any(ok)) max(vo) else NA, units[k])
        if (need("count")) add("count", sum(ok))
        if (need("n_eff")) add("n_eff", n_eff)
        if (need("quantiles") && !blocked) for (q in seq_along(probs)) add(paste0("quantile_", probs[q]), .wapor_wquantile(vo, wo, probs[q]), units[k])
        if (need("sum_volume")) {
          u <- tolower(as.character(units[k]))
          dd <- if (grepl("mm/day", u, fixed = TRUE)) {
            if (is.null(days)) { vol_flag[j, k] <- TRUE; NULL } else v * as.numeric(days)[min(k, length(days))]
          } else if (u %in% c("mm", "mm/season", "mm/month", "mm/year", "mm/dekad")) v else { vol_flag[j, k] <- TRUE; NULL }
          if (!is.null(dd) && any(is.finite(dd[ok])) && !blocked) add("sum_volume", sum(dd[ok]/1000*w[ok]), "m3")
        }
        if (need("class_share")) {
          if (is.null(breaks) && is.null(scheme) && !all(v[ok] == as.integer(v[ok]))) {
            stop("class_share needs an integer classified layer, or breaks/scheme to classify first", call. = FALSE)
          }
          codes <- if (!is.null(scheme) || !is.null(breaks)) {
            cls <- wapor_classify(v, breaks = breaks, labels = labels, method = if (is.null(method)) "fixed" else method, scheme = scheme)
            as.integer(cls)
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
        if (length(st)) slots[[(j - 1L) * nval + k]] <- list(stat = st, class = cl, unit = un, value = va)
      }
    }
  }
  # Warning inputs in the original zone-by-zone, layer-by-layer order.
  cov_warn <- rep(zone_key, each = nval)[as.vector(t(cov_flag))]
  vol_warn <- rep(names(r), times = nzone)[as.vector(t(vol_flag))]
  if (length(cov_warn)) warning(sprintf("zones below min_coverage: %s", paste(unique(utils::head(cov_warn, 5)), collapse = ", ")), call. = FALSE)
  if (n_eff_flag) warning("fewer than about 3 x 3 whole cells: spread statistics are unreliable at this resolution", call. = FALSE)
  if (length(unique(vol_warn))) warning(sprintf("sum_volume skipped for rate layers without days: %s", paste(unique(vol_warn), collapse = ", ")), call. = FALSE)
  n_rows <- lengths(lapply(slots, `[[`, "stat"))
  zone_index <- rep(rep(seq_len(nzone), each = nval), times = n_rows)
  ans <- if (sum(n_rows)) {
    layer_index <- rep(rep(seq_len(nval), times = nzone), times = n_rows)
    data.frame(level = z$.level[zone_index], zone_id = zone_key[zone_index], zone_key = zone_key[zone_index],
               season = season_value, variable = names(r)[layer_index], period = NA_character_,
               stat = unlist(lapply(slots, `[[`, "stat")), class = unlist(lapply(slots, `[[`, "class")),
               value = unlist(lapply(slots, `[[`, "value")), unit = unlist(lapply(slots, `[[`, "unit")),
               stringsAsFactors = FALSE)
  } else data.frame()
  class(ans) <- c("wapor_zonal", "data.frame"); attr(ans,"wapor_zonal_call") <- list(stats=stats, sd_type=sd_type)
  if (format == "wide") return(wapor_zonal_wide(ans)); if (format == "sf") return(sf::st_sf(ans, geometry = sf::st_geometry(z)[zone_index]))
  ans
}

#' Convert a long zonal result to one row per zone and variable.
#' @param z A `wapor_zonal` or long data frame.
#' @return Wide data frame.
#' @export
wapor_zonal_wide <- function(z) {
  if (!is.data.frame(z)) stop("z must be a data frame returned by wapor_zonal_stats", call. = FALSE)
  key <- interaction(z$zone_key, z$variable, drop = TRUE, sep = "|")
  vals <- stats::reshape(z[c("zone_key", "variable", "stat", "value")], idvar = c("zone_key", "variable"), timevar = "stat", direction = "wide")
  names(vals) <- sub("^value\\.", "", names(vals)); vals
}
