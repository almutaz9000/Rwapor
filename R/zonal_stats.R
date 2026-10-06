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
  vapply(probs, function(p) stats::approx(pos, x, xout = p, method = "linear", ties = "ordered", rule = 2)$y, numeric(1))
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

#' Merge polygons that share the same id values (internal)
#'
#' The grouping key is built from the id attributes only. Indexing the `sf`
#' object itself would carry the geometry column into the key, so that no two
#' polygons ever matched.
#' @param zones `sf` polygons.
#' @param ids Id column names.
#' @return `sf` with one row per id combination (sorted by id) and the id columns.
#' @keywords internal
#' @noRd
.wapor_dissolve <- function(zones, ids) {
  attrs <- as.data.frame(sf::st_drop_geometry(zones))[ids]
  key <- do.call(paste, c(lapply(attrs, as.character), sep = "\034"))
  groups <- split(seq_len(nrow(zones)), key)
  geom <- sf::st_geometry(zones)
  merged <- do.call(c, lapply(groups, function(ii) sf::st_union(geom[ii])))
  out <- attrs[vapply(groups, function(ii) ii[1], integer(1)), , drop = FALSE]
  rownames(out) <- NULL
  sf::st_sf(out, geometry = sf::st_sfc(merged, crs = sf::st_crs(zones)))
}

#' Zone areas in hectares (internal)
#'
#' Zones in a projected CRS are measured as they are. Zones in lon/lat are first
#' projected to a Lambert azimuthal equal-area system centred on them, which
#' keeps areas exact on the ellipsoid. This needs neither s2, which fails on
#' field polygons with duplicate vertices, nor the lwgeom package, which
#' `sf::st_area()` requires for lon/lat when s2 is off (ISS-20261005-004).
#' @param z `sf` zones in the CRS of the raster.
#' @param lonlat Logical. Is that CRS geographic?
#' @return Numeric vector, one area per zone.
#' @keywords internal
#' @noRd
.wapor_zone_area_ha <- function(z, lonlat) {
  if (isTRUE(lonlat)) {
    bb <- sf::st_bbox(z)
    z <- sf::st_transform(z, sprintf(
      "+proj=laea +lat_0=%.6f +lon_0=%.6f +datum=WGS84 +units=m +no_defs",
      mean(bb[c("ymin", "ymax")]), mean(bb[c("xmin", "xmax")])
    ))
  }
  as.numeric(sf::st_area(z)) / 1e4
}

.wapor_extract_layer_names <- function(x) {
  if (inherits(x, "SpatRaster")) return(names(x))
  if (is.list(x) && inherits(x$raster, "SpatRaster")) return(names(x$raster))
  stop("x must be a terra SpatRaster or an analysis result containing $raster", call. = FALSE)
}

#' Area of lon/lat raster cells on the WGS84 ellipsoid, in m2 (internal)
#'
#' Exact area of a cell bounded by two parallels and two meridians (Snyder 1987,
#' eq. 3-12, authalic latitude). exactextractr's `coverage_area` uses a sphere
#' for lon/lat rasters, which is about 0.3% too large at 32 degrees north.
#' @param y Cell centre latitudes in degrees.
#' @param xres,yres Cell size in degrees.
#' @return Numeric vector of cell areas.
#' @keywords internal
#' @noRd
.wapor_lonlat_cell_area <- function(y, xres, yres) {
  a <- 6378137; f <- 1 / 298.257223563
  e2 <- f * (2 - f); e <- sqrt(e2); b <- a * (1 - f)
  q <- function(lat) {
    s <- sin(lat * pi / 180)
    s / (1 - e2 * s^2) + log((1 + e * s) / (1 - e * s)) / (2 * e)
  }
  b^2 / 2 * (xres * pi / 180) * abs(q(y + yres / 2) - q(y - yres / 2))
}

