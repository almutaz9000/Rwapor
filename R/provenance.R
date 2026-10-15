# =============================================================================
# Temporal provenance primitives
# =============================================================================

#' Resolve WaPOR temporal code from a variable code
#'
#' @keywords internal
#' @noRd
.wapor_temporal_code <- function(variable) {
  if (is.null(variable) || length(variable) != 1L || is.na(variable)) {
    return(NA_character_)
  }
  match <- regmatches(as.character(variable), regexpr("-(D|M|A|E)$", as.character(variable)))
  if (!length(match) || !nzchar(match)) return(NA_character_)
  sub("^-", "", match)
}

#' Resolve a WaPOR variable code embedded in a layer name
#'
#' @keywords internal
#' @noRd
.wapor_variable_code_from_name <- function(layer_name) {
  if (length(layer_name) != 1L || is.na(layer_name)) return(NA_character_)
  match <- regmatches(
    layer_name,
    regexpr(
      "(?<![A-Za-z0-9])(?:L[123]|AGERA5)-[A-Za-z0-9]+-[DMAE](?![A-Za-z0-9])",
      layer_name,
      perl = TRUE
    )
  )
  if (!length(match) || !nzchar(match)) NA_character_ else match
}

#' Parse a filename/date token to a closed temporal interval
#'
#' @keywords internal
#' @noRd
.wapor_interval_from_token <- function(token, temporal_code = NA_character_) {
  if (is.null(token) || length(token) != 1L || is.na(token) || !nzchar(token)) {
    return(NULL)
  }

  code <- temporal_code
  if (is.na(code) || !nzchar(code)) {
    code <- if (grepl("^[0-9]{4}-[0-9]{2}-D[123]$", token)) {
      "D"
    } else if (grepl("^[0-9]{4}-[0-9]{2}-[123]$", token)) {
      "D"
    } else if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$|^[0-9]{8}$", token)) {
      "E"
    } else if (grepl("^[0-9]{4}-[0-9]{2}$|^[0-9]{6}$", token)) {
      "M"
    } else if (grepl("^[0-9]{4}$", token)) {
      "A"
    } else {
      NA_character_
    }
  }
  if (is.na(code) || !code %in% c("D", "M", "A", "E")) return(NULL)

  date_token <- token
  if (code == "D" && grepl("^[0-9]{4}-[0-9]{2}-([0-9]{2})$", token)) {
    day <- as.integer(sub("^.*-([0-9]{2})$", "\\1", token))
    dekad <- if (day == 1L) "D1" else if (day == 11L) "D2" else if (day == 21L) "D3" else NA_character_
    if (is.na(dekad)) return(NULL)
    date_token <- paste0(substr(token, 1L, 7L), "-", dekad)
  } else if (code == "D" && grepl("^[0-9]{4}-[0-9]{2}-[123]$", token)) {
    date_token <- sub("-([123])$", "-D\\1", token)
  } else if (code == "M" && grepl("^[0-9]{6}$", token)) {
    date_token <- paste0(substr(token, 1L, 4L), "-", substr(token, 5L, 6L))
  } else if (code == "E" && grepl("^[0-9]{8}$", token)) {
    date_token <- paste(substr(token, 1L, 4L), substr(token, 5L, 6L), substr(token, 7L, 8L), sep = "-")
  }

  info <- tryCatch(
    wapor_date_info(paste0("layer.", date_token, ".tif"), code),
    error = function(e) NULL
  )
  if (is.null(info)) return(NULL)
  list(
    start_date = as.character(info$start_date),
    end_date = as.character(info$end_date),
    temporal_code = code
  )
}

