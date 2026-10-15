# =============================================================================
# Compatibility validation for provenance-aware calculations
# =============================================================================

#' Create a compact SpatRaster grid signature
#' @keywords internal
#' @noRd
.wapor_provenance_grid_signature <- function(x) {
  e <- terra::ext(x)
  list(nrow = as.integer(terra::nrow(x)), ncol = as.integer(terra::ncol(x)),
       res = as.numeric(terra::res(x)),
       extent = list(xmin = e$xmin, xmax = e$xmax, ymin = e$ymin, ymax = e$ymax),
       crs = as.character(terra::crs(x)))
}

#' Content digest for a raster, read in fixed-size row windows
#' @keywords internal
#' @noRd
.wapor_raster_content_signature <- function(x, rows_per_chunk = 64L) {
  if (!inherits(x, "SpatRaster")) stop("'x' must be a SpatRaster", call. = FALSE)
  if (length(rows_per_chunk) != 1L || is.na(rows_per_chunk) || rows_per_chunk < 1L) {
    stop("'rows_per_chunk' must be one positive integer", call. = FALSE)
  }
  rows_per_chunk <- as.integer(rows_per_chunk)
  grid <- .wapor_provenance_grid_signature(x)
  terra::readStart(x)
  on.exit(terra::readStop(x), add = TRUE)
  starts <- seq.int(1L, terra::nrow(x), by = rows_per_chunk)
  block_digests <- lapply(starts, function(row) {
    n <- min(rows_per_chunk, terra::nrow(x) - row + 1L)
    values <- terra::readValues(x, row = row, nrows = n, mat = TRUE)
    digest::digest(unname(values), algo = "sha256")
  })
  list(grid = grid, content_digest = digest::digest(block_digests, algo = "sha256"))
}

#' Find serialized provenance for an exported raster
#' @keywords internal
#' @noRd
.wapor_read_raster_sidecar_provenance <- function(x) {
  sources <- tryCatch(terra::sources(x), error = function(e) character())
  sources <- sources[!is.na(sources) & nzchar(sources)]
  if (length(sources) != 1L || !file.exists(sources[[1]])) return(NULL)
  source_path <- normalizePath(sources[[1]], winslash = "/", mustWork = TRUE)
  directory <- dirname(source_path)
  for (depth in seq_len(8L)) {
    sidecar <- file.path(directory, "provenance.json")
    if (file.exists(sidecar)) {
      payload <- tryCatch(jsonlite::fromJSON(sidecar), error = function(e) NULL)
      if (is.null(payload) || !identical(as.integer(payload$schema_version), 1L)) return(NULL)
      root <- normalizePath(directory, winslash = "/", mustWork = TRUE)
      if (!startsWith(source_path, paste0(root, "/"))) return(NULL)
      relative <- substring(source_path, nchar(root) + 2L)
      entry <- payload$files[[relative]]
      if (is.character(entry) && length(entry) == 1L) {
        key <- entry
      } else if (is.list(entry) && is.character(entry$output) && length(entry$output) == 1L) {
        key <- entry$output
        expected_hash <- entry$sha256
        actual_hash <- digest::digest(file = source_path, algo = "sha256")
        if (!identical(expected_hash, actual_hash)) {
          warning("Provenance sidecar checksum does not match the raster; ignoring its metadata.", call. = FALSE)
          return(NULL)
        }
      } else {
        return(NULL)
      }
      record <- payload$outputs[[key]]
      if (is.null(record) || !is.list(record) || is.null(record$schema_version)) return(NULL)
      if (!is.null(record$grid) && !isTRUE(.wapor_grids_equal(.wapor_provenance_grid_signature(x), record$grid))) {
        warning("Provenance sidecar grid does not match the raster; ignoring its metadata.", call. = FALSE)
        return(NULL)
      }
      if (is.data.frame(record$intervals) && nrow(record$intervals) != terra::nlyr(x)) {
        warning("Provenance sidecar layer intervals do not match the raster; ignoring its metadata.", call. = FALSE)
        return(NULL)
      }
      class(record) <- c("wapor_provenance", "list")
      return(record)
    }
    parent <- dirname(directory)
    if (identical(parent, directory)) break
    directory <- parent
  }
  NULL
}

