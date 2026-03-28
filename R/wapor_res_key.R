# wapor_res_key.R
# Resolution-aware grouping for WaPOR and AgERA5 variables.
#
# WaPOR 3 native pixel sizes (approximate at equator):
#
#   L1-AETI / E / T / I / NPP / TBP / GBWP / NBWP : ~300 m  (MODIS-derived)
#   L1-PCP                                          : ~5 000 m (CHIRPS)
#   L1-RET                                          : ~30 000 m (ERA5 0.25°)
#   L1-RSM                                          : ~500 m  (Sentinel-1)
#   L2-*                                            : ~100 m
#   L3-*                                            : ~30 m   (varies by scheme)
#   AGERA5-*                                        : ~11 000 m (ERA5 0.1°)
#
# Variables within the SAME resolution key share the same native grid and can
# be stacked for a single exactextractr pass.  Variables with DIFFERENT keys
# must be extracted independently (different grids cannot be stacked).
#
# NOTE: L1 is deliberately NOT treated as one group because its component
# variables come from different sensors at different resolutions.  The user's
# requirement is the driving constraint here.

# ── Internal lookup ───────────────────────────────────────────────────────────

# Keys are matched against the variable code in order:
#   1. Exact "LEVEL-VARNAME" prefix (e.g. "L1-PCP")  — highest priority
#   2. Level prefix (e.g. "L2", "AGERA5")             — fallback

.WAPOR_RES_LOOKUP <- c(
  # ── L1: variable-specific resolutions ────────────────────────────────────
  "L1-AETI"  = "L1_300m",
  "L1-E"     = "L1_300m",
  "L1-T"     = "L1_300m",
  "L1-I"     = "L1_300m",
  "L1-NPP"   = "L1_300m",
  "L1-TBP"   = "L1_300m",
  "L1-GBWP"  = "L1_300m",
  "L1-NBWP"  = "L1_300m",
  "L1-PCP"   = "L1_5000m",   # CHIRPS ~5 km
  "L1-RET"   = "L1_30000m",  # ERA5 ~30 km
  "L1-RSM"   = "L1_500m",    # Sentinel-1 ~500 m
  # ── L2: all on the same 100 m grid ───────────────────────────────────────
  "L2"       = "L2_100m",
  # ── L3: all 30 m (irrigation scheme specific, but same resolution) ────────
  "L3"       = "L3_30m",
  # ── AgERA5: ERA5 0.1° ~11 km ─────────────────────────────────────────────
  "AGERA5"   = "AGERA5_11000m"
)

# ── Exported helper ───────────────────────────────────────────────────────────

#' Get the native-grid resolution key for a WaPOR / AgERA5 variable
#'
#' Returns a short string that identifies the native pixel grid of a variable.
#' Variables that share the same key are on the same spatial grid and can safely
#' be stacked for a single zonal-statistics pass.  Variables with *different*
#' keys must be extracted independently.
#'
#' @param variable Character scalar. Variable code such as `"L1-AETI-D"`,
#'   `"L1-PCP-D"`, `"L2-AETI-D"`, `"L3-AETI-D"`, or `"AGERA5-ET0-E"`.
#'
#' @return A character scalar, e.g. `"L1_300m"`, `"L1_5000m"`, `"L2_100m"`,
#'   `"L3_30m"`, `"AGERA5_11000m"`.  Returns `variable` itself (unique key) if
#'   not recognised, which safely prevents it from being batched with others.
#'
#' @details
#' Within Level 1, variables originate from different sensors:
#' * AETI / E / T / I / NPP / TBP / GBWP / NBWP — MODIS (~300 m)
#' * PCP — CHIRPS (~5 000 m)
#' * RET — ERA5 (~30 000 m)
#' * RSM — Sentinel-1 (~500 m)
#'
#' Grouping L1 variables by level prefix alone would be incorrect because they
#' cannot be stacked onto the same grid without resampling.
#'
#' @export
#' @examples
#' wapor_res_key("L1-AETI-D")   # "L1_300m"
#' wapor_res_key("L1-PCP-D")    # "L1_5000m"
#' wapor_res_key("L1-RET-D")    # "L1_30000m"
#' wapor_res_key("L2-AETI-D")   # "L2_100m"
#' wapor_res_key("L3-AETI-D")   # "L3_30m"
#' wapor_res_key("AGERA5-ET0-E") # "AGERA5_11000m"
wapor_res_key <- function(variable) {
  stopifnot(is.character(variable), length(variable) == 1L)

  # 1. Try "LEVEL-VARNAME" prefix  (strip trailing temporal suffix: -D, -M, -A, -E)
  lv_prefix <- sub("-[ADME]$", "", variable)   # e.g. "L1-AETI-D" -> "L1-AETI"
  if (lv_prefix %in% names(.WAPOR_RES_LOOKUP))
    return(unname(.WAPOR_RES_LOOKUP[lv_prefix]))

  # 2. Try level-only prefix
  lev_prefix <- sub("-.*", "", variable)        # e.g. "L1-AETI-D" -> "L1"
  if (lev_prefix %in% names(.WAPOR_RES_LOOKUP))
    return(unname(.WAPOR_RES_LOOKUP[lev_prefix]))

  # 3. Unknown variable — return itself so it is never batched with others
  variable
}

#' Group a vector of variable codes by shared native grid
#'
#' Splits a character vector of variable codes into named groups where all
#' members share the same resolution key (and therefore the same native pixel
#' grid).  Only groups with more than one variable benefit from batched
#' extraction; single-variable groups are left as-is.
#'
#' @param variables Character vector of variable codes.
#' @return A named list of character vectors, one element per unique resolution
#'   key.  Names are the resolution keys.
#'
#' @export
#' @examples
#' wapor_group_by_res(c("L1-AETI-D", "L1-NPP-D", "L1-PCP-D", "L2-AETI-D"))
#' # $L1_300m   -> c("L1-AETI-D", "L1-NPP-D")
#' # $L1_5000m  -> "L1-PCP-D"
#' # $L2_100m   -> "L2-AETI-D"
wapor_group_by_res <- function(variables) {
  stopifnot(is.character(variables))
  keys <- vapply(variables, wapor_res_key, character(1L), USE.NAMES = FALSE)
  split(variables, keys)
}
