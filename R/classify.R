#' Classification schemes and defaults
#'
#' @return `wapor_class_defaults()` returns a scheme list, or all schemes.
#' @export
#' @param scheme Optional scheme name.
#' @examples
#' wapor_class_defaults("adequacy")
wapor_class_defaults <- function(scheme = NULL) {
  schemes <- list(
    adequacy = list(
      breaks = c(0.68, 0.80, 1.00),
      labels = c("poor", "acceptable", "good", "above ETc"),
      method = "fixed", right = TRUE, direction = "higher_better", units = "ratio",
      source = "Karimi et al. (2019) Remote Sens. 11, 705; as applied in Chukalla et al. (2022) HESS 26, 2759-2778 (Sect. 2.3.2)",
      note = "above ETc is a package class, not published; check Kc and data, not a performance class"
    ),
    equity = list(
      breaks = c(0.10, 0.25), labels = c("good", "fair", "poor"),
      method = "fixed", right = TRUE, direction = "lower_better", units = "CV fraction",
      source = "Bastiaanssen et al. (1996); Karimi et al. (2019); quoted in Chukalla et al. (2022)", note = NULL
    ),
    uniformity_surface = list(
      breaks = 0.65, labels = c("below standard", "meets standard"),
      method = "fixed", right = TRUE, direction = "higher_better", units = "ratio",
      source = "Pitts et al. (1996), quoted in Chukalla et al. (2022); standard written for applied water", note = "1 - CV of ET is a proxy and can overstate applied-water uniformity"
    ),
    uniformity_sprinkler = list(
      breaks = 0.75, labels = c("below standard", "meets standard"),
      method = "fixed", right = TRUE, direction = "higher_better", units = "ratio",
      source = "Pitts et al. (1996), quoted in Chukalla et al. (2022); standard written for applied water", note = "1 - CV of ET is a proxy and can overstate applied-water uniformity"
    ),
    uniformity_pivot = list(
      breaks = 0.75, labels = c("below standard", "meets standard"),
      method = "fixed", right = TRUE, direction = "higher_better", units = "ratio",
      source = "Pitts et al. (1996), quoted in Chukalla et al. (2022); standard written for applied water", note = "1 - CV of ET is a proxy and can overstate applied-water uniformity"
    ),
    uniformity_drip = list(
      breaks = 0.85, labels = c("below standard", "meets standard"),
      method = "fixed", right = TRUE, direction = "higher_better", units = "ratio",
      source = "Pitts et al. (1996), quoted in Chukalla et al. (2022); standard written for applied water", note = "1 - CV of ET is a proxy and can overstate applied-water uniformity"
    ),
    spots = list(
      breaks = c(0.05, 0.95), labels = c("dark", "normal", "bright"),
      method = "quantile", right = TRUE, direction = "higher_better", units = NULL,
      source = "Chukalla et al. (2020) WaPOR productivity protocol (Zenodo 10.5281/zenodo.4641360; WAPORWP Module 5)", note = "dark is a package convention, symmetric to bright"
    )
  )
  if (is.null(scheme)) return(schemes)
  if (!is.character(scheme) || length(scheme) != 1L || !scheme %in% names(schemes)) {
    stop(sprintf("Unknown scheme '%s'. Available schemes: %s", scheme, paste(names(schemes), collapse = ", ")), call. = FALSE)
  }
  schemes[[scheme]]
}

.wapor_class_validate <- function(breaks, labels, method) {
  if (!is.numeric(breaks) || length(breaks) < 1L || any(!is.finite(breaks))) stop("breaks must be finite numeric values", call. = FALSE)
  if (method == "quantile" && any(breaks <= 0 | breaks >= 1)) stop("quantile breaks must be probabilities strictly between 0 and 1", call. = FALSE)
  if (any(diff(breaks) <= 0)) stop("breaks must be strictly increasing with no duplicates", call. = FALSE)
  if (!is.null(labels) && length(labels) != length(breaks) + 1L) stop("labels must have length length(breaks) + 1", call. = FALSE)
}

