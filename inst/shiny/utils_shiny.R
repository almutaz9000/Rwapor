# utils_shiny.R
# Shared utility functions and constants for the Rwapor Shiny Dashboard

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

log_msg <- function(...) {
  msg <- paste0("[", Sys.time(), "] ", paste(..., collapse = ""))
  cat(msg, "\n")
}

null_default <- function(x, default) if (!is.null(x)) x else default

is_l3_code <- function(x) {
  is.character(x) && length(x) == 1 && nchar(x) == 3 && grepl("^[A-Z]{3}$", x)
}

crop_to_region_shiny <- function(r, reg_info, do_mask = FALSE) {
  Rwapor::wapor_crop_to_region(r, reg_info, do_mask = do_mask)
}

# --- AOI Helper Functions ---

extract_bbox_from_feature <- function(feature) {
  if (is.null(feature) || is.null(feature$geometry) || is.null(feature$geometry$coordinates)) {
    return(NULL)
  }
  gtype <- feature$geometry$type
  coords <- switch(
    gtype,
    "Polygon" = feature$geometry$coordinates[[1]],
    "MultiPolygon" = feature$geometry$coordinates[[1]][[1]],
    NULL
  )
  if (is.null(coords) || length(coords) == 0) {
    return(NULL)
  }
  mat <- do.call(rbind, lapply(coords, unlist))
  if (is.null(dim(mat)) || ncol(mat) < 2) {
    return(NULL)
  }
  c(min(mat[, 1]), min(mat[, 2]), max(mat[, 1]), max(mat[, 2]))
}

build_polygon_file <- function(coords_mat) {
  if (nrow(coords_mat) < 3) return(NULL)
  if (!all(coords_mat[1, ] == coords_mat[nrow(coords_mat), ])) {
    coords_mat <- rbind(coords_mat, coords_mat[1, ])
  }
  poly <- sf::st_polygon(list(coords_mat))
  shp <- sf::st_sf(id = 1L, geometry = sf::st_sfc(poly, crs = 4326))
  temp_path <- tempfile(fileext = ".geojson")
  sf::st_write(shp, temp_path, quiet = TRUE, delete_dsn = TRUE)
  temp_path
}

# --- Draw Tool Capability Helpers ---

draw_pkg <- if (requireNamespace("leaflet.extras", quietly = TRUE)) {
  "leaflet.extras"
} else if (requireNamespace("leaflet.extras2", quietly = TRUE)) {
  "leaflet.extras2"
} else {
  NULL
}

resolve_draw_fun <- function(pkg, candidates) {
  if (is.null(pkg)) return(NULL)
  for (nm in candidates) {
    if (exists(nm, where = asNamespace(pkg), inherits = FALSE)) {
      return(get(nm, envir = asNamespace(pkg), inherits = FALSE))
    }
  }
  NULL
}

add_draw_toolbar <- resolve_draw_fun(draw_pkg, c("addDrawToolbar", "add_draw_toolbar"))
edit_toolbar_options <- resolve_draw_fun(draw_pkg, c("editToolbarOptions", "edit_toolbar_options"))
selected_path_options <- resolve_draw_fun(draw_pkg, c("selectedPathOptions", "selected_path_options"))
has_draw_tools <- !is.null(add_draw_toolbar) &&
  !is.null(edit_toolbar_options) &&
  !is.null(selected_path_options)

# --- shinyFiles Helpers ---

# Returns a named vector of available file system roots for shinyFiles widgets.
# Computed once at module init; volumes/cwd don't change during a session.
# Includes user-friendly shortcuts (Desktop, Downloads, Documents) so Windows
# users don't have to navigate all the way from a drive root.
get_shinyfiles_roots <- function() {
  tryCatch({
    vols <- shinyFiles::getVolumes()()
    if (length(vols) > 0) {
      names(vols) <- gsub(":\\\\", ":/", names(vols))
    }
    home <- normalizePath("~", winslash = "/", mustWork = FALSE)
    shortcuts <- Filter(
      dir.exists,
      stats::setNames(
        file.path(home, c("Desktop", "Downloads", "Documents")),
        c("Desktop", "Downloads", "Documents")
      )
    )
    c(vols, shortcuts, Project = getwd())
  }, error = function(e) {
    c(Project = getwd(), Home = normalizePath("~", winslash = "/"))
  })
}
