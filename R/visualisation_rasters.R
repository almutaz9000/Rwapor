# visualisation_rasters.R
# Non-reactive helpers for the Shiny Visualisation tab.

#' Detect seasonal rasters from relative paths
#'
#' Matches WaPOR seasonal download folders (`<var>_seasonal`), `.seasonal.`
#' filenames, analysis `seasonal_rasters/` outputs, and seasonal components.
#' Dekadal/monthly/annual time-step files are not treated as seasonal.
#'
#' @param path Character vector of relative raster paths.
#' @return Logical vector, same length as `path`.
#' @keywords internal
wapor_is_seasonal_raster_path <- function(path) {
  if (is.null(path) || length(path) == 0L) return(logical(0))
  rel <- gsub("\\\\", "/", as.character(path), fixed = TRUE)
  folder_seasonal <- grepl("(^|/)[^/]*_seasonal(/|$)", rel, ignore.case = TRUE)
  seasonal_dir <- grepl("(^|/)seasonal_rasters(/|$)", rel, ignore.case = TRUE)
  filename_seasonal <- grepl("\\.seasonal\\.", basename(rel), ignore.case = TRUE)
  component <- grepl("(^|/)seasonal_component_", rel, ignore.case = TRUE)
  export_suffix <- grepl("_seasonal_", basename(rel), ignore.case = TRUE)
  folder_seasonal | seasonal_dir | filename_seasonal | component | export_suffix
}

.wapor_vis_normalize_relpath <- function(path) {
  gsub("\\\\", "/", path, fixed = TRUE)
}

#' List GeoTIFF rasters under a project folder
#'
#' @param folder Character path. Missing or non-directory returns `character(0)`.
#' @param only_seasonal Logical. If `TRUE`, keep seasonal rasters only.
#' @return Character vector of relative paths using forward slashes.
#' @keywords internal
wapor_list_visualisation_rasters <- function(folder, only_seasonal = FALSE) {
  if (!is.character(folder) || length(folder) != 1L || !nzchar(folder) || !dir.exists(folder)) {
    return(character(0))
  }
  files <- list.files(
    folder,
    pattern = "\\.(tif|tiff)$",
    recursive = TRUE,
    full.names = FALSE,
    ignore.case = TRUE
  )
  files <- .wapor_vis_normalize_relpath(files)
  if (isTRUE(only_seasonal)) {
    files <- files[wapor_is_seasonal_raster_path(files)]
  }
  sort(unique(files))
}

.wapor_vis_group_relpaths <- function(files, prefix = "") {
  if (length(files) == 0L) return(list())
  files <- .wapor_vis_normalize_relpath(files)
  first <- vapply(strsplit(files, "/", fixed = TRUE), function(parts) {
    if (length(parts) <= 1L) "(project root)" else parts[[1L]]
  }, character(1))
  if (nzchar(prefix)) {
    first <- paste0(prefix, first)
    files <- paste0(prefix, files)
  }
  split(unname(files), first)
}

#' Build selectize optgroups for Visualisation raster pickers
#'
#' @param folder Project / download folder.
#' @param an_folder Optional analysis output folder. Prefixed with `[AN] `
#'   when it is a different directory.
#' @param only_seasonal Logical seasonal filter.
#' @return Named list of character vectors (optgroups), or `character(0)`.
#' @keywords internal
wapor_visualisation_raster_choices <- function(folder, an_folder = NULL, only_seasonal = FALSE) {
  tif_files <- wapor_list_visualisation_rasters(folder, only_seasonal = only_seasonal)
  groups <- .wapor_vis_group_relpaths(tif_files)

  same_dir <- FALSE
  if (!is.null(an_folder) && is.character(an_folder) && length(an_folder) == 1L &&
      nzchar(an_folder) && dir.exists(an_folder) &&
      !is.null(folder) && is.character(folder) && length(folder) == 1L && nzchar(folder) &&
      dir.exists(folder)) {
    same_dir <- identical(
      normalizePath(an_folder, mustWork = FALSE),
      normalizePath(folder, mustWork = FALSE)
    )
  }
  if (!isTRUE(same_dir)) {
    an_files <- wapor_list_visualisation_rasters(an_folder, only_seasonal = only_seasonal)
    groups <- c(groups, .wapor_vis_group_relpaths(an_files, prefix = "[AN] "))
  }

  if (length(groups) == 0L) return(character(0))
  groups
}