.wapor_class_groups <- function(x, reference, id) {
  n <- if (inherits(x, "SpatRaster")) terra::ncell(x) else length(x)
  if (is.null(reference)) return(rep("all", n))
  if (inherits(reference, "SpatRaster")) {
    if (!inherits(x, "SpatRaster")) stop("a raster reference requires a SpatRaster x", call. = FALSE)
    if (!terra::compareGeom(x, reference, stopOnError = FALSE, crs = TRUE, ext = TRUE, rowcol = TRUE, res = TRUE)) reference <- terra::resample(reference, x, method = "near")
    return(as.character(terra::values(reference)[, 1]))
  }
  if (inherits(reference, "sf") || inherits(reference, "SpatVector") || is.data.frame(reference) || (is.character(reference) && length(reference) == 1L && file.exists(reference))) {
    if (is.null(id) || length(id) != 1L) stop("id is required when reference is polygon data", call. = FALSE)
    if (!inherits(x, "SpatRaster")) stop("polygon references require a SpatRaster x", call. = FALSE)
    v <- if (inherits(reference, "SpatVector")) reference else terra::vect(reference)
    if (!id %in% names(v)) stop(sprintf("id column '%s' is not present in reference polygons", id), call. = FALSE)
    return(as.character(terra::values(terra::rasterize(v, x, field = id))[, 1]))
  }
  if (length(reference) != length(x)) stop("reference must have the same length as x", call. = FALSE)
  as.character(reference)
}

.wapor_class_metadata <- function(r, meta) {
  attr(r, "wapor_classes") <- meta
  if (inherits(r, "SpatRaster")) {
    terra::metags(r) <- c(wapor_classes = jsonlite::toJSON(meta, auto_unbox = TRUE, dataframe = "rows", null = "null"))
  }
  r
}

