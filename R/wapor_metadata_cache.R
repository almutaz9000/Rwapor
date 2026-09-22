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
    stop(sprintf("'level' must be one of: %s", paste(valid_levels, collapse = ", ")), call. = FALSE)
  }
  result <- .load_metadata_catalog(level)
  if (!nrow(result)) {
    levels_text <- if (level == "all") "L1, L2, or L3" else level
    file_text <- if (level == "all") "wapor_L1.json, wapor_L2.json, or wapor_L3.json" else sprintf("wapor_%s.json", level)
    stop(sprintf("No valid metadata found for %s (expected %s)", levels_text, file_text), call. = FALSE)
  }
  result[, c("code", "long_name", "units", "scale", "temporal_resolution",
             "spatial_extent", "level"), drop = FALSE]
}


#' Parse a human-readable spatial resolution into metres
#'
#' @keywords internal
#' @noRd
.parse_spatial_resolution_m <- function(value) {
  if (is.null(value) || !length(value) || is.na(value[1])) return(NA_real_)
  text <- as.character(value[1])
  number <- suppressWarnings(as.numeric(sub("[^0-9.].*", "", text)))
  if (is.na(number)) return(NA_real_)
  unit <- tolower(sub("^[0-9.]+\\s*", "", text))
  if (startsWith(unit, "km")) number * 1000 else number
}

#' Normalize one API or cache metadata item
#'
#' Normalizes live GISMGR and bundled-cache records while keeping level,
#' temporal resolution, and spatial resolution as separate fields.
#' @keywords internal
#' @noRd
.normalize_metadata_item <- function(item, level = NULL, source = "api",
                                     requested_code = NULL, product_type = NULL) {
  code <- item$code %||% item$requested_code
  if (is.null(code) || length(code) != 1 || is.na(code) || !nzchar(code)) {
    stop("Metadata item has no valid code", call. = FALSE)
  }
  parts <- strsplit(as.character(code), "-", fixed = TRUE)[[1]]
  inferred_level <- parts[1]
  temporal <- tail(parts, 1)
  if (!temporal %in% c("A", "M", "D", "E")) temporal <- NA_character_

  caption <- as.character(item$caption %||% "")
  spatial <- item$spatial_resolution %||% item$spatialResolution
  if (is.null(spatial) || !length(spatial) || is.na(spatial[1])) {
    match <- regmatches(caption, regexpr("[0-9]+\\s*(km|m)", caption,
                                          ignore.case = TRUE, perl = TRUE))
    spatial <- if (length(match) && nzchar(match)) match else NA_character_
  }

  item_level <- level %||% item$level %||% inferred_level
  if (!identical(item_level, inferred_level)) {
    stop(sprintf("Metadata code '%s' conflicts with level '%s'", code, item_level),
         call. = FALSE)
  }
  list(
    code = as.character(code),
    requested_code = requested_code %||% as.character(code),
    resolved_code = as.character(code),
    long_name = as.character(item$long_name %||% item$measureCaption %||%
                               item$caption %||% code),
    units = as.character(item$units %||% item$measureUnit %||% "unknown"),
    scale = as.numeric(item$scale %||% 1),
    offset = as.numeric(item$offset %||% 0),
    temporal_resolution = temporal,
    spatial_resolution = as.character(spatial[1]),
    spatial_resolution_m = .parse_spatial_resolution_m(spatial),
    spatial_extent = item$spatial_extent %||% item$spatialExtent %||% NULL,
    level = inferred_level,
    product_type = product_type %||% item$product_type %||% item$productType %||%
      if (identical(inferred_level, "L3")) "mosaicset" else "mapset",
    source = source,
    fallback_used = FALSE
  )
}

.normalize_metadata_items <- function(items, level, source = "api",
                                    product_type = NULL) {
  if (!length(items)) return(list())
  level_items <- Filter(function(item) {
    code <- item$code %||% ""
    startsWith(as.character(code), paste0(level, "-"))
  }, items)
  normalized <- lapply(level_items, .normalize_metadata_item,
                        level = level, source = source,
                        product_type = product_type)
  keep <- vapply(normalized, function(x) {
    code_parts <- strsplit(x$code, "-", fixed = TRUE)[[1]]
    length(code_parts) == 3 && identical(code_parts[1], level) &&
      code_parts[3] %in% c("A", "M", "D", "E") &&
      !grepl("-(UTM|QUAL|CROP)-", x$code)
  }, logical(1))
  normalized <- normalized[keep]
  if (!length(normalized)) return(list())
  normalized[!duplicated(vapply(normalized, `[[`, character(1), "code"))]
}