#' Rasters of a seasonal analysis result, named and with units (internal)
#'
#' @param res Result of [wapor_run_seasonal_analysis()].
#' @param layers Optional output names to use; default: every known output present.
#' @return List with `raster` (one layer per output, named after it) and `units`.
#' @keywords internal
#' @noRd
.wapor_result_layers <- function(res, layers = NULL) {
  known <- c(seasonal_aeti = "mm", seasonal_t = "mm", seasonal_ret = "mm", seasonal_pcp = "mm",
             seasonal_peff = "mm", etc = "mm", adequacy_etc = NA, adequacy_p95 = NA,
             beneficial_fraction = NA, green_water = "mm", blue_water = "mm",
             seasonal_biomass_t = "t/ha", yield_raster = "t/ha")
  get_layer <- function(nm) {
    if (identical(nm, "etc")) {
      parts <- lapply(res$etc_by_class, function(e) if (is.list(e)) e$etc_seasonal else NULL)
      parts <- parts[vapply(parts, inherits, logical(1), what = "SpatRaster")]
      if (!length(parts)) return(NULL)
      return(Reduce(terra::cover, lapply(parts, function(p) p[[1]])))   # one raster over all crop classes
    }
    v <- res[[nm]]
    if (inherits(v, "SpatRaster")) return(v[[1]])
    if (is.list(v) && inherits(v$raster, "SpatRaster")) return(v$raster[[1]])
    NULL
  }
  found <- lapply(stats::setNames(names(known), names(known)), get_layer)
  found <- found[!vapply(found, is.null, logical(1))]
  if (!length(found)) stop("x holds no raster outputs of wapor_run_seasonal_analysis()", call. = FALSE)
  if (!is.null(layers)) {
    if (!is.character(layers) || any(!layers %in% names(found))) {
      stop(sprintf("for an analysis result 'layers' must be output names; available: %s",
                   paste(names(found), collapse = ", ")), call. = FALSE)
    }
    found <- found[layers]
  }
  r <- terra::rast(unname(found))
  names(r) <- names(found)
  list(raster = r, units = unname(known[names(found)]))
}

#' Value raster and units for the zonal engine (internal)
#' @keywords internal
#' @noRd
.wapor_zonal_source <- function(x, layers) {
  from_raster <- function(r) {
    if (!is.null(layers)) r <- r[[layers]]
    units <- tryCatch(terra::units(r), error = function(e) rep(NA_character_, terra::nlyr(r)))
    if (length(units) != terra::nlyr(r)) units <- rep(NA_character_, terra::nlyr(r))
    list(raster = r, units = units)
  }
  if (inherits(x, "SpatRaster")) return(from_raster(x))
  if (is.list(x) && inherits(x$raster, "SpatRaster")) return(from_raster(x$raster))
  if (is.list(x) && !is.data.frame(x)) return(.wapor_result_layers(x, layers))
  stop("x must contain a SpatRaster", call. = FALSE)
}

