# Irrigation performance indicators, productivity gaps and spots (P2 WP3).

.wapor_pi_is_rast <- function(x) inherits(x, "SpatRaster")

.wapor_pi_vals <- function(x) {
  if (.wapor_pi_is_rast(x)) as.numeric(terra::values(x[[1]])[, 1]) else as.numeric(x)
}

.wapor_pi_wrap <- function(template, vals, name = NULL) {
  if (.wapor_pi_is_rast(template)) {
    out <- terra::setValues(template[[1]], vals)
    if (!is.null(name)) names(out) <- name
    return(out)
  }
  vals
}

.wapor_pi_cv <- function(x, w = NULL, sd_type = "population") {
  if (is.null(w)) w <- rep(1, length(x))
  .wapor_wsd(x, w, sd_type = sd_type) / .wapor_wmean(x, w)
}

.wapor_pi_meta <- function(x, meta) {
  attr(x, "wapor_performance") <- meta
  x
}

.wapor_pi_units <- function(units, template, id) {
  if (is.numeric(units) && length(units) == 1L) {
    if (isTRUE(terra::is.lonlat(template))) {
      stop("block size in metres needs a projected CRS; supply polygons or terra::project()", call. = FALSE)
    }
    e <- terra::ext(template)
    bb <- sf::st_bbox(c(xmin = e[1], xmax = e[2], ymin = e[3], ymax = e[4]), crs = terra::crs(template))
    grid <- sf::st_make_grid(sf::st_as_sfc(bb), cellsize = units, square = TRUE)
    units <- sf::st_sf(block_id = as.character(seq_along(grid)), geometry = grid)
    if (is.null(id)) id <- "block_id"
  }
  z <- .wapor_zone_sf(units)
  if (is.null(id)) {
    nm <- setdiff(names(sf::st_drop_geometry(z)), character())
    if (!length(nm)) stop("id is required", call. = FALSE)
    id <- nm[[1]]
  }
  list(zones = z, id = id)
}

.wapor_pi_align <- function(x, y) {
  if (!.wapor_pi_is_rast(x) || !.wapor_pi_is_rast(y)) return(list(x = x, y = y))
  if (!terra::compareGeom(x, y, stopOnError = FALSE, crs = TRUE, ext = TRUE, rowcol = TRUE, res = TRUE)) {
    y <- terra::resample(y, x, method = "bilinear")
  }
  list(x = x, y = y)
}

.wapor_pi_groups <- function(x, reference, id) {
  n <- if (.wapor_pi_is_rast(x)) terra::ncell(x) else length(.wapor_pi_vals(x))
  if (is.null(reference)) return(rep("all", n))
  .wapor_class_groups(if (.wapor_pi_is_rast(x)) x else .wapor_pi_vals(x), reference, id)
}

.wapor_pi_as_stack <- function(x) {
  if (.wapor_pi_is_rast(x)) return(x)
  if (is.list(x) && !is.data.frame(x)) {
    if (!is.null(x$rasters)) x <- x$rasters
    if (is.list(x) && length(x) && .wapor_pi_is_rast(x[[1]])) return(terra::rast(x))
  }
  if (is.numeric(x)) return(x)
  stop("expected a SpatRaster, a list of SpatRasters, or numeric values", call. = FALSE)
}

#' Classify irrigation adequacy (AETI / ETc)
#'
#' Wrapper for [wapor_classify()] with scheme `"adequacy"`. Formula: class of
#' the ratio AETI/ETc. Default breaks 0.68, 0.80, 1.00 (poor / acceptable /
#' good / above ETc). Class 4 is a package extension, not a published
#' over-irrigation class; for deficit irrigation, rainfed crops and salinity,
#' a "poor" class can be intended management.
#'
#' @param adequacy Numeric vector or SpatRaster of AETI/ETc.
#' @param breaks,labels,right Passed to [wapor_classify()].
#' @return A factor or categorical SpatRaster.
#' @source Karimi et al. (2019); Chukalla et al. (2022).
#' @export
#' @examples
#' wapor_classify_adequacy(c(0.68, 0.8, 1, 1.01))
wapor_classify_adequacy <- function(adequacy, breaks = NULL, labels = NULL, right = TRUE) {
  wapor_classify(adequacy, breaks = breaks, labels = labels, scheme = "adequacy", right = right)
}