#' Find a supported date token in a layer name
#'
#' @keywords internal
#' @noRd
.wapor_interval_from_layer_name <- function(layer_name, variable = NULL) {
  if (length(layer_name) != 1L || is.na(layer_name)) return(NULL)
  variable_code <- if (!is.null(variable)) as.character(variable)[1] else {
    .wapor_variable_code_from_name(layer_name)
  }
  code <- .wapor_temporal_code(variable_code)

  patterns <- c(
    "(?<![0-9])[0-9]{4}-[0-9]{2}-D[123](?![A-Za-z0-9])",
    "(?<![0-9])[0-9]{4}-[0-9]{2}-[123](?![0-9])",
    "(?<![0-9])[0-9]{4}-[0-9]{2}-[0-9]{2}(?![0-9])",
    "(?<![0-9])[0-9]{8}(?![0-9])",
    "(?<![0-9])[0-9]{4}-[0-9]{2}(?!-[0-9]{2})",
    "(?<![0-9])[0-9]{6}(?![0-9])",
    "(?<![0-9])[0-9]{4}(?![0-9])"
  )
  for (pattern in patterns) {
    token <- regmatches(layer_name, regexpr(pattern, layer_name, perl = TRUE))
    if (!length(token) || !nzchar(token)) next
    interval <- .wapor_interval_from_token(token, code)
    if (!is.null(interval)) return(interval)
  }
  NULL
}

