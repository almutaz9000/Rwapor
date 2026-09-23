# R/processing_plan.R
# =============================================================================
# Size-aware processing planner
# =============================================================================
#
# Every raster entry point asks the planner how to run a job: fully in memory,
# streamed layer by layer, or split into spatial tiles. The decision is made
# from an estimate of the working set (bytes held at once) against a memory
# budget, so a small farm runs in memory without tiling while a large 20 m
# scheme is tiled automatically.

.wapor_processing_modes <- c("auto", "memory", "stream", "tiled")

#' Memory budget for one worker, in bytes
#'
#' `options(Rwapor.memory_budget_mb)` overrides the default of half the free
#' RAM reported by terra, divided by the number of parallel workers.
#' @keywords internal
#' @noRd
.wapor_memory_budget_bytes <- function(workers = 1L) {
  workers <- max(1L, as.integer(workers %||% 1L))
  opt <- getOption("Rwapor.memory_budget_mb", NULL)
  if (!is.null(opt)) {
    opt <- as.numeric(opt)
    if (length(opt) != 1L || !is.finite(opt) || opt <= 0) {
      stop("options(Rwapor.memory_budget_mb) must be a single positive number.", call. = FALSE)
    }
    return(opt * 1024^2 / workers)
  }
  # terra::free_RAM() reports kilobytes.
  free_kb <- tryCatch(as.numeric(terra::free_RAM()), error = function(e) NA_real_)
  if (!is.finite(free_kb) || free_kb <= 0) {
    free_kb <- 4 * 1024^2
  }
  free_kb * 1024 * 0.5 / workers
}

#' Mode thresholds as fractions of the memory budget
#' @keywords internal
#' @noRd
.wapor_plan_thresholds <- function() {
  defaults <- c(memory = 0.25, stream = 1, layer = 0.10)
  opt <- getOption("Rwapor.plan_thresholds", NULL)
  if (is.null(opt)) {
    return(defaults)
  }
  opt <- unlist(opt)
  if (is.null(names(opt)) || !all(names(opt) %in% names(defaults)) || any(!is.finite(opt)) || any(opt <= 0)) {
    stop(
      "options(Rwapor.plan_thresholds) must be a named numeric vector using ",
      "'memory', 'stream' and/or 'layer', each > 0.",
      call. = FALSE
    )
  }
  defaults[names(opt)] <- as.numeric(opt)
  defaults
}

#' Maximum number of season profiles for native-resolution aggregation
#' @keywords internal
#' @noRd
.wapor_max_season_profiles <- function() {
  v <- getOption("Rwapor.max_season_profiles", 64L)
  v <- suppressWarnings(as.integer(v))
  if (length(v) != 1L || is.na(v) || v < 1L) {
    stop("options(Rwapor.max_season_profiles) must be a single positive integer.", call. = FALSE)
  }
  v
}

#' Number of parallel workers under the user's future plan
#' @keywords internal
#' @noRd
.wapor_n_workers <- function() {
  n <- tryCatch(future::nbrOfWorkers(), error = function(e) 1L)
  n <- suppressWarnings(as.integer(n))
  if (length(n) != 1L || is.na(n) || n < 1L) 1L else n
}

#' Working-set estimate for one window, in bytes
#'
#' Values are held as 8-byte doubles. `frac` is the share of the analysis area
#' in one window; `batch` is how many dekads are read at once.
#' @keywords internal
#' @noRd
.wapor_working_set_bytes <- function(analysis_cells, native_cells, n_layers, n_targets,
                                     batch, frac = 1) {
  native_cells <- as.numeric(native_cells)
  analysis_cells <- as.numeric(analysis_cells)
  # Native reads: values plus validity for one batch of dekads.
  read_bytes <- sum(native_cells) * frac * batch * 8 * 2
  # Accumulators: one value and one coverage accumulator per output target.
  acc_bytes <- sum(native_cells) * frac * n_targets * 8 * 2
  # Analysis grid: per-pixel coefficients for one batch, plus the outputs.
  out_bytes <- analysis_cells * frac * (batch + n_targets * length(native_cells) + 6) * 8
  # R temporaries (masked copies, row sums) add roughly half again; measured
  # on a 1500 x 1500, 18-dekad job.
  1.5 * (read_bytes + acc_bytes + out_bytes)
}