.metadata_records_to_df <- function(records) {
  if (!length(records)) {
    return(data.frame(
      code = character(), requested_code = character(), resolved_code = character(),
      long_name = character(), units = character(), scale = numeric(), offset = numeric(),
      temporal_resolution = character(), spatial_resolution = character(),
      spatial_resolution_m = numeric(), spatial_extent = I(list()),
      level = character(), product_type = character(), source = character(),
      fallback_used = logical(), stringsAsFactors = FALSE
    ))
  }
  data.frame(
    code = vapply(records, `[[`, character(1), "code"),
    requested_code = vapply(records, `[[`, character(1), "requested_code"),
    resolved_code = vapply(records, `[[`, character(1), "resolved_code"),
    long_name = vapply(records, `[[`, character(1), "long_name"),
    units = vapply(records, `[[`, character(1), "units"),
    scale = vapply(records, `[[`, numeric(1), "scale"),
    offset = vapply(records, `[[`, numeric(1), "offset"),
    temporal_resolution = vapply(records, `[[`, character(1), "temporal_resolution"),
    spatial_resolution = vapply(records, `[[`, character(1), "spatial_resolution"),
    spatial_resolution_m = vapply(records, `[[`, numeric(1), "spatial_resolution_m"),
    spatial_extent = I(lapply(records, `[[`, "spatial_extent")),
    level = vapply(records, `[[`, character(1), "level"),
    product_type = vapply(records, `[[`, character(1), "product_type"),
    source = vapply(records, `[[`, character(1), "source"),
    fallback_used = vapply(records, `[[`, logical(1), "fallback_used"),
    stringsAsFactors = FALSE
  )
}

.load_metadata_catalog_uncached <- function(level = "all") {
  levels_to_read <- if (level == "all") c("L1", "L2", "L3") else level
  records <- unlist(lapply(levels_to_read, function(lvl) {
    path <- .get_metadata_path(sprintf("wapor_%s.json", lvl))
    if (!nzchar(path) || !file.exists(path)) return(list())
    raw <- jsonlite::fromJSON(path, simplifyDataFrame = FALSE)
    .normalize_metadata_items(raw, lvl, source = "cache")
  }), recursive = FALSE)
  .metadata_records_to_df(records)
}

# Metadata files are immutable inputs during a session, so cache parsed
# catalogues and invalidate both catalogues and variable lookups on refresh.
.metadata_catalog_signature <- function() {
  paste(vapply(c("L1", "L2", "L3"), function(lvl) {
    path <- .get_metadata_path(sprintf("wapor_%s.json", lvl))
    if (!nzchar(path) || !file.exists(path)) return("missing")
    info <- file.info(path)
    paste(normalizePath(path, winslash = "/", mustWork = FALSE), info$mtime, info$size)
  }, character(1)), collapse = "|")
}
.load_metadata_catalog_cached <- memoise::memoise(function(level = "all", signature = .metadata_catalog_signature()) {
  .load_metadata_catalog_uncached(level)
})
.load_metadata_catalog <- function(level = "all") {
  .load_metadata_catalog_cached(level, .metadata_catalog_signature())
}
# ---------------------------------------------------------------------------

