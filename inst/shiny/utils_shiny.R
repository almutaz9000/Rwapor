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

# ── Variable grouping for selectInput optgroups ────────────────────────────────
# Groups all WaPOR/AgERA5 variable codes into product families so the UI
# selector is navigable for water productivity users.  Returns a named list
# of named lists, suitable for shiny::selectInput(choices = ...).
#
# Usage in UI:
#   shiny::selectInput("var", "Variable", choices = wapor_grouped_var_choices(all_vars))
wapor_grouped_var_choices <- function(all_vars) {
  groups <- list(
    "ETa - Actual Evapotranspiration"     = grep("AETI", all_vars, value = TRUE),
    "ETp - Reference Evapotranspiration"  = grep("-RET-", all_vars, value = TRUE),
    "Transpiration"                       = grep("-T-[DMA]$", all_vars, value = TRUE),
    "Soil Evaporation"                    = grep("-E-[DMA]$", all_vars, value = TRUE),
    "Interception"                        = grep("-I-[DMA]$", all_vars, value = TRUE),
    "Net Primary Productivity"            = grep("NPP", all_vars, value = TRUE),
    "Precipitation"                       = grep("PCP|PREC", all_vars, value = TRUE),
    "Biomass / Water Productivity"        = grep("GBWP|NBWP", all_vars, value = TRUE),
    "AgERA5 ETo"                          = grep("AGERA5.*ET0", all_vars, value = TRUE),
    "AgERA5 Temperature"                  = grep("TMIN|TMAX|TDEW", all_vars, value = TRUE),
    "AgERA5 Other"                        = grep("^AGERA5-", all_vars, value = TRUE)
  )
  # Remove empty groups and track which vars are assigned to avoid duplicates
  assigned <- character(0)
  result <- list()
  for (grp_name in names(groups)) {
    grp_vars <- setdiff(groups[[grp_name]], assigned)
    if (length(grp_vars) > 0) {
      result[[grp_name]] <- stats::setNames(grp_vars, grp_vars)
      assigned <- c(assigned, grp_vars)
    }
  }
  # Catch-all for any uncategorized variables
  remaining <- setdiff(all_vars, assigned)
  if (length(remaining) > 0) {
    result[["Other"]] <- stats::setNames(remaining, remaining)
  }
  result
}

# ── Analysis configuration save / load ────────────────────────────────────────
# Save the current analysis configuration to a JSON file.
# config must be a list compatible with wapor_validate_analysis_config().
wapor_save_analysis_config <- function(config, path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("jsonlite is required to save analysis configuration.", call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  config$saved_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  config$rwapor_version <- tryCatch(
    as.character(utils::packageVersion("Rwapor")),
    error = function(e) "unknown"
  )
  jsonlite::write_json(config, path, pretty = TRUE, auto_unbox = TRUE)
  invisible(path)
}

# Load an analysis configuration from a JSON file.
# Returns a validated list or stops with a clear message.
wapor_load_analysis_config <- function(path) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("jsonlite is required to load analysis configuration.", call. = FALSE)
  }
  if (!file.exists(path)) {
    stop(sprintf("Configuration file not found: %s", path), call. = FALSE)
  }
  cfg <- tryCatch(
    jsonlite::read_json(path, simplifyVector = TRUE),
    error = function(e) stop(sprintf("Failed to read configuration file: %s", e$message), call. = FALSE)
  )
  # Validate using the package validator if available
  tryCatch(
    Rwapor::wapor_validate_analysis_config(cfg),
    error = function(e) warning(
      sprintf("Loaded config has validation warnings: %s", e$message), call. = FALSE
    )
  )
  cfg
}