#' Decide processing mode, batch size and tile size (internal core)
#' @keywords internal
#' @noRd
.wapor_plan_core <- function(analysis_nrow, analysis_ncol, native_cells, n_layers,
                             n_targets = 1L, n_profiles = 1L,
                             processing = "auto", workers = NULL,
                             bytes_per_file_window = NULL) {
  processing <- match.arg(processing, .wapor_processing_modes)
  workers <- workers %||% .wapor_n_workers()
  workers <- max(1L, as.integer(workers))
  analysis_nrow <- as.numeric(analysis_nrow)
  analysis_ncol <- as.numeric(analysis_ncol)
  analysis_cells <- analysis_nrow * analysis_ncol
  native_cells <- if (length(native_cells)) as.numeric(native_cells) else analysis_cells
  n_layers <- max(1L, as.integer(n_layers))
  n_targets <- max(1L, as.integer(n_targets))

  budget <- .wapor_memory_budget_bytes(workers)
  thr <- .wapor_plan_thresholds()

  full_memory <- .wapor_working_set_bytes(analysis_cells, native_cells, n_layers, n_targets,
                                          batch = n_layers, frac = 1)
  single_layer <- analysis_cells * 8
  reasons <- character(0)
  reasons <- c(reasons, sprintf(
    "Estimated working set in memory: %s (budget %s per worker, %d worker(s)).",
    .wapor_format_bytes(full_memory), .wapor_format_bytes(budget), workers
  ))

  auto_mode <- if (single_layer > thr[["layer"]] * budget) {
    reasons <- c(reasons, sprintf(
      "One analysis layer is %s, above %.0f%% of the budget: tiling.",
      .wapor_format_bytes(single_layer), 100 * thr[["layer"]]
    ))
    "tiled"
  } else if (full_memory <= thr[["memory"]] * budget) {
    reasons <- c(reasons, sprintf("Working set is below %.0f%% of the budget: in memory.", 100 * thr[["memory"]]))
    "memory"
  } else if (.wapor_working_set_bytes(analysis_cells, native_cells, n_layers, n_targets, batch = 1L) <=
             thr[["stream"]] * budget) {
    reasons <- c(reasons, "Full stack does not fit comfortably, but streaming layer batches does: stream.")
    "stream"
  } else {
    reasons <- c(reasons, "Even one layer batch over the whole area exceeds the budget: tiling.")
    "tiled"
  }

  mode <- if (identical(processing, "auto")) auto_mode else processing
  if (!identical(processing, "auto")) {
    reasons <- c(reasons, sprintf("Mode forced to '%s' (auto would choose '%s').", processing, auto_mode))
    if (identical(processing, "memory") && full_memory > budget) {
      warning(sprintf(
        "processing = 'memory' needs about %s but the budget is %s; the job may run out of memory.",
        .wapor_format_bytes(full_memory), .wapor_format_bytes(budget)
      ), call. = FALSE)
    }
  }

  # Largest batch of dekads that fits the budget over the whole area.
  fit_batch <- function(frac) {
    b <- n_layers
    while (b > 1L && .wapor_working_set_bytes(analysis_cells, native_cells, n_layers, n_targets,
                                               batch = b, frac = frac) > budget) {
      b <- max(1L, b %/% 2L)
    }
    as.integer(b)
  }

  tile_size <- NA_integer_
  batch_size <- n_layers
  if (identical(mode, "stream")) {
    batch_size <- fit_batch(1)
  } else if (identical(mode, "tiled")) {
    # Largest square tile whose working set (one-dekad batches) fits the budget.
    per_cell <- .wapor_working_set_bytes(1, native_cells / analysis_cells, n_layers, n_targets,
                                         batch = 1L, frac = 1)
    side <- floor(sqrt(budget / max(per_cell, 1)))
    tile_size <- as.integer(max(64L, min(4096L, side)))
    tile_size <- as.integer(min(tile_size, max(analysis_nrow, analysis_ncol)))
    frac <- min(1, (as.numeric(tile_size)^2) / max(analysis_cells, 1))
    batch_size <- fit_batch(frac)
  }

  chunk <- .wapor_gdal_chunk_bytes(bytes_per_file_window)

  structure(
    list(
      mode = mode,
      auto_mode = auto_mode,
      processing = processing,
      analysis_grid = c(nrow = analysis_nrow, ncol = analysis_ncol),
      cells = analysis_cells,
      native_cells = native_cells,
      n_layers = n_layers,
      n_targets = n_targets,
      n_profiles = as.integer(n_profiles),
      workers = workers,
      working_set_bytes = full_memory,
      budget_bytes = budget,
      tile_size = tile_size,
      batch_size = as.integer(batch_size),
      gdal_chunk_bytes = chunk,
      reasons = reasons
    ),
    class = "wapor_plan"
  )
}