#' Classify numeric values or a raster using fixed or quantile thresholds
#'
#' Fixed intervals use `(-Inf, b1]`, `(b1, b2]`, ..., `(bn, Inf)` when
#' `right = TRUE`; with `right = FALSE`, boundary values move to the upper
#' interval. Quantile thresholds use type-7 quantiles within reference groups.
#' Groups below `min_n` (default 30) are returned as `NA` and reported in one
#' warning. Defaults are literature schemes; `direction` records whether higher
#' or lower values are better and does not reverse the interval order.
#'
#' @details
#' Scheme defaults from [wapor_class_defaults()] (every scheme has a `source`):
#'
#' | scheme | method | breaks | labels | direction | source |
#' |---|---|---|---|---|---|
#' | adequacy | fixed | 0.68, 0.80, 1.00 | poor, acceptable, good, above ETc | higher_better | Karimi et al. (2019); Chukalla et al. (2022) |
#' | equity | fixed | 0.10, 0.25 | good, fair, poor | lower_better | Bastiaanssen et al. (1996); Karimi et al. (2019) |
#' | uniformity_surface | fixed | 0.65 | below standard, meets standard | higher_better | Pitts et al. (1996) |
#' | uniformity_sprinkler | fixed | 0.75 | below standard, meets standard | higher_better | Pitts et al. (1996) |
#' | uniformity_pivot | fixed | 0.75 | below standard, meets standard | higher_better | Pitts et al. (1996) |
#' | uniformity_drip | fixed | 0.85 | below standard, meets standard | higher_better | Pitts et al. (1996) |
#' | spots | quantile | 0.05, 0.95 | dark, normal, bright | higher_better | Chukalla et al. (2020) WAPORWP Module 5 |
#'
#' Class 4 of adequacy is labelled "above ETc". It is a package class, not a
#' published over-irrigation class. Uniformity schemes are per irrigation method,
#' not one ordinal scale. Project overrides: `options(Rwapor.class_breaks)`.
#'
#' @param x Numeric vector or a terra SpatRaster.
#' @param breaks Break values, or probabilities for `method = "quantile"`.
#' @param labels Class labels, one more than `breaks`.
#' @param method Classification method, `"fixed"` or `"quantile"`.
#' @param reference Optional grouping vector, SpatRaster, or polygon data.
#' @param id Polygon attribute used for reference groups.
#' @param scheme Optional default scheme.
#' @param right Logical interval closure.
#' @param min_n Minimum observations per quantile group.
#' @return An integer categorical SpatRaster or factor.
#' @export
#' @examples
#' wapor_classify(c(0.68, 0.8, 1, 1.01), scheme = "adequacy")
wapor_classify <- function(x, breaks = NULL, labels = NULL,
                           method = c("fixed", "quantile"), reference = NULL,
                           id = NULL, scheme = NULL, right = TRUE, min_n = 30) {
  is_raster <- inherits(x, "SpatRaster")
  if (!is_raster && !is.numeric(x)) stop("x must be numeric or a terra SpatRaster", call. = FALSE)
  # NA and NaN are missing values (NoData cells arrive as NaN) and get class NA; only +-Inf is refused.
  if (!is_raster && any(is.infinite(x))) stop("x must contain only finite numeric values or NA", call. = FALSE)
  if (is_raster && terra::nlyr(x) != 1L) stop("x must have exactly one raster layer", call. = FALSE)
  if (!is.logical(right) || length(right) != 1L || is.na(right)) stop("right must be TRUE or FALSE", call. = FALSE)
  if (!is.numeric(min_n) || length(min_n) != 1L || !is.finite(min_n) || min_n < 1) stop("min_n must be a positive number", call. = FALSE)
  defaults <- if (!is.null(scheme)) wapor_class_defaults(scheme) else list()
  method <- if (missing(method) && !is.null(defaults$method)) defaults$method else match.arg(method)
  overrides <- getOption("Rwapor.class_breaks", list())
  if (!is.list(overrides)) stop("option Rwapor.class_breaks must be a named list", call. = FALSE)
  if (!is.null(scheme) && !is.null(overrides[[scheme]])) defaults[names(overrides[[scheme]])] <- overrides[[scheme]]
  if (is.null(breaks)) breaks <- defaults$breaks
  if (is.null(labels)) labels <- defaults$labels
  if (is.null(scheme) && is.null(breaks)) stop("breaks is required when scheme is NULL", call. = FALSE)
  if (is.null(labels)) labels <- as.character(seq_len(length(breaks) + 1L))
  if (!is.null(defaults$method) && missing(method) && is.null(method)) method <- defaults$method
  if (!is.null(scheme) && identical(method, "fixed") && identical(defaults$method, "quantile") && missing(method)) method <- defaults$method
  .wapor_class_validate(breaks, labels, method)
  vals <- if (is_raster) terra::values(x)[, 1] else as.numeric(x)
  groups <- .wapor_class_groups(x, reference, id)
  thresholds <- data.frame(group = character(), stringsAsFactors = FALSE)
  direction <- if (is.null(defaults$direction)) "none" else defaults$direction
  source <- if (is.null(defaults$source)) NULL else defaults$source
  if (method == "fixed") {
    thresholds <- data.frame(group = "all", matrix(breaks, nrow = 1L, dimnames = list(NULL, paste0("t", seq_along(breaks)))), check.names = FALSE)
    class_codes <- as.integer(cut(vals, c(-Inf, breaks, Inf), right = right, labels = FALSE, include.lowest = TRUE))
  } else {
    thresholds <- data.frame(group = sort(unique(groups[!is.na(groups)])), stringsAsFactors = FALSE)
    thresholds[paste0("t", seq_along(breaks))] <- NA_real_
    class_codes <- rep(NA_integer_, length(vals))
    small <- character()
    for (g in thresholds$group) {
      ix <- which(groups == g & !is.na(vals))
      if (length(ix) < min_n) { small <- c(small, g); next }
      th <- as.numeric(stats::quantile(vals[ix], probs = breaks, type = 7, names = FALSE))
      thresholds[thresholds$group == g, paste0("t", seq_along(breaks))] <- th
      class_codes[ix] <- as.integer(cut(vals[ix], c(-Inf, th, Inf), right = right, labels = FALSE, include.lowest = TRUE))
    }
    if (length(small)) warning(sprintf("reference groups below min_n (%s) have NA thresholds and classes", paste(small, collapse = ", ")), call. = FALSE)
  }
  class_codes[is.na(vals) | is.na(groups)] <- NA_integer_
  meta <- list(scheme = scheme, method = method, breaks = breaks, labels = labels, right = right,
               direction = direction, thresholds = thresholds, source = source)
  if (is_raster) {
    out <- terra::setValues(x, as.integer(class_codes))
    levels(out) <- data.frame(value = seq_along(labels), class = labels)
    return(.wapor_class_metadata(out, meta))
  }
  out <- factor(class_codes, levels = seq_along(labels), labels = labels)
  attr(out, "wapor_classes") <- meta
  out
}

#' Retrieve classification metadata
#'
#' @param x A classified factor or SpatRaster.
#' @return The `wapor_classes` metadata list, or `NULL`.
#' @export
#' @examples
#' wapor_class_info(wapor_classify(1:3, breaks = 2:3))
wapor_class_info <- function(x) {
  info <- attr(x, "wapor_classes")
  if (!is.null(info)) return(info)
  if (inherits(x, "SpatRaster")) {
    tags <- terra::metags(x)
    if (nrow(tags) && "wapor_classes" %in% tags$name) return(jsonlite::fromJSON(tags$value[tags$name == "wapor_classes"], simplifyVector = TRUE))
  }
  NULL
}