#' Infer temporal intervals for each SpatRaster layer
#'
#' Complete `terra::time()` metadata takes precedence over layer names. If the
#' time vector is incomplete or unsupported, complete, parseable layer names are
#' used instead. Unknown dates remain NA; layer position and count never imply
#' dates.
#'
#' @param x A SpatRaster time series.
#' @param variable Optional WaPOR/AgERA5 variable code, such as `L1-AETI-M`.
#' @return A data.frame with one row per layer and temporal interval metadata.
#' @keywords internal
#' @noRd
.wapor_raster_intervals <- function(x, variable = NULL) {
  if (!inherits(x, "SpatRaster")) {
    stop("'x' must be a SpatRaster", call. = FALSE)
  }
  if (!is.null(variable) && (!is.character(variable) || length(variable) != 1L || is.na(variable) || !nzchar(variable))) {
    stop("'variable' must be NULL or one non-empty variable code", call. = FALSE)
  }

  n <- terra::nlyr(x)
  layer_names <- names(x)
  if (length(layer_names) != n) layer_names <- rep(NA_character_, n)
  code_from_variable <- .wapor_temporal_code(variable)
  time_values <- tryCatch(terra::time(x), error = function(e) NULL)
  complete_time <- length(time_values) == n && n > 0L &&
    !anyNA(time_values) && (inherits(time_values, "Date") || inherits(time_values, "POSIXt"))

  rows <- lapply(seq_len(n), function(i) {
    interval <- NULL
    metadata_source <- "unknown"
    if (complete_time) {
      time_date <- as.Date(time_values[i])
      code <- code_from_variable
      if (is.na(code)) code <- .wapor_temporal_code(.wapor_variable_code_from_name(layer_names[i]))
      if (is.na(code)) code <- "E"
      interval <- .wapor_interval_from_token(as.character(time_date), code)
      if (!is.null(interval)) metadata_source <- "terra_time"
    }
    if (is.null(interval)) {
      interval <- .wapor_interval_from_layer_name(layer_names[i], variable)
      if (!is.null(interval)) metadata_source <- "layer_name"
    }
    if (is.null(interval)) {
      interval <- list(start_date = NA_character_, end_date = NA_character_, temporal_code = NA_character_)
    }
    data.frame(
      layer = as.integer(i),
      layer_name = as.character(layer_names[i]),
      start_date = interval$start_date,
      end_date = interval$end_date,
      temporal_code = interval$temporal_code,
      metadata_source = metadata_source,
      stringsAsFactors = FALSE
    )
  })
  if (!length(rows)) {
    return(data.frame(
      layer = integer(), layer_name = character(), start_date = character(),
      end_date = character(), temporal_code = character(), metadata_source = character(),
      stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, rows)
}

#' Normalize common values for JSON-safe provenance records
#'
#' @keywords internal
#' @noRd
.wapor_json_safe <- function(x) {
  if (is.null(x)) return(NULL)
  if (inherits(x, "Date")) return(as.character(x))
  if (inherits(x, "POSIXt")) return(format(x, "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"))
  if (is.factor(x)) return(as.character(x))
  if (is.data.frame(x)) {
    out <- lapply(x, .wapor_json_safe)
    return(as.data.frame(out, stringsAsFactors = FALSE, optional = TRUE))
  }
  if (is.list(x)) return(lapply(x, .wapor_json_safe))
  if (is.atomic(x)) return(x)
  stop(sprintf("Unsupported provenance value of class %s", paste(class(x), collapse = "/")), call. = FALSE)
}

#' Build a schema-versioned provenance record
#'
#' @keywords internal
#' @noRd
.wapor_new_provenance <- function(variable = NULL, intervals = NULL, period = NULL,
                                  units = NULL, value_semantics = NULL, grid = NULL,
                                  coverage = NULL, operation = NULL, parents = NULL,
                                  season_definition = NULL, source = NULL,
                                  dataset_id = NULL) {
  if (!is.null(variable) && (!is.character(variable) || length(variable) != 1L || is.na(variable) || !nzchar(variable))) {
    stop("'variable' must be NULL or one non-empty character string", call. = FALSE)
  }
  if (!is.null(intervals)) {
    if (!is.data.frame(intervals) || !all(c("start_date", "end_date") %in% names(intervals))) {
      stop("'intervals' must be NULL or a data.frame with start_date and end_date columns", call. = FALSE)
    }
    intervals <- .wapor_json_safe(intervals)
  }
  if (is.null(period)) {
    starts <- if (!is.null(intervals)) intervals$start_date else character()
    ends <- if (!is.null(intervals)) intervals$end_date else character()
    starts <- starts[!is.na(starts)]
    ends <- ends[!is.na(ends)]
    period <- if (length(starts) && length(ends)) {
      list(start = min(starts), end = max(ends))
    } else {
      list(start = NULL, end = NULL)
    }
  } else if (inherits(period, "Date") && length(period) == 2L) {
    period <- list(start = as.character(period[[1]]), end = as.character(period[[2]]))
  } else if (is.character(period) && length(period) == 2L && all(!is.na(period))) {
    period <- list(start = period[[1]], end = period[[2]])
  } else if (!is.list(period) || !all(c("start", "end") %in% names(period))) {
    stop("'period' must be NULL, two dates, or a list with start and end", call. = FALSE)
  }

  code <- .wapor_temporal_code(variable)
  if (is.na(code) && !is.null(intervals) && "temporal_code" %in% names(intervals)) {
    codes <- unique(stats::na.omit(intervals$temporal_code))
    if (length(codes) == 1L) code <- as.character(codes[[1]])
  }
  safe_source <- NULL
  if (!is.null(source)) {
    if (!is.character(source) || length(source) != 1L || is.na(source)) {
      stop("'source' must be NULL or one character path/URL", call. = FALSE)
    }
    source_name <- sub("[?#].*$", "", gsub("\\\\", "/", source))
    safe_source <- list(identifier = basename(source_name))
  }

  record <- list(
    schema_version = 1L,
    dataset_id = NULL,
    variable = variable,
    temporal_resolution = if (is.na(code)) NULL else code,
    intervals = intervals,
    period = .wapor_json_safe(period),
    units = units,
    value_semantics = value_semantics,
    grid = .wapor_json_safe(grid),
    coverage = .wapor_json_safe(coverage),
    operation = operation,
    parents = .wapor_json_safe(parents),
    season_definition = .wapor_json_safe(season_definition),
    source = safe_source
  )
  record <- .wapor_json_safe(record)
  if (is.null(dataset_id)) {
    encoded <- jsonlite::toJSON(
      record, auto_unbox = TRUE, null = "null", na = "null",
      dataframe = "rows", POSIXt = "ISO8601", digits = NA
    )
    record$dataset_id <- digest::digest(as.character(encoded), algo = "sha256", serialize = FALSE)
  } else {
    if (!is.character(dataset_id) || length(dataset_id) != 1L || is.na(dataset_id) || !nzchar(dataset_id)) {
      stop("'dataset_id' must be NULL or one non-empty character string", call. = FALSE)
    }
    record$dataset_id <- dataset_id
  }
  class(record) <- c("wapor_provenance", "list")
  record
}