#' Region bounding box in EPSG:4326 (NULL for L3 codes)
#' @keywords internal
#' @noRd
.wapor_region_bbox <- function(reg_info) {
  if (is.null(reg_info)) return(NULL)
  if (identical(reg_info$type, "bbox")) {
    return(as.numeric(reg_info$value))
  }
  if (identical(reg_info$type, "vector")) {
    v <- reg_info$value
    crs <- sf::st_crs(v)
    if (!is.na(crs) && !isTRUE(crs$epsg == 4326)) v <- sf::st_transform(v, 4326)
    return(as.numeric(sf::st_bbox(v)))
  }
  NULL
}

#' Number of source cells inside a region (from the header only; no pixel reads)
#' @keywords internal
#' @noRd
.wapor_region_cells <- function(r, reg_info) {
  full <- as.numeric(terra::ncell(r))
  bb <- tryCatch(.wapor_region_bbox(reg_info), error = function(e) NULL)
  if (is.null(bb) || !isTRUE(terra::is.lonlat(r))) return(full)
  e <- terra::intersect(terra::ext(bb[1], bb[3], bb[2], bb[4]), terra::ext(r))
  if (is.null(e)) return(0)
  res <- terra::res(r)
  cells <- ((terra::xmax(e) - terra::xmin(e)) / res[1] + 1) *
    ((terra::ymax(e) - terra::ymin(e)) / res[2] + 1)
  min(full, cells)
}

#' Plan batch size and GDAL chunk size for a download or time-series job
#'
#' @param urls Source paths or /vsicurl/ URLs, one per layer.
#' @param reg_info Parsed region.
#' @param n_targets Outputs held per cell (for example mean, min, max).
#' @keywords internal
#' @noRd
.wapor_io_plan <- function(urls, reg_info, processing = "auto", n_targets = 3L) {
  n_layers <- max(1L, length(urls))
  first <- tryCatch(terra::rast(urls[[1]]), error = function(e) NULL)
  cells <- if (is.null(first)) 1e6 else max(1, .wapor_region_cells(first, reg_info))
  side <- sqrt(cells)
  .wapor_plan_core(
    analysis_nrow = side, analysis_ncol = side, native_cells = cells,
    n_layers = n_layers, n_targets = n_targets, processing = processing,
    bytes_per_file_window = cells * 4
  )
}

#' Batch size from an explicit value or the plan (capped for retry granularity)
#' @keywords internal
#' @noRd
.wapor_resolve_batch_size <- function(batch_size, plan, cap = 36L) {
  if (!is.null(batch_size)) {
    if (!is.numeric(batch_size) || length(batch_size) != 1 || is.na(batch_size) || batch_size < 1) {
      stop("'batch_size' must be a positive integer", call. = FALSE)
    }
    return(as.integer(batch_size))
  }
  as.integer(max(1L, min(cap, plan$batch_size)))
}

#' GDAL HTTP chunk size matched to the bytes one file window needs
#' @keywords internal
#' @noRd
.wapor_gdal_chunk_bytes <- function(bytes_per_file_window = NULL) {
  lo <- 256 * 1024
  hi <- 10 * 1024^2
  if (is.null(bytes_per_file_window) || !is.finite(bytes_per_file_window)) {
    return(as.integer(hi))
  }
  as.integer(max(lo, min(hi, 2^ceiling(log2(max(1, bytes_per_file_window))))))
}

.wapor_format_bytes <- function(x) {
  x <- as.numeric(x)
  units <- c("B", "KB", "MB", "GB", "TB")
  i <- 1L
  while (x >= 1024 && i < length(units)) {
    x <- x / 1024
    i <- i + 1L
  }
  sprintf("%.1f %s", x, units[i])
}