#' Relative water deficit
#'
#' RWD = 1 - AETI / ETx, with ETx = ETc (`etx_method = "etc"`) or the type-7
#' percentile `p` of AETI within each reference group (`"percentile"`). The
#' IHE Delft protocol uses ETp or P99; package adequacy uses P95. Values are
#' not clamped. Also returns the deficit depth ETx - AETI (mm).
#'
#' @param aeti Actual evapotranspiration (mm), numeric or SpatRaster.
#' @param etx Optional ETc (or other demand) raster or numeric. Required when
#'   `etx_method = "etc"`.
#' @param etx_method `"etc"` or `"percentile"`.
#' @param p Percentile of AETI when `etx_method = "percentile"` (default 0.95).
#' @param reference,id Grouping for the percentile, as in [wapor_classify()].
#' @return A list with `rwd`, `deficit_mm` and `etx`.
#' @source Bastiaanssen and Bos (1999); Chukalla et al. (2020) WAPORWP Module 3.
#' @export
wapor_calc_rwd <- function(aeti, etx = NULL, etx_method = c("etc", "percentile"),
                           p = 0.95, reference = NULL, id = NULL) {
  etx_method <- match.arg(etx_method)
  if (!is.numeric(p) || length(p) != 1L || p <= 0 || p >= 1) stop("p must be a probability in (0, 1)", call. = FALSE)
  av <- .wapor_pi_vals(aeti)
  if (etx_method == "etc") {
    if (is.null(etx)) stop("etx is required when etx_method = \"etc\"", call. = FALSE)
    aligned <- .wapor_pi_align(aeti, etx)
    aeti <- aligned$x
    etx <- aligned$y
    ev <- .wapor_pi_vals(etx)
    if (length(ev) == 1L) ev <- rep(ev, length(av))
  } else {
    groups <- .wapor_pi_groups(aeti, reference, id)
    ev <- rep(NA_real_, length(av))
    for (g in unique(groups)) {
      ix <- which(groups == g & is.finite(av))
      if (!length(ix)) next
      ev[groups == g] <- as.numeric(stats::quantile(av[ix], probs = p, type = 7, names = FALSE))
    }
  }
  rwd <- ifelse(!is.finite(ev) | ev == 0, NA_real_, 1 - av / ev)
  deficit <- ifelse(!is.finite(ev), NA_real_, ev - av)
  out <- list(
    rwd = .wapor_pi_wrap(aeti, rwd, "rwd"),
    deficit_mm = .wapor_pi_wrap(aeti, deficit, "deficit_mm"),
    etx = if (.wapor_pi_is_rast(aeti) && etx_method == "percentile") .wapor_pi_wrap(aeti, ev, "etx") else if (.wapor_pi_is_rast(etx)) etx else ev
  )
  if (length(unique(ev[is.finite(ev)])) == 1L) out$etx <- unique(ev[is.finite(ev)])
  .wapor_pi_meta(out, list(etx_method = etx_method, p = p, formula = "RWD = 1 - AETI/ETx"))
}