#' Zonal Statistics for Any Polygons on Any WaPOR Raster
#'
#' Area-weighted statistics, volumes, crop share, data coverage and class shares
#' for polygons at one or several nested levels (for example scheme and farm),
#' on a raster or on the result of [wapor_run_seasonal_analysis()].
#'
#' @param x A `SpatRaster` (one layer per variable or time step), or the result
#'   of [wapor_run_seasonal_analysis()]. For a result the default layers are
#'   those present among `seasonal_aeti`, `seasonal_t`, `seasonal_ret`,
#'   `seasonal_pcp`, `seasonal_peff`, `etc`, `adequacy_etc`, `adequacy_p95`,
#'   `beneficial_fraction`, `green_water`, `blue_water`, `seasonal_biomass_t`
#'   and `yield_raster`; seasonal totals carry the unit mm.
#' @param zones Polygons: `sf`, `SpatVector` or a vector file path.
#' @param id One or more column names of `zones`, from coarse to fine. Several
#'   columns give nested levels; each level is computed from its own dissolved
#'   geometry, never by averaging the finer zones.
#' @param stats Statistics to return: `"mean"`, `"median"`, `"quantiles"` (at
#'   `probs`), `"sd"`, `"cv"`, `"cu"`, `"du_lq"`, `"gini"`, `"theil"`, `"min"`,
#'   `"max"`, `"count"`, `"n_eff"`, `"area_ha"`, `"mask_fraction"`,
#'   `"coverage"`, `"sum_volume"`, `"class_share"`. See Details.
#' @param probs Probabilities for `"quantiles"`.
#' @param mask Optional raster; cells where it is 0 or `NA` do not count.
#' @param weights Optional raster of fractions between 0 and 1, for example the
#'   crop fraction from [wapor_harmonize_mask()]. Prefer it to a hard mask at
#'   Level 1 and Level 2, where most pixels are mixed.
#' @param dissolve Merge polygons that share the same id values. Default `TRUE`.
#' @param aoi Add one row set for the union of all zones (level 0, id `"AOI"`).
#' @param classes Optional classified raster (integer codes, optionally with
#'   category labels). With `"class_share"` its classes are reported instead of
#'   classes of `x`.
#' @param breaks,labels,method,scheme Classify the values of `x` for
#'   `"class_share"` with [wapor_classify()].
#' @param min_coverage Zones with a smaller valid share of their masked area
#'   get `NA` statistics (areas, `count` and `n_eff` are still reported).
#' @param min_cell_fraction Drop cells of which a smaller fraction is covered
#'   by the zone (removes mixed edge pixels from spread statistics).
#' @param min_mask_area_ha Zones with a smaller masked area get `NA` statistics.
#' @param sd_type `"population"` (default, as in the IHE Delft WaPOR protocol)
#'   or `"sample"`.
#' @param days Days per layer, to turn rates (mm/day) into depths for
#'   `"sum_volume"`: a numeric vector in layer order, or a data frame with
#'   columns `layer` and `days`.
#' @param season Optional season label written to the `season` column.
#' @param normalize_id Build `zone_key` as upper case without surrounding
#'   blanks, so that `" f01 "` and `"F01"` match. Default `TRUE`.
#' @param layers Layers of `x` to use (names or indices; output names for an
#'   analysis result).
#' @param format `"long"` (default), `"wide"` (see [wapor_zonal_wide()]) or
#'   `"sf"` (the wide table of the finest level and the AOI, with geometry).
#'
#' @return For `format = "long"` a data frame of class `wapor_zonal` with one
#'   row per zone, layer and statistic: `level` (0 = AOI, 1 = first id column,
#'   ...), `zone_id`, `zone_key`, the id columns, `season`, `variable`,
#'   `period`, `stat`, `class`, `value`, `unit`. Attribute `"wapor_zonal_call"`
#'   records the settings; `"wapor_classes"` the classes of `"class_share"`.
#'
#' @details
#' Each cell counts with the weight `w = a * m * f`: `a` is the area of the
#' cell covered by the zone in m2 (from exactextractr; for lon/lat rasters the
#' covered fraction times the cell's area on the WGS84 ellipsoid), `m` the
#' mask (1 inside), `f` the weight fraction. Cells with data and `w > 0` are
#' the valid cells.
#'
#' * `area_ha`: area of the zone geometry (lon/lat zones are measured in an
#'   equal-area projection). `mask_fraction` = masked area / zone area (the
#'   crop share). `coverage` = valid area / masked area (the data share). The
#'   two are different questions and are reported separately.
#' * `mean` = `sum(w v) / sum(w)`; `median` and `quantiles` are weighted and
#'   equal `quantile(type = 7)` for equal weights.
#' * `sd`: population `sqrt(sum(w (v - mean)^2) / sum(w))`; the sample form
#'   multiplies the variance by `V1^2 / (V1^2 - V2)` with `V1 = sum(w)`,
#'   `V2 = sum(w^2)`. `cv` = `sd / mean`.
#' * `cu` = `1 - sum(w |v - mean|) / (mean sum(w))` (Christiansen, 1942).
#'   `du_lq` = mean of the lowest quarter of the weight / mean (Merriam and
#'   Keller, 1978). `gini` and `theil` (over `v > 0`) are weighted.
#' * `count` = number of valid cells; `n_eff` = sum of their covered fractions.
#' * `sum_volume` (m3, and `sum_volume_mcm` in million m3) =
#'   `sum(depth / 1000 * w)`. Depth units (`mm`, `mm/season`, `mm/month`,
#'   `mm/year`, `mm/dekad`) are used as they are; rates (`mm/day`) need `days`.
#'   Layers with another or no unit give no volume, with a warning.
#' * `class_share`: `class_area_ha` per class and `class_pct` = class area /
#'   valid area * 100 (the denominator is the area with data, so the shares
#'   sum to 100), plus the area without data as class `"no data"`. Every class
#'   is listed, also with zero area, when the classes are known (labels, a
#'   scheme, or a categorical raster).
#'
#' Resolution: a warning is given when a zone holds fewer than about 3 x 3
#' whole cells (`n_eff < 9`) and spread statistics are requested; they are not
#' reliable there (heuristic). At 100 m and 300 m most cells along field
#' borders are mixed: use `weights`, or `min_cell_fraction`.
#'
#' Layers are read in groups sized to `options(Rwapor.memory_budget_mb)`.
#'
#' @seealso [wapor_zonal_wide()], [wapor_classify()], [wapor_harmonize_mask()].
#' @export
#' @examples
#' r <- terra::rast(nrows = 10, ncols = 10, xmin = 700000, xmax = 700200,
#'                  ymin = 3600000, ymax = 3600200, crs = "EPSG:32636", vals = 1:100)
#' names(r) <- "aeti"
#' terra::units(r) <- "mm"
#' half <- sf::st_sf(farm = "west", geometry = sf::st_as_sfc(sf::st_bbox(
#'   c(xmin = 700000, ymin = 3600000, xmax = 700100, ymax = 3600200), crs = 32636)))
#' wapor_zonal_stats(r, half, id = "farm", stats = c("mean", "area_ha", "sum_volume"), aoi = FALSE)
wapor_zonal_stats <- function(x, zones, id, stats = c("mean", "area_ha", "mask_fraction", "coverage"),
                               probs = c(.1, .9), mask = NULL, weights = NULL, dissolve = TRUE, aoi = TRUE,
                               classes = NULL, breaks = NULL, labels = NULL, method = NULL, scheme = NULL,
                               min_coverage = .5, min_cell_fraction = 0, min_mask_area_ha = 0,
                               sd_type = c("population", "sample"), days = NULL, season = NULL,
                               normalize_id = TRUE, layers = NULL, format = c("long", "wide", "sf")) {
  sd_type <- match.arg(sd_type); format <- match.arg(format)
  src <- .wapor_zonal_source(x, layers)
  r <- src$raster; units <- src$units
  z <- .wapor_zone_sf(zones)
  if (missing(id) || !length(id) || any(!id %in% names(z))) stop(sprintf("id columns missing; available columns: %s", paste(names(z), collapse = ", ")), call. = FALSE)
  reserved <- c("level", "zone_id", "zone_key", "season", "variable", "period", "stat", "class", "value", "unit")
  if (any(id %in% reserved)) stop(sprintf("id columns cannot be named: %s", paste(intersect(id, reserved), collapse = ", ")), call. = FALSE)
  if (is.data.frame(days) && !all(c("layer", "days") %in% names(days))) stop("a 'days' data frame needs the columns 'layer' and 'days'", call. = FALSE)
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
    ao <- sf::st_sf(stats::setNames(as.list(rep(NA_character_, length(id))), id), geometry = sf::st_union(sf::st_geometry(z)))
    ao[[id[1]]] <- "AOI"; ao$.level <- 0L
    z <- rbind(z, ao)
  }
  z <- sf::st_transform(z, terra::crs(r))
  align <- function(a, method) terra::resample(if (inherits(a, "SpatRaster")) a else terra::rast(a), r, method = method)
  if (!is.null(mask)) mask <- align(mask, "near")
  if (!is.null(weights)) weights <- align(weights, "bilinear")
  if (!is.null(weights)) {
    # Range from the first layer, read block-wise by terra rather than as one vector.
    w_range <- as.numeric(unlist(terra::global(weights[[1]], "range", na.rm = TRUE)))
    if (any(is.finite(w_range)) && (min(w_range, na.rm = TRUE) < 0 || max(w_range, na.rm = TRUE) > 1)) stop("weights must be between 0 and 1", call. = FALSE)
  }
  class_levels <- NULL
  if (!is.null(classes)) {
    if (!inherits(classes, "SpatRaster") || terra::nlyr(classes) != 1L) stop("classes must be a single-layer SpatRaster", call. = FALSE)
    lv <- tryCatch(terra::levels(classes)[[1]], error = function(e) NULL)
    if (is.data.frame(lv) && ncol(lv) >= 2L) class_levels <- list(codes = as.integer(lv[[1]]), labels = as.character(lv[[2]]))
    class_name <- names(classes)[1]
    classes <- align(classes, "near")
  }
  nval <- terra::nlyr(r); nzone <- nrow(z)
  lonlat <- isTRUE(terra::is.lonlat(r))
  geom_area <- .wapor_zone_area_ha(z, lonlat)
  id_values <- lapply(id, function(nm) as.character(sf::st_drop_geometry(z)[[nm]]))
  names(id_values) <- id
  zone_id <- vapply(seq_len(nzone), function(j) {
    parts <- vapply(id_values, function(v) v[j], character(1))
    paste(parts[!is.na(parts)], collapse = "|")
  }, character(1))
  zone_key <- if (normalize_id) vapply(seq_len(nzone), function(j) {
    parts <- vapply(id_values, function(v) v[j], character(1))
    paste(toupper(trimws(parts[!is.na(parts)])), collapse = "|")
  }, character(1)) else zone_id
  season_value <- if (is.null(season)) NA_character_ else as.character(season)
  days_of <- function(k) {
    if (is.null(days)) return(NA_real_)
    if (is.data.frame(days)) return(as.numeric(days$days[match(names(r)[k], days$layer)]))
    as.numeric(days)[min(k, length(days))]
  }
  n_extra <- (!is.null(mask)) + (!is.null(weights)) + (!is.null(classes))
  spread_stats <- any(c("sd", "cv", "cu", "du_lq", "gini", "theil", "quantiles") %in% stats)
  need <- function(s) s %in% stats
  # Categorical value layers know their classes, so empty classes can be listed.
  layer_levels <- lapply(seq_len(nval), function(k) {
    lv <- tryCatch(terra::levels(r[[k]])[[1]], error = function(e) NULL)
    if (is.data.frame(lv) && ncol(lv) >= 2L) list(codes = as.integer(lv[[1]]), labels = as.character(lv[[2]])) else NULL
  })

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

  class_rows <- function(add, codes, ok, w, labs, used, mask_area, valid_area) {
    den <- sum(w[ok])
    for (code in used) {
      lab <- if (!is.null(labs) && !is.na(match(code, labs$codes))) labs$labels[match(code, labs$codes)] else as.character(code)
      hit <- ok & !is.na(codes) & codes == code
      add("class_area_ha", sum(w[hit])/1e4, "ha", lab)
      add("class_pct", if (den > 0) 100 * sum(w[hit]) / den else NA_real_, "percent", lab)
    }
    add("class_area_ha", mask_area - valid_area, "ha", "no data")
  }

  # One slot per zone and layer, filled in any order and read back zone by zone.
  slots <- vector("list", nzone * nval)
  class_slots <- vector("list", nzone)
  no_overlap <- logical(nzone)
  cov_flag <- vol_flag <- unit_flag <- matrix(FALSE, nzone, nval)
  n_eff_flag <- FALSE
  ext <- NULL
  for (ch in chunks) {
    # Release the previous group before reading the next, so that peak memory
    # follows one group and not how late the garbage collector runs.
    ext <- d <- NULL
    if (length(chunks) > 1L) invisible(gc(verbose = FALSE))
    ext_stack <- c(r[[ch]], mask, weights, classes)
    names(ext_stack) <- paste0("zonal_", seq_len(terra::nlyr(ext_stack)))
    # Projected rasters: covered area straight from exactextractr. Lon/lat rasters: covered
    # fraction times the ellipsoidal cell area (exactextractr would use a sphere).
    ext <- exactextractr::exact_extract(ext_stack, z, coverage_area = !lonlat, include_xy = lonlat,
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
      if (lonlat) {
        frac <- d$coverage_fraction
        a <- frac * .wapor_lonlat_cell_area(d$y, terra::xres(r), terra::yres(r))
      } else {
        a <- d$coverage_area
        frac <- d$coverage_fraction
        if (is.null(frac)) {
          cell_a <- abs(terra::xres(r) * terra::yres(r))
          frac <- pmin(1, a / cell_a)
        }
      }
      m <- if (!is.null(mask)) d[[nch + 1L]] else rep(1, length(a))
      f <- if (!is.null(weights)) d[[nch + 1L + !is.null(mask)]] else rep(1, length(a))
      keep <- frac >= min_cell_fraction; a <- a[keep]; m <- as.numeric(m[keep]); f <- as.numeric(f[keep]); frac <- frac[keep]
      w <- a * ifelse(is.na(m), 0, m) * ifelse(is.na(f), 0, f)
      mask_area <- sum(w, na.rm = TRUE)/1e4
      if (!is.null(classes) && need("class_share") && is.null(class_slots[[j]])) {
        # Class shares of the 'classes' raster: once per zone, independent of the value layers.
        codes <- as.integer(d[[nch + n_extra]][keep]); ok_c <- is.finite(codes) & w > 0   # classes is the last raster column
        st <- character(0); cl <- character(0); un <- character(0); va <- list()
        add <- function(stat, value, unit = NA_character_, class = NA_character_) {
          n <- length(st) + 1L
          st[n] <<- stat; cl[n] <<- class; un[n] <<- unit; va[[n]] <<- value
        }
        labs <- if (!is.null(class_levels)) class_levels else if (!is.null(labels)) list(codes = seq_along(labels), labels = as.character(labels)) else NULL
        used <- if (!is.null(labs)) labs$codes else sort(unique(codes[ok_c]))
        class_rows(add, codes, ok_c, w, labs, used, mask_area, sum(w[ok_c])/1e4)
        class_slots[[j]] <- list(stat = st, class = cl, unit = un, value = va)
      }
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
        if (need("median")) add("median", if (!blocked) .wapor_wquantile(vo, wo, .5) else NA_real_, units[k])
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
            if (is.na(days_of(k))) { vol_flag[j, k] <- TRUE; NULL } else v * days_of(k)
          } else if (u %in% c("mm", "mm/season", "mm/month", "mm/year", "mm/dekad")) v else { unit_flag[j, k] <- TRUE; NULL }
          if (!is.null(dd) && any(is.finite(dd[ok])) && !blocked) {
            volume <- sum(dd[ok]/1000*w[ok])
            add("sum_volume", volume, "m3")
            add("sum_volume_mcm", volume / 1e6, "Mm3")
          }
        }
        if (need("class_share") && is.null(classes)) {
          classify <- !is.null(scheme) || !is.null(breaks)
          if (!classify && !all(v[ok] == as.integer(v[ok]))) {
            stop("class_share needs an integer classified layer, or breaks/scheme to classify first", call. = FALSE)
          }
          codes <- if (classify) {
            cls <- wapor_classify(v, breaks = breaks, labels = labels, method = if (is.null(method)) "fixed" else method, scheme = scheme)
            as.integer(cls)
          } else as.integer(v)
          labs <- if (!is.null(labels)) list(codes = seq_along(labels), labels = as.character(labels)) else if (!is.null(scheme)) {
            sl <- wapor_class_defaults(scheme)$labels; list(codes = seq_along(sl), labels = as.character(sl))
          } else if (classify) { n_cls <- length(breaks) + 1L; list(codes = seq_len(n_cls), labels = as.character(seq_len(n_cls)))
          } else layer_levels[[k]]
          used <- if (!is.null(labs)) labs$codes else sort(unique(codes[ok]))
          class_rows(add, codes, ok, w, labs, used, mask_area, valid_area)
        }
        if (length(st)) slots[[(j - 1L) * nval + k]] <- list(stat = st, class = cl, unit = un, value = va)
      }
    }
  }
  # Warning inputs in zone-by-zone, layer-by-layer order.
  cov_warn <- rep(zone_key, each = nval)[as.vector(t(cov_flag))]
  vol_warn <- rep(names(r), times = nzone)[as.vector(t(vol_flag))]
  if (length(cov_warn)) warning(sprintf("zones below min_coverage: %s", paste(unique(utils::head(cov_warn, 5)), collapse = ", ")), call. = FALSE)
  if (n_eff_flag) warning("fewer than about 3 x 3 whole cells: spread statistics are unreliable at this resolution", call. = FALSE)
  if (length(unique(vol_warn))) warning(sprintf("sum_volume skipped for rate layers without days: %s", paste(unique(vol_warn), collapse = ", ")), call. = FALSE)
  unit_warn <- rep(names(r), times = nzone)[as.vector(t(unit_flag))]
  if (length(unique(unit_warn))) warning(sprintf("sum_volume skipped for layers whose unit is not a depth (mm) or a rate (mm/day): %s", paste(unique(unit_warn), collapse = ", ")), call. = FALSE)

  n_rows <- lengths(lapply(slots, `[[`, "stat"))
  zone_index <- rep(rep(seq_len(nzone), each = nval), times = n_rows)
  layer_index <- rep(rep(seq_len(nval), times = nzone), times = n_rows)
  variable <- names(r)[layer_index]
  pick <- function(field, from) unlist(lapply(from, `[[`, field))
  stat <- pick("stat", slots); class_col <- pick("class", slots); value <- pick("value", slots); unit <- pick("unit", slots)
  if (!is.null(classes) && need("class_share")) {
    n_class <- lengths(lapply(class_slots, `[[`, "stat"))
    zone_index <- c(zone_index, rep(seq_len(nzone), times = n_class))
    variable <- c(variable, rep(class_name, sum(n_class)))
    stat <- c(stat, pick("stat", class_slots)); class_col <- c(class_col, pick("class", class_slots))
    value <- c(value, pick("value", class_slots)); unit <- c(unit, pick("unit", class_slots))
    o <- order(zone_index, method = "radix")          # stable: class rows follow the zone's value rows
    zone_index <- zone_index[o]; variable <- variable[o]; stat <- stat[o]; class_col <- class_col[o]
    value <- value[o]; unit <- unit[o]
  }
  ans <- if (length(zone_index)) {
    data.frame(level = z$.level[zone_index], zone_id = zone_id[zone_index], zone_key = zone_key[zone_index],
               lapply(id_values, function(v) v[zone_index]),
               season = season_value, variable = variable, period = NA_character_,
               stat = stat, class = class_col, value = value, unit = unit,
               stringsAsFactors = FALSE, check.names = FALSE)
  } else data.frame()
  class(ans) <- c("wapor_zonal", "data.frame")
  attr(ans, "wapor_zonal_call") <- list(
    stats = stats, sd_type = sd_type, id = id, probs = probs, mask = !is.null(mask), weights = !is.null(weights),
    min_coverage = min_coverage, min_cell_fraction = min_cell_fraction, min_mask_area_ha = min_mask_area_ha,
    area_method = if (terra::is.lonlat(r)) "equal-area projection (lon/lat zones)" else "planar (projected CRS)"
  )
  if (need("class_share")) {
    attr(ans, "wapor_classes") <- list(scheme = scheme, breaks = breaks, method = method,
                                       labels = if (!is.null(class_levels)) class_levels$labels else labels)
  }
  if (format == "long") return(ans)
  wide <- wapor_zonal_wide(ans)
  if (format == "wide") return(wide)
  # sf: the finest level and the AOI, one row per zone and variable, with the zone geometry.
  wide <- wide[wide$level %in% c(0L, max(z$.level)), , drop = FALSE]
  zone_row <- match(paste(wide$level, wide$zone_key), paste(z$.level, zone_key))
  sf::st_sf(wide, geometry = sf::st_geometry(z)[zone_row])
}