#' Convert a validation input to provenance
#' @keywords internal
#' @noRd
.wapor_input_provenance <- function(x) {
  if (inherits(x, "wapor_provenance")) return(x)
  sidecar <- if (inherits(x, "SpatRaster")) .wapor_read_raster_sidecar_provenance(x) else NULL
  if (inherits(sidecar, "wapor_provenance")) return(sidecar)
  if (is.list(x) && inherits(x$provenance, "wapor_provenance")) return(x$provenance)
  if (inherits(x, "SpatRaster")) {
    nm <- names(x)
    variable <- if (length(nm)) .wapor_variable_code_from_name(nm[[1]]) else NA_character_
    if (is.na(variable)) variable <- NULL
    u <- tryCatch(as.character(terra::units(x)), error = function(e) character())
    u <- unique(u[!is.na(u) & nzchar(u)])
    return(.wapor_new_provenance(variable, .wapor_raster_intervals(x, variable),
      units = if (length(u) == 1L) u[[1]] else NULL, grid = .wapor_provenance_grid_signature(x)))
  }
  stop("Each input must be a provenance record, a SpatRaster, or a result containing provenance", call. = FALSE)
}

#' Apply a compatibility contract before raster pair arithmetic
#' @keywords internal
#' @noRd
.wapor_check_raster_pair <- function(x, y, operation, provenance = NULL,
                                     mode = c("warn", "strict"),
                                     input_names = c("a", "b")) {
  mode <- match.arg(mode)
  explicit_provenance <- !is.null(provenance)
  if (!explicit_provenance && identical(operation, "harmonized_pair")) {
    return(invisible(NULL))
  }
  inputs <- provenance
  if (is.null(inputs) && inherits(x, "SpatRaster") && inherits(y, "SpatRaster")) {
    inputs <- stats::setNames(list(x, y), input_names)
  }
  if (!is.null(inputs)) {
    if (!explicit_provenance && identical(operation, "harmonized_pair")) {
      operation <- "harmonized_units"
    }
    is_series <- function(item) {
      if (inherits(item, "SpatRaster")) return(terra::nlyr(item) > 1L)
      interval_data <- if (inherits(item, "wapor_provenance")) item$intervals else NULL
      is.data.frame(interval_data) && nrow(interval_data) > 1L
    }
    if (any(vapply(inputs, is_series, logical(1)))) {
      operation <- switch(operation,
        ratio = "ratio_series",
        add = "add_series",
        harmonized_pair = "harmonized_series",
        operation
      )
    }
    .wapor_require_compatible(inputs, operation, mode)
  }
  invisible(NULL)
}

#' Normalize a unit label
#' @keywords internal
#' @noRd
.wapor_unit_label <- function(x) {
  if (is.null(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(as.character(x)))) return(NA_character_)
  tolower(gsub("\\s+", "", as.character(x)))
}

#' Resolve a conservative physical unit dimension
#' @keywords internal
#' @noRd
.wapor_unit_dimension <- function(x) {
  u <- .wapor_unit_label(x)
  if (is.na(u)) return(NA_character_)
  if (u %in% c("mm", "mm/month", "mm/year", "mm/dekad")) return("water_depth")
  if (u %in% c("mm/day", "mm/d")) return("water_depth_rate")
  if (u %in% c("kg/ha", "t/ha", "kgdm/ha", "gc/m2")) return("mass_per_area")
  if (u %in% c("kg/ha/day", "t/ha/day", "gc/m2/day")) return("mass_per_area_rate")
  if (u %in% c("kg/m3", "kg/m^3")) return("mass_per_volume")
  if (u %in% c("%", "percent", "1", "dimensionless")) return("dimensionless")
  if (u %in% c("k", "degc", "celsius")) return("temperature")
  NA_character_
}

#' Compare complete grid signatures
#' @keywords internal
#' @noRd
.wapor_grids_equal <- function(a, b) {
  required <- c("nrow", "ncol", "res", "extent", "crs")
  if (!is.list(a) || !is.list(b) || !all(required %in% names(a)) || !all(required %in% names(b))) return(NA)
  num_equal <- function(x, y) isTRUE(all.equal(as.numeric(unlist(x, use.names = FALSE)),
    as.numeric(unlist(y, use.names = FALSE)), tolerance = 1e-9, check.attributes = FALSE))
  identical(as.integer(a$nrow), as.integer(b$nrow)) && identical(as.integer(a$ncol), as.integer(b$ncol)) &&
    identical(as.character(a$crs), as.character(b$crs)) && num_equal(a$res, b$res) && num_equal(a$extent, b$extent)
}