#' Irrigation uniformity within units
#'
#' Per unit: `uniformity_cv = 1 - CV` (Chukalla proxy), Christiansen CU, and
#' low-quarter DU. Classes come from `uniformity_<method>` and are applied to
#' `uniformity_cv`. With `irrigation_method = "unknown"` only values are
#' returned. Units smaller than `min_area_ha` are NA.
#'
#' The method standards are for applied water. 1 - CV of ET overstates
#' irrigation uniformity; DU_lq is the closer comparison. Blocks generated
#' from a numeric size measure landscape heterogeneity, not field uniformity.
#'
#' @param aeti SpatRaster of AETI (or another ET layer).
#' @param units `sf` polygons, SpatVector, file path, or a single number:
#'   block size in metres (projected CRS required).
#' @param id Polygon id column. Default: first attribute, or `block_id`.
#' @param mask,weights Passed to [wapor_zonal_stats()].
#' @param irrigation_method One of `unknown`, `surface`, `sprinkler`, `pivot`, `drip`.
#' @param measures Statistics to return.
#' @param min_area_ha Units below this valid area (ha) get NA (default 1; heuristic).
#' @param min_cell_fraction Passed to the zonal engine (default 0.5; heuristic).
#' @param sd_type `"population"` (default) or `"sample"`.
#' @return A data frame, one row per unit.
#' @source Chukalla et al. (2022); Pitts et al. (1996); Christiansen (1942);
#'   Merriam and Keller (1978).
#' @export
wapor_calc_uniformity <- function(aeti, units, id = NULL, mask = NULL, weights = NULL,
                                  irrigation_method = c("unknown", "surface", "sprinkler", "pivot", "drip"),
                                  measures = c("uniformity_cv", "cu", "du_lq"),
                                  min_area_ha = 1, min_cell_fraction = 0.5,
                                  sd_type = "population") {
  irrigation_method <- match.arg(irrigation_method)
  sd_type <- match.arg(sd_type, c("population", "sample"))
  if (!.wapor_pi_is_rast(aeti)) stop("aeti must be a SpatRaster", call. = FALSE)
  u <- .wapor_pi_units(units, aeti, id)
  stats <- unique(c("cv", "cu", "du_lq", "area_ha", "n_eff", "count"))
  z <- wapor_zonal_stats(
    aeti, u$zones, id = u$id, stats = stats, mask = mask, weights = weights,
    aoi = FALSE, min_cell_fraction = min_cell_fraction, min_coverage = 0,
    min_mask_area_ha = 0, sd_type = sd_type, format = "wide"
  )
  z <- z[z$level == max(z$level), , drop = FALSE]
  out <- z
  out$uniformity_cv <- 1 - z$cv
  small <- is.finite(z$area_ha) & z$area_ha < min_area_ha
  if (any(small)) {
    out$uniformity_cv[small] <- NA_real_
    out$cu[small] <- NA_real_
    out$du_lq[small] <- NA_real_
    out$cv[small] <- NA_real_
  }
  thin <- is.finite(z$n_eff) & z$n_eff < 9
  if (any(thin)) warning("some units have n_eff < 9; uniformity is not reliable there", call. = FALSE)
  if (!identical(irrigation_method, "unknown")) {
    scheme <- paste0("uniformity_", irrigation_method)
    cls <- wapor_classify(out$uniformity_cv, scheme = scheme)
    out$class <- as.character(cls)
    out$class[is.na(out$uniformity_cv)] <- NA_character_
  }
  keep <- unique(c(u$id, "zone_id", "zone_key", "area_ha", "n_eff", "count",
                   intersect(c("uniformity_cv", "cv", "cu", "du_lq", "class"), names(out))))
  keep <- intersect(keep, names(out))
  .wapor_pi_meta(out[keep], list(
    irrigation_method = irrigation_method, min_area_ha = min_area_ha,
    min_cell_fraction = min_cell_fraction, sd_type = sd_type,
    measures = measures,
    note = "1 - CV of ET is a proxy for applied-water uniformity and can overstate it; DU_lq is the closer comparison"
  ))
}

#' Equity of ET between units
#'
#' CV of the unit means (unweighted by default, as in the literature). Optional
#' area weighting. Class from scheme `equity` (good / fair / poor).
#'
#' @param aeti SpatRaster.
#' @param units Polygons or a block size in metres (see [wapor_calc_uniformity()]).
#' @param id,mask,weights,min_area_ha,sd_type As in [wapor_calc_uniformity()].
#' @param unit_weights `"none"` (default) or `"area"`.
#' @return A list with `cv`, `class`, `unit_means` and settings.
#' @source Bastiaanssen et al. (1996); Chukalla et al. (2022).
#' @export
wapor_calc_equity <- function(aeti, units, id = NULL, mask = NULL, weights = NULL,
                              unit_weights = c("none", "area"), min_area_ha = 1,
                              sd_type = "population") {
  unit_weights <- match.arg(unit_weights)
  sd_type <- match.arg(sd_type, c("population", "sample"))
  if (!.wapor_pi_is_rast(aeti)) stop("aeti must be a SpatRaster", call. = FALSE)
  u <- .wapor_pi_units(units, aeti, id)
  z <- wapor_zonal_stats(
    aeti, u$zones, id = u$id, stats = c("mean", "area_ha"), mask = mask, weights = weights,
    aoi = FALSE, min_coverage = 0, min_mask_area_ha = 0, sd_type = sd_type, format = "wide"
  )
  z <- z[z$level == max(z$level), , drop = FALSE]
  keep <- is.finite(z$mean) & (is.na(z$area_ha) | z$area_ha >= min_area_ha)
  means <- z$mean[keep]
  w <- if (unit_weights == "area") z$area_ha[keep] else rep(1, length(means))
  cv <- .wapor_pi_cv(means, w, sd_type = sd_type)
  cls <- as.character(wapor_classify(cv, scheme = "equity"))
  .wapor_pi_meta(
    list(cv = cv, class = cls, unit_means = means, sd_type = sd_type, unit_weights = unit_weights),
    list(formula = "equity = CV of unit means", source = "Bastiaanssen et al. (1996); Chukalla et al. (2022)")
  )
}