#' One Row per Zone and Variable from a Long Zonal Table
#'
#' @param z A long table returned by [wapor_zonal_stats()].
#' @return A data frame with `level`, `zone_id`, `zone_key`, the id columns,
#'   `season` and `variable`, and one column per statistic. Class rows become
#'   columns named `<stat>.<class>` (for example `class_pct.good`).
#' @export
wapor_zonal_wide <- function(z) {
  if (!is.data.frame(z)) stop("z must be a data frame returned by wapor_zonal_stats", call. = FALSE)
  if (!nrow(z)) return(data.frame())
  id <- attr(z, "wapor_zonal_call")$id
  keys <- intersect(c("level", "zone_id", "zone_key", id, "season", "variable"), names(z))
  z <- as.data.frame(z)
  column <- ifelse(is.na(z$class), z$stat, paste(z$stat, z$class, sep = "."))
  row_key <- paste(if ("level" %in% names(z)) z$level else "", z$zone_key, z$variable, sep = "\034")
  rows <- !duplicated(row_key)
  out <- z[rows, keys, drop = FALSE]
  rownames(out) <- NULL
  for (nm in unique(column)) {
    hit <- column == nm
    out[[nm]] <- z$value[hit][match(row_key[rows], row_key[hit])]
  }
  out
}