#' Validate metadata compatibility for a multi-input calculation
#'
#' Applies an operation-specific contract to provenance records or SpatRasters.
#' Known conflicts return `status = "failed"` in every mode. Missing metadata
#' warns by default and produces a failed report in strict mode. Calculation
#' callers must stop when the returned status is `failed`.
#'
#' @param inputs Named list of provenance records, SpatRasters, or result objects
#'   containing provenance. Meaningful names improve diagnostics.
#' @param operation One of `same_period`, `harmonized_units`, `harmonized_pair`, `harmonized_series`,
#'   `ratio`, `ratio_series`, `add`, `add_series`, `seasonal_ratio`,
#'   `time_series`, `complete_series`, or `water_productivity`.
#' @param mode Missing-metadata policy: `"warn"` (default) or `"strict"`.
#' @return List with status (`passed`, `warning`, or `failed`), errors, warnings,
#'   and check records.
#' @export
#' @examples
#' \dontrun{
#' wapor_validate_compatibility(list(yield = yield_meta, aeti = aeti_meta),
#'                              operation = "water_productivity")
#' }
wapor_validate_compatibility <- function(inputs,
  operation = c("same_period", "harmonized_units", "harmonized_pair", "harmonized_series", "ratio", "ratio_series", "add", "add_series", "seasonal_ratio", "time_series", "complete_series", "water_productivity"),
  mode = c("warn", "strict")) {
  operation <- match.arg(operation)
  mode <- match.arg(mode)
  if (!is.list(inputs) || length(inputs) < 2L) stop("'inputs' must be a list with at least two inputs", call. = FALSE)
  nms <- names(inputs)
  if (is.null(nms)) nms <- rep("", length(inputs))
  blank <- is.na(nms) | !nzchar(nms)
  nms[blank] <- paste0("input", which(blank))
  names(inputs) <- nms
  p <- lapply(inputs, .wapor_input_provenance)
  contracts <- list(
    same_period = c("period", "grid"),
    harmonized_units = c("units_equal"),
    harmonized_pair = c("period", "units_equal"),
    harmonized_series = c("intervals", "units_equal"),
    ratio = c("period", "grid", "units_known"),
    ratio_series = c("intervals", "grid", "units_known"),
    add_series = c("intervals", "grid", "units_equal"),
    seasonal_ratio = c("period", "grid", "units_known", "season"),
    add = c("period", "grid", "units_equal"),
    time_series = c("intervals", "grid", "units_known"),
    complete_series = c("intervals", "grid", "units_known", "coverage"),
    water_productivity = c("period", "intervals", "grid", "water_productivity_units", "season")
  )
  checks <- list(); errors <- character(); warnings <- character()
  add <- function(id, status, message, observed = NULL) {
    checks[[length(checks) + 1L]] <<- list(id = id, status = status, inputs = nms,
                                           message = message, observed = observed)
    if (status == "failed") errors <<- c(errors, message)
    if (status == "warning") warnings <<- c(warnings, message)
  }
  unknown <- function(id, msg) add(id, if (mode == "strict") "failed" else "warning", msg)
  fields <- contracts[[operation]]

  if ("period" %in% fields) {
    vals <- lapply(p, `[[`, "period")
    valid <- vapply(vals, function(x) is.list(x) && all(c("start", "end") %in% names(x)) &&
      length(x$start) == 1L && length(x$end) == 1L && !is.null(x$start) && !is.null(x$end) &&
      !is.na(x$start) && !is.na(x$end) && nzchar(as.character(x$start)) && nzchar(as.character(x$end)), logical(1))
    if (!all(valid)) unknown("temporal.period", "Analysis period metadata is unknown for one or more inputs.") else {
      keys <- vapply(vals, function(x) paste(x$start, x$end, sep = "/"), character(1))
      if (length(unique(keys)) > 1L) add("temporal.period", "failed",
        sprintf("Analysis periods differ: %s.", paste(paste(nms, keys, sep = "="), collapse = "; ")),
        stats::setNames(as.list(keys), nms)) else add("temporal.period", "passed", "Analysis periods match.", keys[[1]])
    }
  }

  if ("intervals" %in% fields) {
    vals <- lapply(p, function(x) {
      d <- x$intervals
      if (!is.data.frame(d) || !all(c("start_date", "end_date") %in% names(d)) || !nrow(d) ||
          anyNA(d$start_date) || anyNA(d$end_date)) return(NULL)
      paste(d$start_date, d$end_date, sep = "/")
    })
    if (any(vapply(vals, is.null, logical(1)))) unknown("temporal.intervals", "Complete ordered layer interval metadata is unknown for one or more inputs.") else if (
      !all(vapply(vals[-1], identical, logical(1), vals[[1]]))) add("temporal.intervals", "failed",
        "Ordered layer intervals differ between inputs.", stats::setNames(vals, nms)) else
        add("temporal.intervals", "passed", "Ordered layer intervals match.", vals[[1]])
  }

  if ("grid" %in% fields) {
    vals <- lapply(p, `[[`, "grid")
    if (any(vapply(vals, is.null, logical(1)))) unknown("spatial.grid", "Grid metadata is unknown for one or more inputs.") else {
      eq <- vapply(vals[-1], function(x) .wapor_grids_equal(vals[[1]], x), logical(1))
      if (anyNA(eq)) unknown("spatial.grid", "Grid signatures are incomplete for one or more inputs.") else if (!all(eq))
        add("spatial.grid", "failed", "Raster grid signatures differ between inputs.", stats::setNames(vals, nms)) else
          add("spatial.grid", "passed", "Raster grid signatures match.")
    }
  }

  if ("units_known" %in% fields) {
    dims <- vapply(p, function(x) .wapor_unit_dimension(x$units), character(1))
    if (anyNA(dims)) unknown("units.dimension", "One or more units are missing or have an unrecognized physical dimension.") else
      add("units.dimension", "passed", "All input units have recognized physical dimensions.", stats::setNames(as.list(dims), nms))
  }
  if ("units_equal" %in% fields) {
    labs <- vapply(p, function(x) .wapor_unit_label(x$units), character(1))
    if (anyNA(labs)) unknown("units.equal", "Unit metadata is missing for one or more inputs.") else if (length(unique(labs)) > 1L)
      add("units.equal", "failed", sprintf("Input units differ: %s.", paste(paste(nms, labs, sep = "="), collapse = "; ")),
          stats::setNames(as.list(labs), nms)) else add("units.equal", "passed", "Input units match.", labs[[1]])
  }
  if ("water_productivity_units" %in% fields) {
    dims <- vapply(p, function(x) .wapor_unit_dimension(x$units), character(1))
    num <- which(grepl("yield|biomass|numerator", nms, ignore.case = TRUE))
    den <- which(grepl("aeti|water|denominator", nms, ignore.case = TRUE))
    if (length(num) != 1L || length(den) != 1L || num == den) add("units.water_productivity", "failed",
      "Water-productivity inputs need one yield/biomass numerator and one AETI/water denominator.") else if (
        is.na(dims[num]) || is.na(dims[den])) unknown("units.water_productivity", "Water-productivity input units are missing or unrecognized.") else if (
          dims[num] != "mass_per_area" || dims[den] != "water_depth") add("units.water_productivity", "failed",
            sprintf("Water-productivity dimensions must be mass_per_area / water_depth; received %s / %s.", dims[num], dims[den])) else
              add("units.water_productivity", "passed", "Water-productivity input dimensions are compatible.")
  }
  if ("season" %in% fields) {
    vals <- lapply(p, `[[`, "season_definition")
    known <- vapply(vals, function(x) !is.null(x) && length(x) > 0L, logical(1))
    if (!all(known)) unknown("temporal.season_definition", "Season-definition lineage is unknown for one or more inputs.") else {
      json <- vapply(vals, function(x) as.character(jsonlite::toJSON(.wapor_json_safe(x), auto_unbox = TRUE)), character(1))
      if (length(unique(json)) > 1L) add("temporal.season_definition", "failed", "Season-definition lineage differs between inputs.") else
        add("temporal.season_definition", "passed", "Season-definition lineage matches.")
    }
  }
  if ("coverage" %in% fields) {
    vals <- lapply(p, `[[`, "coverage")
    known <- vapply(vals, function(x) is.list(x) && length(x$complete) == 1L && !is.na(x$complete), logical(1))
    if (!all(known)) unknown("coverage.complete", "Completeness metadata is unknown for one or more inputs.") else if (
      !all(vapply(vals, function(x) isTRUE(x$complete), logical(1)))) add("coverage.complete", "failed",
        "One or more inputs have incomplete temporal coverage.") else add("coverage.complete", "passed", "All inputs report complete coverage.")
  }

  status <- if (length(errors)) "failed" else if (length(warnings)) "warning" else "passed"
  report <- list(status = status, errors = unique(errors), warnings = unique(warnings), checks = checks)
  if (length(warnings)) warning(paste(unique(warnings), collapse = " "), call. = FALSE)
  report
}

#' Stop calculations on known compatibility failures
#' @keywords internal
#' @noRd
.wapor_require_compatible <- function(inputs, operation, mode = "warn") {
  report <- wapor_validate_compatibility(inputs, operation = operation, mode = mode)
  if (identical(report$status, "failed")) stop(paste(report$errors, collapse = " "), call. = FALSE)
  report
}