#' Temporal reliability of relative ET
#'
#' Population (default) or sample CV over time of AETI/ETc per pixel, or per
#' zone through [wapor_zonal_stats()]. Monthly relative ET is the intended
#' input; dekadal relative ET is noisy. No default class scheme (Molden and
#' Gates 1990 bands are secondary and unverified for ET).
#'
#' @param ratio_stack SpatRaster stack of AETI_t / ETc_t, or the output of
#'   [wapor_relative_et_stack()].
#' @param zones Optional polygons for a zonal series.
#' @param id Zone id column.
#' @param sd_type `"population"` or `"sample"`.
#' @return A SpatRaster of CV (pixel mode) or a data frame (zone mode).
#' @source Bastiaanssen and Bos (1999).
#' @export
wapor_calc_reliability <- function(ratio_stack, zones = NULL, id = NULL,
                                   sd_type = "population") {
  sd_type <- match.arg(sd_type, c("population", "sample"))
  ratio_stack <- .wapor_pi_as_stack(ratio_stack)
  cv_fun <- function(v) {
    v <- v[is.finite(v)]
    if (length(v) < 2L) return(NA_real_)
    mu <- mean(v)
    if (!is.finite(mu) || mu == 0) return(NA_real_)
    s <- if (identical(sd_type, "sample")) stats::sd(v) else sqrt(mean((v - mu)^2))
    s / mu
  }
  if (is.null(zones)) {
    if (!.wapor_pi_is_rast(ratio_stack)) stop("ratio_stack must be a SpatRaster", call. = FALSE)
    out <- terra::app(ratio_stack, fun = cv_fun)
    names(out) <- "reliability_cv"
    return(.wapor_pi_meta(out, list(sd_type = sd_type, formula = "CV_t(AETI/ETc)")))
  }
  u <- .wapor_pi_units(zones, ratio_stack, id)
  z <- wapor_zonal_stats(
    ratio_stack, u$zones, id = u$id, stats = "mean", aoi = FALSE, min_coverage = 0, format = "long"
  )
  z <- z[z$level == max(z$level) & z$stat == "mean", , drop = FALSE]
  split_z <- split(z, z$zone_key)
  ans <- do.call(rbind, lapply(split_z, function(d) {
    data.frame(
      zone_key = d$zone_key[[1]],
      reliability_cv = cv_fun(d$value),
      stringsAsFactors = FALSE
    )
  }))
  rownames(ans) <- NULL
  .wapor_pi_meta(ans, list(sd_type = sd_type))
}

#' Build a stack of monthly relative ET (AETI / ETc)
#'
#' @param result A seasonal-analysis result with `monthly_aeti` and
#'   `monthly_etc`, or a list with those names.
#' @return A SpatRaster of AETI_t / ETc_t.
#' @export
wapor_relative_et_stack <- function(result) {
  pull <- function(x) {
    if (.wapor_pi_is_rast(x)) return(x)
    if (is.list(x) && !is.null(x$rasters)) x <- x$rasters
    if (is.list(x) && length(x) && .wapor_pi_is_rast(x[[1]])) return(terra::rast(x))
    stop("monthly_aeti / monthly_etc must be rasters", call. = FALSE)
  }
  a <- pull(result$monthly_aeti)
  e <- pull(result$monthly_etc)
  aligned <- .wapor_pi_align(a, e)
  e_safe <- terra::ifel(aligned$y == 0, NA, aligned$y)
  aligned$x / e_safe
}

