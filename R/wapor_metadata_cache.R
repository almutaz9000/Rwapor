#' Fetch WaPOR Metadata from JSON Cache Files
#'
#' Reads pre-built metadata JSON files bundled with the package and returns
#' a data.frame describing WaPOR Level 1, 2, or 3 datasets.
#'
#' @param level Character. One of `"L1"`, `"L2"`, `"L3"`, or `"all"`.
#'   When `"all"` is supplied, all three levels are read and row-bound.
#'
#' @return A data.frame with columns:
#'   \describe{
#'     \item{code}{Character. Dataset code (e.g., `"L1-AETI-D"`).}
#'     \item{long_name}{Character. Descriptive name.}
#'     \item{units}{Character. Physical units.}
#'     \item{scale}{Numeric. Scale factor.}
#'     \item{temporal_resolution}{Character. Temporal resolution code.}
#'     \item{spatial_extent}{List column. Named list with `xmin`, `xmax`,
#'       `ymin`, `ymax`, or `NULL` when not available.}
#'     \item{level}{Character. Level identifier (`"L1"`, `"L2"`, or `"L3"`).}
#'   }
#'
#' @details
#' JSON files are resolved at runtime from a writable user cache first and
#' fall back to the installed package metadata bundled under `inst/metadata/`.
#' Call [wapor_update_metadata()] to refresh the user cache from the live API.
#'
#' @export
#'
#' @importFrom jsonlite fromJSON
#'
#' @examples
#' \dontrun{
#' # Fetch all L1 datasets
#' meta <- wapor_fetch_metadata("L1")
#' head(meta)
#'
#' # Fetch everything at once
#' all_meta <- wapor_fetch_metadata("all")
#' }
wapor_fetch_metadata <- function(level) {
  valid_levels <- c("L1", "L2", "L3", "all")
  if (!is.character(level) || length(level) != 1 || !level %in% valid_levels) {
    stop(
      sprintf("'level' must be one of: %s", paste(valid_levels, collapse = ", ")),
      call. = FALSE
    )
  }

  levels_to_read <- if (level == "all") c("L1", "L2", "L3") else level

  results <- lapply(levels_to_read, function(lvl) {
    fname  <- sprintf("wapor_%s.json", lvl)
    fpath  <- .get_metadata_path(fname)
    if (nchar(fpath) == 0 || !file.exists(fpath)) {
      stop(
        sprintf(
          "Metadata file '%s' not found. The package may not be properly installed, or you need to run wapor_update_metadata() to generate it.",
          fname
        ),
        call. = FALSE
      )
    }
    raw <- jsonlite::fromJSON(fpath, simplifyDataFrame = FALSE)
    .parse_metadata_items(raw, lvl)
  })

  do.call(rbind, results)
}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

#' Get the path to a metadata JSON file
#'
#' Wrapper around system.file() for testability.
#' @param filename Character. Name of the JSON file (e.g., "wapor_L1.json").
#' @return Character path to the file, or "" if not found.
#' @keywords internal
#' @noRd
.wapor_metadata_cache_dir <- function() {
  dir.path <- file.path(tools::R_user_dir("Rwapor", which = "cache"), "metadata")
  if (!dir.exists(dir.path)) dir.create(dir.path, recursive = TRUE, showWarnings = FALSE)
  dir.path
}

#' Get the path to a metadata JSON file
#'
#' Wrapper around system.file() for testability.
#' @param filename Character. Name of the JSON file (e.g., "wapor_L1.json").
#' @return Character path to the file, or "" if not found.
#' @keywords internal
#' @noRd
.get_metadata_path <- function(filename) {
  user_path <- file.path(.wapor_metadata_cache_dir(), filename)
  if (file.exists(user_path)) return(user_path)
  system.file("metadata", filename, package = "Rwapor")
}