#' Whether the Visualisation overlay observer may mutate the Leaflet map
#'
#' Call this before `leafletProxy()` / `clearGroup()` so a missing raster
#' cannot blank the map.
#'
#' @param mode Visualisation mode (`single`, `dual`, `query`).
#' @param r1,r2 Prepared raster objects or sentinels. `NULL` means not ready.
#' @param query Query result list with `success` and `raster`, or `NULL`.
#' @return Logical.
#' @keywords internal
wapor_vis_overlay_ready <- function(mode, r1 = NULL, r2 = NULL, query = NULL) {
  if (is.null(mode) || length(mode) == 0L || !nzchar(as.character(mode)[[1L]])) {
    return(FALSE)
  }
  mode <- as.character(mode)[[1L]]
  if (identical(mode, "single")) return(!is.null(r1))
  if (identical(mode, "dual")) return(!is.null(r1) && !is.null(r2))
  if (identical(mode, "query")) {
    return(is.list(query) && isTRUE(query$success) && !is.null(query$raster))
  }
  FALSE
}

#' Leaflet groups owned by the Visualisation raster overlay
#'
#' Analysis overlays (`lyr_crop_mask`, season start/end) are excluded so a
#' raster change does not wipe them.
#'
#' @param mode Visualisation mode (unused; all overlay groups are returned so
#'   leftover layers from a previous mode are removed).
#' @return Character vector of group names.
#' @keywords internal
wapor_vis_overlay_clear_groups <- function(mode = "single") {
  c("raster", "raster1", "raster2", "raster_intersection", "raster_query")
}

#' DOM ids for the side-by-side Leaflet maps
#'
#' @param ns A Shiny namespace function, typically `session$ns`.
#' @return Named character vector with `left` and `right`.
#' @keywords internal
wapor_dual_map_dom_ids <- function(ns) {
  if (!is.function(ns)) stop("ns must be a Shiny namespace function.", call. = FALSE)
  c(left = ns("map_left"), right = ns("map_right"))
}

#' Whether dual-map pan/zoom lock can be attached
#'
#' Leaflet.extras2 `addLeafletsync` looks up widgets with `HTMLWidgets.find`.
#' That fails if the Side-by-Side tab has not created the maps yet. Wait until
#' both maps have reported a zoom (they exist in the DOM) before syncing.
#'
#' @param locked Logical. The "Lock pan & zoom" checkbox.
#' @param left_zoom,right_zoom Numeric zoom from `input$map_*_zoom`, or NULL.
#' @return Logical.
#' @keywords internal
#' Whether both dual-map instances exist in DOM
#'
#' @param left_zoom,right_zoom Numeric zoom from `input$map_*_zoom`, or NULL.
#' @return Logical.
#' @keywords internal
wapor_dual_map_ready <- function(left_zoom, right_zoom) {
  lz <- suppressWarnings(as.numeric(left_zoom)[1L])
  rz <- suppressWarnings(as.numeric(right_zoom)[1L])
  is.finite(lz) && is.finite(rz)
}

#' Whether dual-map pan/zoom lock can be attached
#'
#' Leaflet.extras2 `addLeafletsync` looks up widgets with `HTMLWidgets.find`.
#' That fails if the Side-by-Side tab has not created the maps yet. Wait until
#' both maps have reported a zoom (they exist in the DOM) before syncing.
#'
#' @param locked Logical. The "Lock pan & zoom" checkbox.
#' @param left_zoom,right_zoom Numeric zoom from `input$map_*_zoom`, or NULL.
#' @return Logical.
#' @keywords internal
wapor_dual_map_can_sync <- function(locked, left_zoom, right_zoom) {
  if (!isTRUE(locked)) return(FALSE)
  wapor_dual_map_ready(left_zoom, right_zoom)
}