#' Climate normalisation factor f_norm = mean(RET) / RET
#'
#' The mean is area-weighted over the masked area by default. Chukalla also
#' weights by field size and growing length; season-length weighting is the
#' caller's choice via per-season inputs.
#'
#' @param ret SpatRaster of reference evapotranspiration.
#' @param zones,id Unused in pixel mode; reserved for a zonal mean.
#' @param weights `"area"` (default) or `"none"`.
#' @param mask Optional mask (NA outside).
#' @return A SpatRaster of f_norm.
#' @source Chukalla et al. (2022) Eq. 3.
#' @export
wapor_calc_climate_norm <- function(ret, zones = NULL, id = NULL,
                                    weights = c("area", "none"), mask = NULL) {
  weights <- match.arg(weights)
  if (!.wapor_pi_is_rast(ret)) stop("ret must be a SpatRaster", call. = FALSE)
  r <- ret[[1]]
  if (!is.null(mask)) {
    aligned <- .wapor_pi_align(r, mask[[1]])
    r <- terra::mask(aligned$x, aligned$y)
  }
  if (identical(weights, "none")) {
    mu <- as.numeric(terra::global(r, "mean", na.rm = TRUE)$mean)
  } else {
    a <- terra::cellSize(r, unit = "m", transform = isTRUE(terra::is.lonlat(r)))
    a <- terra::mask(a, r)
    s1 <- as.numeric(terra::global(r * a, "sum", na.rm = TRUE)$sum)
    s0 <- as.numeric(terra::global(a, "sum", na.rm = TRUE)$sum)
    mu <- s1 / s0
  }
  out <- mu / r
  names(out) <- "f_norm"
  .wapor_pi_meta(out, list(mean_ret = mu, weights = weights, formula = "f_norm = mean(RET)/RET"))
}

#' Apply a climate normalisation factor
#'
#' Normalises water consumption depths or water productivity indicators to remove
#' the confounding effect of spatial climate variability (evaporative demand).
#'
#' Mathematical Derivation:
#' With climate factor \eqn{f_{norm} = \overline{RET} / RET}:
#' \itemize{
#'   \item \strong{Depth indicators (AETI, ETc in mm):} Multiplied by \eqn{f_{norm}}.
#'     \deqn{Depth_{norm} = Depth \times \frac{\overline{RET}}{RET}}
#'     Areas with higher evaporative demand (\eqn{RET > \overline{RET}}, so \eqn{f_{norm} < 1})
#'     have their consumed depth scaled downward to represent consumption under regional average demand.
#'   \item \strong{Productivity indicators (CWP, BWP in kg/m3):} Divided by \eqn{f_{norm}}.
#'     Since \eqn{WP = Yield / Depth}, normalising depth in the denominator yields:
#'     \deqn{WP_{norm} = \frac{Yield}{Depth_{norm}} = \frac{Yield}{Depth \times f_{norm}} = \frac{WP}{f_{norm}} = WP \times \frac{RET}{\overline{RET}}}
#'     Under harsh, high-evaporative climates, plants inevitably consume more water per kg biomass produced,
#'     depressing unadjusted WP. Dividing by \eqn{f_{norm}} compensates for this climatic penalty,
#'     enabling fair comparison of agricultural performance across diverse agro-climatic zones.
#' }
#'
#' @param x Numeric or SpatRaster.
#' @param f_norm Factor from [wapor_calc_climate_norm()].
#' @param type `"depth"` or `"productivity"`.
#' @return The same type as `x` (or a raster if `x` is a raster).
#' @references
#' Chukalla, A. D., Krol, M. S., & Hoekstra, A. Y. (2022). Climate normalisation of
#'   crop water productivity and irrigation performance indicators. Agricultural Water Management, 260, 107297.
#' @export
wapor_apply_climate_norm <- function(x, f_norm, type = c("depth", "productivity")) {
  type <- match.arg(type)
  if (.wapor_pi_is_rast(x) && .wapor_pi_is_rast(f_norm)) {
    aligned <- .wapor_pi_align(x, f_norm)
    x <- aligned$x
    f_norm <- aligned$y
  }
  out <- if (identical(type, "depth")) x * f_norm else x / f_norm
  .wapor_pi_meta(out, list(type = type, note = "UNVERIFIED as a published convention"))
}