#' Parse a list of raw API/JSON items into a tidy data.frame
#'
#' @param items List of metadata records (each is a named list).
#' @param level Character. Level label to attach ("L1", "L2", "L3").
#' @return data.frame
#' @keywords internal
#' @noRd
.parse_metadata_items <- function(items, level) {
  if (length(items) == 0) {
    return(
      data.frame(
        code                = character(0),
        long_name           = character(0),
        units               = character(0),
        scale               = numeric(0),
        temporal_resolution = character(0),
        spatial_extent      = I(list()),
        level               = character(0),
        stringsAsFactors    = FALSE
      )
    )
  }

  rows <- lapply(items, function(x) {
    list(
      code                = .null_chr(x$code),
      long_name           = .null_chr(x$long_name),
      units               = .null_chr(x$units),
      scale               = if (!is.null(x$scale)) as.numeric(x$scale) else NA_real_,
      temporal_resolution = .null_chr(x$temporal_resolution),
      spatial_extent      = list(if (length(x$spatial_extent) == 0) NULL else x$spatial_extent),
      level               = level
    )
  })

  df <- data.frame(
    code                = vapply(rows, `[[`, character(1), "code"),
    long_name           = vapply(rows, `[[`, character(1), "long_name"),
    units               = vapply(rows, `[[`, character(1), "units"),
    scale               = vapply(rows, `[[`, numeric(1),   "scale"),
    temporal_resolution = vapply(rows, `[[`, character(1), "temporal_resolution"),
    spatial_extent      = I(lapply(rows, function(r) r$spatial_extent[[1]])),
    level               = vapply(rows, `[[`, character(1), "level"),
    stringsAsFactors    = FALSE
  )

  df
}

#' Coerce a potentially-NULL value to character(1)
#' @keywords internal
#' @noRd
.null_chr <- function(x) {
  if (is.null(x) || length(x) == 0) NA_character_ else as.character(x[[1]])
}


# ---------------------------------------------------------------------------
# wapor_update_metadata
# ---------------------------------------------------------------------------

#' Update WaPOR Metadata Cache from the Live API
#'
#' Re-fetches dataset metadata from the FAO GISMGR API and writes JSON cache
#' files to `dest`. This is intended to be run periodically to keep the local
#' cache up to date when FAO adds new datasets.
#'
#' @param level Character. One of `"L1"`, `"L2"`, `"L3"`, or `"all"`.
#'   Defaults to `"all"`.
#' @param dest Character. Directory to write JSON files to. Defaults to the
#'   package's own `inst/metadata/` folder (useful during development). In
#'   production, users can point this to any writable directory.
#'
#' @return Invisibly, a named character vector of file paths that were written
#'   (or would have been written). On network error the function warns and
#'   returns `NULL` invisibly without overwriting existing files.
#'
#' @details
#' **API endpoints used:**
#' \itemize{
#'   \item L1/L2: `https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets`
#'   \item L3:    `https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets`
#' }
#' Pagination is handled automatically via the `links[rel="next"]` field in
#' each response.
#'
#' @keywords internal
#'
#' @importFrom httr2 request req_perform resp_body_json req_timeout req_retry
#' @importFrom jsonlite toJSON
#'
#' @examples
#' \dontrun{
#' # Update all levels in the default writable user cache
#' wapor_update_metadata()
#'
#' # Update only L1 and write to a custom directory
#' wapor_update_metadata("L1", dest = tempdir())
#' }
wapor_update_metadata <- function(level = "all", dest = NULL) {
  valid_levels <- c("L1", "L2", "L3", "all")
  if (!is.character(level) || length(level) != 1 || !level %in% valid_levels) {
    stop(
      sprintf("'level' must be one of: %s", paste(valid_levels, collapse = ", ")),
      call. = FALSE
    )
  }

  if (is.null(dest)) {
    dest <- .wapor_metadata_cache_dir()
  }

  if (!dir.exists(dest)) {
    dir.create(dest, recursive = TRUE)
  }

  levels_to_fetch <- if (level == "all") c("L1", "L2", "L3") else level

  url_map <- list(
    L1 = "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets",
    L2 = "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets",
    L3 = "https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets"
  )

  written_paths <- character(0)

  for (lvl in levels_to_fetch) {
    message(sprintf("Fetching metadata for %s ...", lvl))

    items <- tryCatch(
      .fetch_all_pages(url_map[[lvl]], level_filter = lvl),
      error = function(e) {
        warning(
          sprintf("Network error while fetching %s metadata: %s", lvl, e$message),
          call. = FALSE
        )
        NULL
      }
    )

    if (is.null(items)) {
      message(sprintf("  Skipped %s (network error -- existing cache not overwritten).", lvl))
      next
    }

    out_path <- file.path(dest, sprintf("wapor_%s.json", lvl))
    jsonlite::write_json(items, out_path, pretty = TRUE, auto_unbox = TRUE)
    message(sprintf("  Written: %s (%d items)", out_path, length(items)))
    written_paths <- c(written_paths, stats::setNames(out_path, lvl))
  }

  invisible(written_paths)
}