#' Get the path to a metadata JSON file
#'
#' Wrapper around system.file() for testability.
#' @param filename Character. Name of the JSON file (e.g., "wapor_L1.json").
#' @return Character path to the file, or "" if not found.
#' @keywords internal
#' @noRd
.wapor_metadata_cache_dir <- function(create = FALSE) {
  dir.path <- file.path(tools::R_user_dir("Rwapor", which = "cache"), "metadata")
  if (isTRUE(create) && !dir.exists(dir.path)) {
    dir.create(dir.path, recursive = TRUE, showWarnings = FALSE)
  }
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
#'   writable user cache. Set this explicitly to `inst/metadata/` only when
#'   refreshing package-bundled snapshots during development.
#'
#' @return Invisibly, a named character vector of file paths that were written
#'   (or would have been written). On network error the function warns and
#'   returns `NULL` invisibly without overwriting existing files.
#'
#' @export
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
    dest <- .wapor_metadata_cache_dir(create = TRUE)
  }

  if (!dir.exists(dest)) {
    dir.create(dest, recursive = TRUE)
  }

  levels_to_fetch <- if (level == "all") c("L1", "L2", "L3") else level

  url_map <- list(
    L1 = .wapor_level_workspace_url("L1"),
    L2 = .wapor_level_workspace_url("L2"),
    L3 = .wapor_level_workspace_url("L3")
  )

  pending <- list()
  failures <- character(0)

  for (lvl in levels_to_fetch) {
    message(sprintf("Fetching metadata for %s ...", lvl))
    items <- tryCatch(
      .fetch_all_pages(url_map[[lvl]], level_filter = lvl),
      error = function(e) {
        failures <<- c(failures, lvl)
        warning(sprintf("Network error while fetching %s metadata: %s", lvl, e$message),
                call. = FALSE)
        NULL
      }
    )
    if (is.null(items)) next
    if (!length(items)) {
      failures <- c(failures, lvl)
      warning(sprintf("No valid metadata records returned for %s", lvl), call. = FALSE)
      next
    }
    pending[[lvl]] <- items
  }

  if (length(failures)) {
    message("Metadata update aborted; existing cache files were not overwritten.")
    return(invisible(character(0)))
  }

  written_paths <- stats::setNames(character(length(pending)), names(pending))
  for (lvl in names(pending)) {
    out_path <- file.path(dest, sprintf("wapor_%s.json", lvl))
    tmp_path <- tempfile(pattern = paste0("wapor_", lvl, "-"),
                         tmpdir = dest, fileext = ".json.tmp")
    ok <- FALSE
    tryCatch({
      jsonlite::write_json(pending[[lvl]], tmp_path, pretty = TRUE, auto_unbox = TRUE)
      if (!file.rename(tmp_path, out_path)) {
        stop("Could not atomically replace metadata cache file", call. = FALSE)
      }
      ok <- TRUE
    }, error = function(e) {
      if (file.exists(tmp_path)) unlink(tmp_path)
      stop(sprintf("Failed to write %s metadata: %s", lvl, e$message), call. = FALSE)
    })
    if (ok) {
      written_paths[[lvl]] <- out_path
      message(sprintf("  Written: %s (%d items)", out_path, length(pending[[lvl]])))
    }
  }

  manifest_path <- file.path(dest, "wapor_metadata_manifest.json")
  manifest <- list(
    schema_version = 1L,
    retrieved_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
    workspace = "WAPOR-3",
    levels = lapply(names(pending), function(lvl) {
      list(records = length(pending[[lvl]]), endpoint = url_map[[lvl]])
    })
  )
  names(manifest$levels) <- names(pending)
  manifest_tmp <- tempfile(pattern = "wapor-metadata-manifest-",
                           tmpdir = dest, fileext = ".json.tmp")
  tryCatch({
    jsonlite::write_json(manifest, manifest_tmp, pretty = TRUE, auto_unbox = TRUE)
    if (!file.rename(manifest_tmp, manifest_path)) {
      stop("Could not atomically replace metadata manifest", call. = FALSE)
    }
  }, error = function(e) {
    if (file.exists(manifest_tmp)) unlink(manifest_tmp)
    stop(sprintf("Failed to write metadata manifest: %s", e$message), call. = FALSE)
  })
  written_paths <- c(written_paths, manifest = manifest_path)

  if (exists("wapor_variable_metadata", mode = "function") &&
      memoise::is.memoised(wapor_variable_metadata)) {
    memoise::forget(wapor_variable_metadata)
  }
  if (exists(".load_metadata_catalog_cached", mode = "function") &&
      memoise::is.memoised(.load_metadata_catalog_cached)) {
    memoise::forget(.load_metadata_catalog_cached)
  }
  invisible(written_paths)
}
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
  items <- collect_responses(base_url, info = NULL, use_cache = FALSE)
  product_type <- if (grepl("/mosaicsets", base_url, fixed = TRUE)) "mosaicset" else "mapset"
  .normalize_metadata_items(items, level_filter, source = "api", product_type = product_type)
}