#' Productivity target and gap
#'
#' Target = type-7 percentile `p` of `x` within the reference group (default
#' P95). Gap = max(0, target - x). Production gap = sum(gap x area), so t/ha
#' becomes tonnes when cell areas are in hectares.
#'
#' @param x Numeric or SpatRaster (for example yield or biomass).
#' @param p Percentile (default 0.95).
#' @param reference,id Grouping as in [wapor_classify()].
#' @param zones,zone_id Optional polygons to summarise production gap per zone.
#' @return A list with `gap`, `target` and `production_gap`.
#' @source Chukalla et al. (2020) WAPORWP Module 5.
#' @export
wapor_calc_productivity_gap <- function(x, p = 0.95, reference = NULL, id = NULL,
                                        zones = NULL, zone_id = NULL) {
  if (!is.numeric(p) || length(p) != 1L || p <= 0 || p >= 1) stop("p must be a probability in (0, 1)", call. = FALSE)
  xv <- .wapor_pi_vals(x)
  groups <- .wapor_pi_groups(x, reference, id)
  target <- rep(NA_real_, length(xv))
  for (g in unique(groups)) {
    ix <- which(groups == g & is.finite(xv))
    if (!length(ix)) next
    target[groups == g] <- as.numeric(stats::quantile(xv[ix], probs = p, type = 7, names = FALSE))
  }
  gap_v <- pmax(0, target - xv)
  gap <- .wapor_pi_wrap(x, gap_v, "gap")
  production_gap <- NA_real_
  if (.wapor_pi_is_rast(x)) {
    a_ha <- terra::cellSize(x[[1]], unit = "m", transform = isTRUE(terra::is.lonlat(x))) / 1e4
    production_gap <- as.numeric(terra::global(gap * a_ha, "sum", na.rm = TRUE)$sum)
  }
  target_out <- if (length(unique(target[is.finite(target)])) == 1L) unique(target[is.finite(target)]) else .wapor_pi_wrap(x, target, "target")
  out <- list(gap = gap, target = target_out, production_gap = production_gap)
  if (!is.null(zones) && .wapor_pi_is_rast(x)) {
    u <- .wapor_pi_units(zones, x, zone_id)
    try(terra::units(gap) <- "mm", silent = TRUE)
    vol <- wapor_zonal_stats(gap, u$zones, id = u$id, stats = "sum_volume", aoi = FALSE, min_coverage = 0)
    out$production_gap_by_zone <- vol
  }
  .wapor_pi_meta(out, list(p = p, formula = "gap = max(0, Pp - x)"))
}