# ---------------------------------------------------------------------------
# Internal pagination helper
# ---------------------------------------------------------------------------

#' Fetch all pages from a GISMGR catalogue endpoint and extract metadata
#'
#' @param base_url Character. API endpoint.
#' @param level_filter Character. Level to keep (e.g., "L1").  Items whose
#'   code does not start with this prefix are discarded.
#' @return A list of standardised metadata records.
#' @keywords internal
#' @noRd
.fetch_all_pages <- function(base_url, level_filter) {
  all_items <- list()
  next_url  <- base_url

  while (!is.null(next_url)) {
    resp <- httr2::request(next_url) |>
      httr2::req_timeout(60) |>
      .wapor_req_retry() |>
      httr2::req_perform() |>
      httr2::resp_body_json()

    data <- resp$response

    if (is.null(data)) break

    items <- data$items
    if (!is.null(items) && length(items) > 0) {
      for (item in items) {
        code <- item$code
        if (is.null(code)) next
        # For L1/L2 the same endpoint is used; filter by code prefix
        if (!is.null(level_filter) && !startsWith(code, level_filter)) next

        record <- .extract_item_metadata(item, level_filter)
        all_items <- c(all_items, list(record))
      }
    }

    # Pagination: look for rel="next"
    next_url <- NULL
    links    <- data$links
    if (!is.null(links)) {
      for (lnk in links) {
        if (identical(lnk$rel, "next")) {
          next_url <- lnk$href
          break
        }
      }
    }
  }

  all_items
}


#' Extract a single item's metadata into a standardised list
#'
#' @param item List. One element from `response$items`.
#' @param level Character. Level label.
#' @return Named list with keys matching the JSON schema.
#' @keywords internal
#' @noRd
.extract_item_metadata <- function(item, level) {
  # Spatial extent -- may be missing, NULL, or a named list / bbox array
  se_raw <- item$spatialExtent
  spatial_extent <- if (is.null(se_raw)) {
    NULL
  } else if (is.list(se_raw) && !is.null(se_raw$xmin)) {
    list(
      xmin = se_raw$xmin, xmax = se_raw$xmax,
      ymin = se_raw$ymin, ymax = se_raw$ymax
    )
  } else if (is.numeric(se_raw) && length(se_raw) >= 4) {
    # bbox array: [xmin, ymin, xmax, ymax]
    list(xmin = se_raw[1], ymin = se_raw[2], xmax = se_raw[3], ymax = se_raw[4])
  } else {
    NULL
  }

  # Temporal resolution -- may live at top level or inside info
  temp_res <- item$temporalResolution %||%
    item$info$temporalResolution %||%
    NA_character_

  # Unit
  unit <- item$info$properties$unit %||%
    item$measureUnit %||%
    NA_character_

  # Scale
  scale_val <- item$info$properties$scale %||%
    item$scale %||%
    NA_real_

  # Long name / caption
  long_name <- item$caption %||%
    item$measureCaption %||%
    NA_character_

  list(
    code                = item$code,
    long_name           = long_name,
    units               = unit,
    scale               = if (!is.null(scale_val)) as.numeric(scale_val) else NA_real_,
    temporal_resolution = temp_res,
    spatial_extent      = spatial_extent,
    level               = level
  )
}


# ---------------------------------------------------------------------------
# NULL-coalescing operator (scoped to this file)
# ---------------------------------------------------------------------------

`%||%` <- function(lhs, rhs) if (!is.null(lhs) && length(lhs) > 0) lhs else rhs