#' Plan How a Raster Job Should Be Processed
#'
#' Estimates the memory a job needs and chooses how to run it:
#' * `"memory"`: the whole area and every dekad are processed at once.
#' * `"stream"`: the whole area is processed, reading dekads in batches.
#' * `"tiled"`: the area is split into square tiles, each streamed separately
#'   and assembled with a VRT. Tiles run in parallel under the active
#'   [future::plan()].
#'
#' Results are identical whichever mode runs; only memory use and speed differ.
#'
#' @param template Optional `SpatRaster` defining the analysis grid.
#' @param aoi Optional bounding box `c(xmin, ymin, xmax, ymax)` in degrees, used
#'   with `resolution` when no template is available.
#' @param resolution Analysis resolution in metres (for example 20, 100 or 300),
#'   used with `aoi`.
#' @param n_layers Integer. Dekads per variable (36 for one year).
#' @param n_vars Integer. Number of variables read.
#' @param native_resolution Optional numeric vector of each variable's native
#'   resolution in metres. Defaults to the analysis resolution.
#' @param n_targets Integer. Outputs accumulated per variable (the season plus
#'   each month). Default `1 + ceiling(n_layers / 3)`.
#' @param n_profiles Integer. Unique season profiles (crop class, start, end).
#' @param workers Integer. Parallel workers. Defaults to [future::nbrOfWorkers()].
#' @param processing One of `"auto"`, `"memory"`, `"stream"`, `"tiled"`.
#'
#' @return An object of class `wapor_plan` with the chosen `mode`, the
#'   estimate (`working_set_bytes`, `budget_bytes`), `batch_size`, `tile_size`,
#'   `gdal_chunk_bytes`, and the `reasons` for the choice.
#'
#' @details
#' The memory budget is half of the free RAM divided by the number of workers.
#' Override it with `options(Rwapor.memory_budget_mb = ...)`. Mode thresholds
#' (fractions of the budget) can be changed with
#' `options(Rwapor.plan_thresholds = c(memory = 0.25, stream = 1, layer = 0.1))`.
#'
#' @examples
#' # A 5 km x 5 km farm at 20 m for one year: runs in memory
#' wapor_plan_processing(aoi = c(35, 33, 35.05, 33.05), resolution = 20, n_layers = 36)
#'
#' # A 150 km x 150 km scheme at 20 m: tiled
#' wapor_plan_processing(aoi = c(35, 33, 36.5, 34.5), resolution = 20,
#'                       n_layers = 36, n_vars = 4)
#' @export
wapor_plan_processing <- function(template = NULL, aoi = NULL, resolution = NULL,
                                  n_layers = 36L, n_vars = 1L,
                                  native_resolution = NULL,
                                  n_targets = NULL, n_profiles = 1L,
                                  workers = NULL,
                                  processing = c("auto", "memory", "stream", "tiled")) {
  processing <- match.arg(processing)
  if (inherits(template, "SpatRaster")) {
    nr <- terra::nrow(template)
    nc <- terra::ncol(template)
    res_m <- if (isTRUE(terra::is.lonlat(template))) {
      terra::res(template)[1] * 111320
    } else {
      terra::res(template)[1]
    }
  } else {
    if (is.null(aoi) || is.null(resolution)) {
      stop("Supply either 'template', or both 'aoi' and 'resolution'.", call. = FALSE)
    }
    if (!is.numeric(aoi) || length(aoi) != 4L) {
      stop("'aoi' must be c(xmin, ymin, xmax, ymax) in degrees.", call. = FALSE)
    }
    lat <- mean(aoi[c(2, 4)])
    width_m <- abs(aoi[3] - aoi[1]) * 111320 * cos(lat * pi / 180)
    height_m <- abs(aoi[4] - aoi[2]) * 110574
    res_m <- as.numeric(resolution)
    nr <- ceiling(height_m / res_m)
    nc <- ceiling(width_m / res_m)
  }
  n_vars <- max(1L, as.integer(n_vars))
  native_resolution <- native_resolution %||% rep(res_m, n_vars)
  native_resolution <- rep_len(as.numeric(native_resolution), n_vars)
  native_cells <- (as.numeric(nr) * as.numeric(nc)) * (res_m / native_resolution)^2
  n_targets <- n_targets %||% (1L + as.integer(ceiling(n_layers / 3)))
  .wapor_plan_core(
    analysis_nrow = nr, analysis_ncol = nc, native_cells = native_cells,
    n_layers = n_layers, n_targets = n_targets, n_profiles = n_profiles,
    processing = processing, workers = workers,
    bytes_per_file_window = max(native_cells) * 4
  )
}

#' @export
print.wapor_plan <- function(x, ...) {
  cat("<wapor_plan>\n")
  cat(sprintf("  mode        : %s%s\n", x$mode,
              if (!identical(x$processing, "auto")) sprintf(" (forced; auto = %s)", x$auto_mode) else ""))
  cat(sprintf("  grid        : %s x %s cells\n",
              format(x$analysis_grid[["nrow"]], big.mark = ","),
              format(x$analysis_grid[["ncol"]], big.mark = ",")))
  cat(sprintf("  layers      : %d dekad(s), %d output target(s), %d season profile(s)\n",
              x$n_layers, x$n_targets, x$n_profiles))
  cat(sprintf("  working set : %s (budget %s, %d worker(s))\n",
              .wapor_format_bytes(x$working_set_bytes), .wapor_format_bytes(x$budget_bytes), x$workers))
  cat(sprintf("  batch size  : %d dekad(s)\n", x$batch_size))
  if (!is.na(x$tile_size)) cat(sprintf("  tile size   : %d px\n", x$tile_size))
  cat(sprintf("  GDAL chunk  : %s\n", .wapor_format_bytes(x$gdal_chunk_bytes)))
  cat("  reasons     :\n")
  for (r in x$reasons) cat("    - ", r, "\n", sep = "")
  invisible(x)
}