#' Bright and dark productivity spots
#'
#' Protocol pair: land productivity `lp` (biomass or yield) and water
#' productivity `wp`. bright = lp >= P_high AND wp >= P_high; dark = lp <= P_low
#' AND wp <= P_low (package convention); else normal. Built with explicit
#' `>=` / `<=` (a value equal to a threshold is bright or dark). Zone mode
#' classifies zone means (recommended for management use).
#'
#' @param lp,wp Numeric or SpatRaster.
#' @param breaks Two values: either probabilities in (0, 1) (default 0.05, 0.95)
#'   or absolute thresholds (when any value is outside (0, 1)).
#' @param labels Unused; classes are dark / normal / bright.
#' @param reference,id Grouping for percentiles.
#' @param zones,zone_id Zone mode: classify means per polygon.
#' @param min_cell_fraction Reserved for pixel-mode edge filtering (heuristic).
#' @return A categorical SpatRaster, a factor, or a zone table.
#' @source Chukalla et al. (2020).
#' @export
wapor_classify_spots <- function(lp, wp, breaks = NULL, labels = NULL,
                                 reference = NULL, id = NULL, zones = NULL,
                                 zone_id = NULL, min_cell_fraction = 0.5) {
  def <- wapor_class_defaults("spots")
  if (is.null(breaks)) breaks <- def$breaks
  if (is.null(labels)) labels <- def$labels
  quantile_mode <- is.numeric(breaks) && length(breaks) == 2L && all(breaks > 0 & breaks < 1)
  lp_r <- .wapor_pi_is_rast(lp)
  if (lp_r && .wapor_pi_is_rast(wp)) {
    aligned <- .wapor_pi_align(lp, wp)
    lp <- aligned$x
    wp <- aligned$y
  }
  if (!is.null(zones) && lp_r) {
    u <- .wapor_pi_units(zones, lp, zone_id)
    zlp <- wapor_zonal_stats(lp, u$zones, id = u$id, stats = "mean", aoi = FALSE, min_coverage = 0,
                             min_cell_fraction = min_cell_fraction, format = "wide")
    zwp <- wapor_zonal_stats(wp, u$zones, id = u$id, stats = "mean", aoi = FALSE, min_coverage = 0,
                             min_cell_fraction = min_cell_fraction, format = "wide")
    zlp <- zlp[zlp$level == max(zlp$level), , drop = FALSE]
    zwp <- zwp[zwp$level == max(zwp$level), , drop = FALSE]
    m <- merge(zlp[, c("zone_key", u$id, "mean")], zwp[, c("zone_key", "mean")], by = "zone_key", suffixes = c("_lp", "_wp"))
    fac <- wapor_classify_spots(m$mean_lp, m$mean_wp, breaks = breaks, labels = labels, reference = NULL)
    m$class <- as.character(fac)
    return(.wapor_pi_meta(m, list(mode = "zone", min_cell_fraction = min_cell_fraction)))
  }
  lv <- .wapor_pi_vals(lp)
  wv <- .wapor_pi_vals(wp)
  if (length(lv) != length(wv)) stop("lp and wp must have the same length", call. = FALSE)
  groups <- .wapor_pi_groups(lp, reference, id)
  if (is.null(reference) && lp_r) {
    n_class <- length(unique(groups[!is.na(groups)]))
    if (n_class > 1L) warning("reference is NULL and more than one group is present; pass reference so each crop class has its own P5/P95", call. = FALSE)
  }
  code <- rep(2L, length(lv))
  plo <- phi <- rep(NA_real_, length(lv))
  for (g in unique(groups)) {
    ix <- which(groups == g)
    ok <- ix[is.finite(lv[ix]) & is.finite(wv[ix])]
    if (!length(ok)) next
    if (quantile_mode) {
      plo_g <- as.numeric(stats::quantile(lv[ok], probs = min(breaks), type = 7, names = FALSE))
      phi_g <- as.numeric(stats::quantile(lv[ok], probs = max(breaks), type = 7, names = FALSE))
      # Protocol pair: each variable has its own P_low / P_high.
      plo_w <- as.numeric(stats::quantile(wv[ok], probs = min(breaks), type = 7, names = FALSE))
      phi_w <- as.numeric(stats::quantile(wv[ok], probs = max(breaks), type = 7, names = FALSE))
    } else {
      plo_g <- min(breaks)
      phi_g <- max(breaks)
      plo_w <- plo_g
      phi_w <- phi_g
    }
    plo[ix] <- plo_g
    phi[ix] <- phi_g
    bright <- lv[ok] >= phi_g & wv[ok] >= phi_w
    dark <- lv[ok] <= plo_g & wv[ok] <= plo_w
    code[ok[bright]] <- 3L
    code[ok[dark]] <- 1L
  }
  code[!is.finite(lv) | !is.finite(wv)] <- NA_integer_
  if (lp_r) {
    out <- terra::setValues(lp[[1]], as.integer(code))
    levels(out) <- data.frame(value = seq_along(labels), class = labels)
    names(out) <- "spots"
    return(.wapor_pi_meta(out, list(breaks = breaks, quantile_mode = quantile_mode, min_cell_fraction = min_cell_fraction)))
  }
  out <- factor(code, levels = seq_along(labels), labels = labels)
  .wapor_pi_meta(out, list(breaks = breaks, quantile_mode = quantile_mode))
}

#' Net irrigation requirement
#'
#' NIR = sum over months of max(0, ETc_m - Peff_m) (mm). Compute monthly, then
#' sum, as for green/blue water. Volume via [wapor_zonal_stats()].
#'
#' @param etc_monthly Monthly ETc, numeric vector, SpatRaster stack, or list of rasters.
#' @param peff_monthly Monthly effective rainfall, same shape as `etc_monthly`.
#' @return Numeric or SpatRaster (mm).
#' @source Allen et al. (1998); Smith (1992) CROPWAT.
#' @export
wapor_calc_nir <- function(etc_monthly, peff_monthly) {
  if (is.numeric(etc_monthly) && is.numeric(peff_monthly)) {
    if (length(etc_monthly) != length(peff_monthly)) stop("etc_monthly and peff_monthly must have the same length", call. = FALSE)
    return(.wapor_pi_meta(sum(pmax(0, etc_monthly - peff_monthly)), list(formula = "NIR = sum max(0, ETc_m - Peff_m)")))
  }
  e <- .wapor_pi_as_stack(etc_monthly)
  p <- .wapor_pi_as_stack(peff_monthly)
  if (terra::nlyr(e) != terra::nlyr(p)) stop("etc_monthly and peff_monthly must have the same number of layers", call. = FALSE)
  aligned <- .wapor_pi_align(e, p)
  diff <- aligned$x - aligned$y
  nir <- terra::app(diff, function(v) sum(pmax(0, v), na.rm = TRUE))
  names(nir) <- "nir"
  .wapor_pi_meta(nir, list(formula = "NIR = sum max(0, ETc_m - Peff_m)"))
}
