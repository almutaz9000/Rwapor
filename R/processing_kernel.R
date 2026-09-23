# R/processing_kernel.R
# =============================================================================
# Shared window kernel for seasonal aggregation
# =============================================================================
#
# Memory, stream and tiled modes all run `.wapor_kernel_window()`; they differ
# only in how the analysis area is split into windows and how many dekads are
# read per batch. Each output pixel depends only on the source pixels inside a
# fixed halo around it, so every mode returns the same values.
#
# Aggregation follows three rules:
#   1. Linear steps (weighted dekad sums) run at the source's native
#      resolution, with one scalar weight vector per season profile.
#   2. The native sums are resampled once onto the analysis grid.
#   3. Non-linear steps (Peff, ratios, yield) run afterwards on the analysis
#      grid, in the engine.
#
# A season profile is a unique (crop class, season start, season end) triple.
# Paths per variable:
#   * "aligned":   native grid == analysis grid; each pixel is summed with its
#                  own profile's weights. No resampling, no profile limit.
#   * "native":    native grid differs and is not finer; sums are accumulated
#                  per unique weight vector at native resolution, resampled
#                  once, then each pixel takes its own profile's column.
#   * "per_dekad": fallback when there are too many profiles or the source is
#                  finer than the analysis grid; each dekad is resampled onto
#                  the analysis grid first (the v1.0.0 order).
#
# Coverage: for every pixel and output, the share of season days that have
# data. Pixels below `min_coverage` (default 1: every dekad must have data)
# are NA instead of silently counting missing dekads as zero.

.WAPOR_KEY_CLASS_FACTOR <- 4e6
.WAPOR_KEY_DAY_OFFSET <- 1000
.WAPOR_KEY_DAY_SPAN <- 2000
.WAPOR_KERNEL_HALO <- 3L

# -----------------------------------------------------------------------------
# Season profiles
# -----------------------------------------------------------------------------

#' Encode (class, start, end) as one numeric key raster
#'
#' The season end is moved into continuous Julian days for cross-year seasons
#' (end < start), matching `wapor_build_season_weights()`.
#' @keywords internal
#' @noRd
.wapor_profile_key_raster <- function(h_mask, h_start, h_end, reference_year) {
  ref_days <- if (lubridate::leap_year(as.integer(reference_year))) 366L else 365L
  s <- round(h_start)
  e <- round(h_end)
  e <- terra::ifel(e < s, e + ref_days, e)
  rng <- terra::global(c(s, e), c("min", "max"), na.rm = TRUE)
  lo <- min(rng$min, na.rm = TRUE)
  hi <- max(rng$max, na.rm = TRUE)
  if (is.finite(lo) && is.finite(hi) &&
      (lo + .WAPOR_KEY_DAY_OFFSET < 0 || hi + .WAPOR_KEY_DAY_OFFSET >= .WAPOR_KEY_DAY_SPAN)) {
    stop(sprintf(
      "Season start/end values must lie between %d and %d days; found %s to %s.",
      -.WAPOR_KEY_DAY_OFFSET, .WAPOR_KEY_DAY_SPAN - .WAPOR_KEY_DAY_OFFSET - 1L, lo, hi
    ), call. = FALSE)
  }
  key <- round(h_mask) * .WAPOR_KEY_CLASS_FACTOR +
    (s + .WAPOR_KEY_DAY_OFFSET) * .WAPOR_KEY_DAY_SPAN +
    (e + .WAPOR_KEY_DAY_OFFSET)
  names(key) <- "profile_key"
  key
}

#' Decode profile keys into a profile table
#' @keywords internal
#' @noRd
.wapor_decode_profile_keys <- function(keys) {
  keys <- sort(unique(as.numeric(keys[is.finite(keys)])))
  cls <- floor(keys / .WAPOR_KEY_CLASS_FACTOR)
  rem <- keys - cls * .WAPOR_KEY_CLASS_FACTOR
  s <- floor(rem / .WAPOR_KEY_DAY_SPAN) - .WAPOR_KEY_DAY_OFFSET
  e <- rem %% .WAPOR_KEY_DAY_SPAN - .WAPOR_KEY_DAY_OFFSET
  data.frame(
    key = keys,
    class_value = as.integer(cls),
    start_jd = as.integer(s),
    end_jd = as.integer(e),
    total_days = as.integer(e - s + 1L),
    stringsAsFactors = FALSE
  )
}

#' Unique season profiles present in a key raster (block-wise)
#' @keywords internal
#' @noRd
.wapor_profiles_from_keys <- function(key_r) {
  u <- terra::unique(key_r, na.rm = TRUE)
  vals <- if (is.null(u) || !length(u)) numeric(0) else as.numeric(u[[1]])
  .wapor_decode_profile_keys(vals)
}

#' Per-profile dekad weights (fraction) and overlap days
#'
#' Same overlap arithmetic as `wapor_build_season_weights()`, computed once per
#' profile as scalars instead of once per pixel as rasters.
#' @keywords internal
#' @noRd
.wapor_profile_dekad_weights <- function(profiles, dekad_table, reference_year) {
  K <- nrow(profiles)
  L <- nrow(dekad_table)
  d_start <- vapply(seq_len(L), function(i) {
    wapor_continuous_julian(dekad_table$dekad_start[i], reference_year)
  }, numeric(1))
  d_end <- vapply(seq_len(L), function(i) {
    wapor_continuous_julian(dekad_table$dekad_end[i], reference_year)
  }, numeric(1))
  days <- matrix(0, nrow = K, ncol = L)
  for (i in seq_len(L)) {
    o_start <- pmax(profiles$start_jd, d_start[i])
    o_end <- pmin(profiles$end_jd, d_end[i])
    days[, i] <- pmax(o_end - o_start + 1, 0)
  }
  frac <- sweep(days, 2, as.numeric(dekad_table$n_days), "/")
  list(weights = frac, days = days)
}

#' Per-profile dekadal Kc (NA rows for classes without crop parameters)
#' @keywords internal
#' @noRd
.wapor_profile_kc <- function(profiles, crop_params, dekad_table, reference_year) {
  K <- nrow(profiles)
  L <- nrow(dekad_table)
  kc <- matrix(NA_real_, nrow = K, ncol = L)
  if (!K || is.null(crop_params) || !nrow(crop_params)) {
    return(kc)
  }
  cache <- list()
  for (k in seq_len(K)) {
    cp <- crop_params[crop_params$class_value == profiles$class_value[k], , drop = FALSE]
    if (!nrow(cp) || profiles$total_days[k] <= 0L) next
    fixed_sum <- cp$l_ini_days[1] + cp$l_mid_days[1] + cp$l_late_days[1]
    l_dev <- max(0L, as.integer(profiles$total_days[k] - fixed_sum))
    ck <- paste(profiles$class_value[k], profiles$start_jd[k], l_dev, sep = "_")
    if (is.null(cache[[ck]])) {
      kc_daily <- wapor_build_kc(
        kc_ini = cp$kc_ini[1], kc_mid = cp$kc_mid[1], kc_end = cp$kc_end[1],
        l_ini = cp$l_ini_days[1], l_dev = l_dev,
        l_mid = cp$l_mid_days[1], l_late = cp$l_late_days[1]
      )
      season_start_date <- as.Date(sprintf("%04d-01-01", as.integer(reference_year))) +
        profiles$start_jd[k] - 1L
      cache[[ck]] <- wapor_aggregate_kc(kc_daily, dekad_table, season_start_date)
    }
    kc[k, ] <- cache[[ck]]
  }
  kc
}

#' Month targets: dekad indices for each calendar month in the period
#' @keywords internal
#' @noRd
.wapor_month_targets <- function(dekad_table) {
  dates <- if ("dekad_start" %in% names(dekad_table)) {
    as.Date(dekad_table$dekad_start)
  } else {
    as.Date(dekad_table$dekad_key)
  }
  keys <- format(dates, "%Y-%m")
  lapply(stats::setNames(unique(keys), unique(keys)), function(k) which(keys == k))
}

# -----------------------------------------------------------------------------
# Grids, windows and reads
# -----------------------------------------------------------------------------

#' TRUE when two rasters share CRS, resolution and cell alignment
#' @keywords internal
#' @noRd
.wapor_grids_aligned <- function(a, b, tol = 1e-6) {
  if (!identical(terra::crs(a), terra::crs(b))) {
    same_crs <- tryCatch(terra::same.crs(a, b), error = function(e) FALSE)
    if (!isTRUE(same_crs)) return(FALSE)
  }
  ra <- terra::res(a)
  rb <- terra::res(b)
  if (any(abs(ra - rb) > tol * pmax(abs(ra), 1e-12))) return(FALSE)
  off <- (c(terra::xmin(a), terra::ymax(a)) - c(terra::xmin(b), terra::ymax(b))) / ra
  all(abs(off - round(off)) < 1e-4)
}

#' Native-CRS extent covering a tile, expanded by a halo of native cells
#' @keywords internal
#' @noRd
.wapor_native_window_ext <- function(native_r, tile_template, halo = .WAPOR_KERNEL_HALO) {
  e <- terra::ext(tile_template)
  same_crs <- isTRUE(tryCatch(terra::same.crs(native_r, tile_template), error = function(err) FALSE))
  if (!same_crs) {
    poly <- terra::as.polygons(e, crs = terra::crs(tile_template))
    poly <- terra::densify(poly, interval = max(terra::res(tile_template)))
    e <- terra::ext(terra::project(poly, terra::crs(native_r)))
  }
  res <- terra::res(native_r)
  e <- terra::ext(
    terra::xmin(e) - halo * res[1], terra::xmax(e) + halo * res[1],
    terra::ymin(e) - halo * res[2], terra::ymax(e) + halo * res[2]
  )
  terra::intersect(e, terra::ext(native_r))
}

#' Read one batch of dekads over a native window: a cells x layers matrix
#' @keywords internal
#' @noRd
.wapor_read_native_batch <- function(paths, e, remote = FALSE, snap = "out") {
  op <- function() {
    layers <- lapply(paths, function(p) terra::rast(p, lyrs = 1L))
    stacked <- tryCatch(terra::rast(layers), error = function(err) NULL)
    if (is.null(stacked)) {
      # Sources on different grids: bring every layer onto the first one.
      first <- terra::crop(layers[[1]], e, snap = snap)
      cropped <- lapply(layers, function(l) {
        out <- terra::crop(l, e, snap = snap)
        if (!isTRUE(terra::compareGeom(out, first, stopOnError = FALSE))) {
          out <- terra::resample(out, first, method = "near")
        }
        out
      })
      w <- terra::rast(cropped)
    } else {
      w <- terra::crop(stacked, e, snap = snap)
    }
    list(geom = terra::rast(w[[1]]), X = terra::values(w, mat = TRUE))
  }
  out <- if (isTRUE(remote)) {
    .wapor_retry_remote_operation(op, label = sprintf("window read (%d layer(s))", length(paths)))
  } else {
    op()
  }
  .wapor_note_tiled_cells(nrow(out$X))
  out
}

#' Move native-grid columns onto the tile grid (resample or project)
#' @keywords internal
#' @noRd
.wapor_native_to_tile <- function(geom, values_mat, tile_template, method) {
  r <- terra::rast(geom, nlyrs = ncol(values_mat))
  terra::values(r) <- values_mat
  moved <- if (isTRUE(tryCatch(terra::same.crs(r, tile_template), error = function(e) FALSE))) {
    terra::resample(r, tile_template, method = method, wopt = list(datatype = "FLT8S"))
  } else {
    terra::project(r, tile_template, method = method, wopt = list(datatype = "FLT8S"))
  }
  terra::values(moved, mat = TRUE)
}

# -----------------------------------------------------------------------------
# Accumulation
# -----------------------------------------------------------------------------

#' One source (a set of dekadal files on one grid) and the outputs it feeds
#'
#' `sets` is a named list of outputs computed from the same files, for example
#' RET totals and ETc. Each set has `coef` (profiles x dekads), the multiplier
#' applied to each dekad value, and `days` (profiles x dekads), the season days
#' each dekad covers, used for coverage. The files are read once per window and
#' every set is accumulated from the same read.
#' @keywords internal
#' @noRd
.wapor_kernel_spec <- function(name, variable, paths, sets, method, path, remote) {
  list(
    name = name, variable = variable, paths = paths, sets = sets,
    method = method, path = path, remote = remote
  )
}

#' Combine sums and coverage into output values for one target
#' @keywords internal
#' @noRd
.wapor_finish_target <- function(sum_vec, valid_days, denom, pid, min_coverage) {
  out <- sum_vec
  cov <- ifelse(denom > 0, valid_days / denom, 1)
  out[is.na(pid)] <- NA_real_
  cov[is.na(pid)] <- NA_real_
  out[!is.na(cov) & cov < min_coverage - 1e-9] <- NA_real_
  list(value = out, coverage = cov)
}

#' Aligned path: each pixel summed with its own profile's coefficients
#' @keywords internal
#' @noRd
.wapor_accumulate_pixelwise <- function(read_batch, spec, pid, targets, batches, min_coverage) {
  M <- length(pid)
  K <- nrow(spec$sets[[1]]$coef)
  pid_safe <- ifelse(is.na(pid), K + 1L, pid)
  sets <- lapply(spec$sets, function(st) list(coef = rbind(st$coef, 0), days = rbind(st$days, 0)))
  zero <- function() lapply(targets, function(tg) numeric(M))
  sums <- lapply(sets, function(st) zero())
  valid <- lapply(sets, function(st) zero())
  for (b in batches) {
    X <- read_batch(b)
    ok <- !is.na(X)
    X[!ok] <- 0
    for (sn in names(sets)) {
      wx <- X * sets[[sn]]$coef[pid_safe, b, drop = FALSE]
      vx <- ok * sets[[sn]]$days[pid_safe, b, drop = FALSE]
      for (tg in names(targets)) {
        cols <- which(b %in% targets[[tg]])
        if (!length(cols)) next
        sums[[sn]][[tg]] <- sums[[sn]][[tg]] + rowSums(wx[, cols, drop = FALSE])
        valid[[sn]][[tg]] <- valid[[sn]][[tg]] + rowSums(vx[, cols, drop = FALSE])
      }
    }
  }
  # Finish one output at a time, releasing its accumulators as it goes.
  out <- lapply(sets, function(st) list())
  for (sn in names(sets)) {
    for (tg in names(targets)) {
      denom <- rowSums(sets[[sn]]$days[, targets[[tg]], drop = FALSE])[pid_safe]
      res <- .wapor_finish_target(sums[[sn]][[tg]], valid[[sn]][[tg]], denom, pid, min_coverage)
      sums[[sn]][tg] <- list(NULL)
      valid[[sn]][tg] <- list(NULL)
      if (!identical(tg, "season")) res$coverage <- NULL
      out[[sn]][[tg]] <- res
    }
  }
  out
}

#' Native path: accumulate per unique coefficient vector, resample once
#' @keywords internal
#' @noRd
.wapor_accumulate_native <- function(read_batch, geom, spec, pid, targets, batches,
                                     tile_template, min_coverage) {
  L <- ncol(spec$sets[[1]]$coef)
  make_group <- function(st, idx) {
    mat <- cbind(st$coef[, idx, drop = FALSE], st$days[, idx, drop = FALSE])
    key <- apply(mat, 1, function(row) paste(format(row, digits = 17), collapse = "|"))
    ukey <- unique(key)
    first <- match(ukey, key)
    C <- matrix(0, nrow = L, ncol = length(ukey))
    D <- matrix(0, nrow = L, ncol = length(ukey))
    C[idx, ] <- t(st$coef[first, idx, drop = FALSE])
    D[idx, ] <- t(st$days[first, idx, drop = FALSE])
    list(map = match(key, ukey), C = C, D = D, denom = colSums(D))
  }
  # One group per (output set, target); all are fed from the same reads.
  groups <- list()
  for (sn in names(spec$sets)) {
    for (tg in names(targets)) {
      groups[[length(groups) + 1L]] <- c(make_group(spec$sets[[sn]], targets[[tg]]),
                                         list(set = sn, target = tg))
    }
  }
  acc_sum <- NULL
  acc_valid <- NULL
  for (b in batches) {
    X <- read_batch(b)
    ok <- !is.na(X)
    X[!ok] <- 0
    s_parts <- lapply(groups, function(g) X %*% g$C[b, , drop = FALSE])
    v_parts <- lapply(groups, function(g) ok %*% g$D[b, , drop = FALSE])
    if (is.null(acc_sum)) {
      acc_sum <- s_parts
      acc_valid <- v_parts
    } else {
      for (j in seq_along(groups)) {
        acc_sum[[j]] <- acc_sum[[j]] + s_parts[[j]]
        acc_valid[[j]] <- acc_valid[[j]] + v_parts[[j]]
      }
    }
  }
  # Resample one output at a time so only that output's columns exist on the
  # analysis grid (all groups at once would hold cells x groups doubles).
  M <- length(pid)
  rows <- seq_len(M)
  out <- lapply(spec$sets, function(st) list())
  for (j in seq_along(groups)) {
    g <- groups[[j]]
    w <- ncol(g$C)
    moved <- .wapor_native_to_tile(geom, cbind(acc_sum[[j]], acc_valid[[j]]), tile_template, spec$method)
    acc_sum[j] <- list(NULL)
    acc_valid[j] <- list(NULL)
    col <- g$map[pid]
    has <- !is.na(col)
    pick <- function(base) {
      v <- rep(NA_real_, M)
      v[has] <- moved[cbind(rows[has], base + col[has])]
      v
    }
    denom <- rep(0, M)
    denom[has] <- g$denom[col[has]]
    res <- .wapor_finish_target(pick(0L), pick(w), denom, pid, min_coverage)
    rm(moved)
    if (!identical(g$target, "season")) res$coverage <- NULL
    out[[g$set]][[g$target]] <- res
  }
  out
}

# -----------------------------------------------------------------------------
# Window driver
# -----------------------------------------------------------------------------

#' Batches of dekad indices
#' @keywords internal
#' @noRd
.wapor_layer_batches <- function(n_layers, batch_size) {
  batch_size <- max(1L, as.integer(batch_size))
  split(seq_len(n_layers), ceiling(seq_len(n_layers) / batch_size))
}

#' Run every kernel source over one analysis-grid window
#'
#' @param job Kernel job from `.wapor_build_kernel_job()`.
#' @param tile_template SpatRaster: the analysis grid for this window.
#' @param batch_size Dekads read per batch.
#' @return Named list per output set of targets, each with `value` and
#'   `coverage` numeric vectors in the tile's cell order.
#' @keywords internal
#' @noRd
.wapor_kernel_window <- function(job, tile_template, batch_size, emit = NULL) {
  key_r <- terra::rast(job$key_path)
  key_tile <- terra::crop(key_r, tile_template, snap = "near")
  if (!isTRUE(terra::compareGeom(key_tile, tile_template, stopOnError = FALSE))) {
    key_tile <- terra::resample(key_tile, tile_template, method = "near")
  }
  pid <- match(as.numeric(terra::values(key_tile, mat = FALSE)), job$profiles$key)
  targets <- c(list(season = seq_len(nrow(job$dekad_table))), job$month_targets)
  batches <- .wapor_layer_batches(nrow(job$dekad_table), batch_size)

  out <- list()
  for (spec in job$specs) {
    if (identical(spec$path, "aligned")) {
      e <- terra::ext(tile_template)
      read_batch <- function(b) {
        # Grids are aligned, so snap to the nearest cell edge; floating-point
        # noise in the tile extent must not add a row or column.
        rb <- .wapor_read_native_batch(spec$paths[b], e, remote = spec$remote, snap = "near")
        if (!isTRUE(terra::compareGeom(rb$geom, tile_template, stopOnError = FALSE))) {
          stop("Aligned source window does not match the analysis window.", call. = FALSE)
        }
        rb$X
      }
      res <- .wapor_accumulate_pixelwise(read_batch, spec, pid, targets, batches, job$min_coverage)
    } else {
      native_r <- terra::rast(spec$paths[[1]], lyrs = 1L)
      e <- .wapor_native_window_ext(native_r, tile_template)
      if (is.null(e)) {
        stop(sprintf("Source %s does not overlap the analysis area.", spec$variable), call. = FALSE)
      }
      if (identical(spec$path, "native")) {
        # Read the first batch up front to learn the native window geometry;
        # the accumulator then receives it without a second read.
        first_batch <- .wapor_read_native_batch(spec$paths[batches[[1]]], e, remote = spec$remote)
        pending <- first_batch$X
        read_batch <- function(b) {
          if (!is.null(pending)) {
            x <- pending
            pending <<- NULL
            return(x)
          }
          .wapor_read_native_batch(spec$paths[b], e, remote = spec$remote)$X
        }
        res <- .wapor_accumulate_native(
          read_batch, first_batch$geom, spec, pid, targets, batches, tile_template, job$min_coverage
        )
      } else {
        read_batch <- function(b) {
          rb <- .wapor_read_native_batch(spec$paths[b], e, remote = spec$remote)
          .wapor_native_to_tile(rb$geom, rb$X, tile_template, spec$method)
        }
        res <- .wapor_accumulate_pixelwise(read_batch, spec, pid, targets, batches, job$min_coverage)
      }
    }
    if (is.function(emit)) {
      # Hand each output over as soon as its source is done, so the caller
      # can write it out instead of holding every output at once.
      for (sn in names(res)) {
        for (tg in names(res[[sn]])) emit(paste0(sn, "__", tg), res[[sn]][[tg]]$value)
        emit(paste0(sn, "__coverage"), res[[sn]]$season$coverage)
      }
      rm(res)
    } else {
      out[names(res)] <- res
    }
  }
  out
}

# -----------------------------------------------------------------------------
# Job construction
# -----------------------------------------------------------------------------

#' Build a kernel job for one season
#'
#' @param period Character c(start, end).
#' @param reference_year Integer.
#' @param template SpatRaster analysis grid (already cropped to the AOI).
#' @param h_mask,h_start,h_end SpatRasters on the analysis grid.
#' @param variables Named list: kernel spec name -> list(variable, paths,
#'   multipliers, method, kc = FALSE, remote).
#' @param crop_params data.frame (needed for Kc specs).
#' @param min_coverage Numeric in (0, 1].
#' @param work_dir Directory for small job files (profile keys).
#' @keywords internal
#' @noRd
.wapor_build_kernel_job <- function(period, reference_year, template, h_mask, h_start, h_end,
                                    variables, crop_params = NULL, min_coverage = 1,
                                    work_dir = tempfile("rwapor-job-")) {
  if (!is.numeric(min_coverage) || length(min_coverage) != 1L ||
      !is.finite(min_coverage) || min_coverage <= 0 || min_coverage > 1) {
    stop("'min_coverage' must be a single number in (0, 1].", call. = FALSE)
  }
  dir.create(work_dir, recursive = TRUE, showWarnings = FALSE)
  dekad_table <- build_dekad_table(period[1], period[2])
  key_r <- .wapor_profile_key_raster(h_mask, h_start, h_end, reference_year)
  key_path <- file.path(work_dir, "profile_keys.tif")
  terra::writeRaster(key_r, key_path, overwrite = TRUE, datatype = "FLT8S")
  profiles <- .wapor_profiles_from_keys(terra::rast(key_path))
  sw <- .wapor_profile_dekad_weights(profiles, dekad_table, reference_year)
  kc <- NULL
  max_profiles <- .wapor_max_season_profiles()

  specs <- list()
  for (nm in names(variables)) {
    v <- variables[[nm]]
    if (is.null(v$paths) || !length(v$paths)) next
    if (length(v$paths) != nrow(dekad_table)) {
      stop(sprintf("%s: expected %d dekad source(s), found %d.",
                   v$variable, nrow(dekad_table), length(v$paths)), call. = FALSE)
    }
    m <- as.numeric(v$multipliers %||% rep(1, nrow(dekad_table)))
    coef <- sweep(sw$weights, 2, m, "*")
    if (isTRUE(v$kc)) {
      if (is.null(kc)) kc <- .wapor_profile_kc(profiles, crop_params, dekad_table, reference_year)
      coef <- coef * kc
    }
    method <- v$method %||% "near"
    # Outputs from the same files and method share one read (e.g. RET and ETc).
    share <- Filter(function(sp) identical(sp$paths, as.character(v$paths)) &&
                      identical(sp$method, method), specs)
    if (length(share)) {
      specs[[names(share)[1]]]$sets[[nm]] <- list(coef = coef, days = sw$days)
      next
    }
    native_r <- terra::rast(v$paths[[1]], lyrs = 1L)
    path <- if (.wapor_grids_aligned(native_r, template)) {
      "aligned"
    } else if (nrow(profiles) <= max_profiles &&
               all(terra::res(native_r) >= terra::res(template) * (1 - 1e-6) |
                     !isTRUE(tryCatch(terra::same.crs(native_r, template), error = function(e) FALSE)))) {
      "native"
    } else {
      "per_dekad"
    }
    specs[[nm]] <- .wapor_kernel_spec(
      name = nm, variable = v$variable, paths = as.character(v$paths),
      sets = stats::setNames(list(list(coef = coef, days = sw$days)), nm),
      method = method, path = path, remote = isTRUE(v$remote)
    )
  }

  list(
    period = period,
    reference_year = reference_year,
    dekad_table = dekad_table,
    month_targets = .wapor_month_targets(dekad_table),
    profiles = profiles,
    key_path = key_path,
    specs = specs,
    min_coverage = min_coverage,
    work_dir = work_dir
  )
}

#' Output set names of a kernel job (one per variable, e.g. "ret", "etc")
#' @keywords internal
#' @noRd
.wapor_kernel_set_names <- function(job) {
  unlist(lapply(job$specs, function(sp) names(sp$sets)), use.names = FALSE)
}

#' Output layer names produced by a kernel job
#' @keywords internal
#' @noRd
.wapor_kernel_output_names <- function(job) {
  targets <- c("season", names(job$month_targets))
  unlist(lapply(.wapor_kernel_set_names(job), function(nm) {
    c(paste0(nm, "__", targets), paste0(nm, "__coverage"))
  }), use.names = FALSE)
}

#' Flatten one window result into named numeric columns
#' @keywords internal
#' @noRd
.wapor_flatten_window <- function(res) {
  cols <- list()
  for (nm in names(res)) {
    for (t in names(res[[nm]])) {
      cols[[paste0(nm, "__", t)]] <- res[[nm]][[t]]$value
    }
    cols[[paste0(nm, "__coverage")]] <- res[[nm]]$season$coverage
  }
  cols
}

# -----------------------------------------------------------------------------
# Runner: memory, stream and tiled modes
# -----------------------------------------------------------------------------

#' Per-worker memory settings under a parallel future plan
#' @keywords internal
#' @noRd
.wapor_worker_init <- function(n_workers = 1L) {
  n <- max(1L, as.integer(n_workers))
  if (n > 1L) {
    try(terra::terraOptions(memfrac = 0.6 / n), silent = TRUE)
    cachemax <- max(32L, as.integer(512L / n))
    vsi <- max(8e6, 1e8 / n)
    try(terra::setGDALconfig(c(
      sprintf("GDAL_CACHEMAX=%d", cachemax),
      sprintf("VSI_CACHE_SIZE=%.0f", vsi)
    )), silent = TRUE)
  }
  invisible(n)
}

#' Temporarily set the GDAL HTTP chunk size for one job
#' @keywords internal
#' @noRd
.wapor_with_gdal_chunk <- function(chunk_bytes, code) {
  old <- tryCatch(terra::getGDALconfig("CPL_VSIL_CURL_CHUNK_SIZE"), error = function(e) "")
  if (is.null(old) || !length(old) || is.na(old) || !nzchar(old)) {
    old <- Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE", unset = "")
  }
  try(terra::setGDALconfig("CPL_VSIL_CURL_CHUNK_SIZE", as.character(as.integer(chunk_bytes))), silent = TRUE)
  on.exit(try(terra::setGDALconfig("CPL_VSIL_CURL_CHUNK_SIZE", old), silent = TRUE), add = TRUE)
  force(code)
}

#' Run a kernel job in the planned mode and return one raster per output
#'
#' @param job Kernel job.
#' @param template SpatRaster analysis grid.
#' @param plan `wapor_plan`.
#' @param output_dir Directory for stream/tiled outputs (and tile assets).
#' @param cog Logical. Write tiles as COGs.
#' @param resume Logical. Reuse valid tiles recorded in `output_dir`.
#' @param manifest_extra List merged into the tiled run manifest.
#' @param progress_callback function(value, detail).
#' @return List with `rasters` (named list of single-layer SpatRasters),
#'   `n_tiles`, `n_tiles_resumed`, `n_tiles_written`, `manifest_path`.
#' @keywords internal
#' @noRd
.wapor_run_kernel <- function(job, template, plan, output_dir = NULL, cog = FALSE,
                              resume = FALSE, manifest_extra = list(),
                              progress_callback = function(v, d) NULL) {
  template <- template[[1]]
  out_names <- .wapor_kernel_output_names(job)

  make_raster <- function(tmpl, cols, nm) {
    r <- terra::rast(tmpl)
    terra::values(r) <- cols[[nm]]
    names(r) <- nm
    r
  }

  if (!identical(plan$mode, "tiled")) {
    progress_callback(0.5, sprintf("Aggregating dekads (%s mode, %d per batch)...", plan$mode, plan$batch_size))
    rasters <- list()
    if (identical(plan$mode, "stream")) {
      dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    }
    # Stream mode writes each output to disk as it arrives; memory mode keeps it.
    emit <- function(nm, vec) {
      r <- make_raster(template, stats::setNames(list(vec), nm), nm)
      if (identical(plan$mode, "stream")) {
        p <- file.path(output_dir, paste0(nm, ".tif"))
        terra::writeRaster(r, p, overwrite = TRUE, datatype = "FLT8S")
        r <- terra::rast(p)
      }
      rasters[[nm]] <<- r
    }
    .wapor_with_gdal_chunk(
      plan$gdal_chunk_bytes,
      .wapor_kernel_window(job, template, plan$batch_size, emit = emit)
    )
    return(list(rasters = rasters[intersect(out_names, names(rasters))], n_tiles = 1L, n_tiles_resumed = 0L,
                n_tiles_written = 1L, manifest_path = NULL))
  }

  # --- tiled -----------------------------------------------------------------
  tile_size <- plan$tile_size
  if (is.na(tile_size)) tile_size <- 512L
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  tiles_dir <- file.path(output_dir, "tiles")
  dir.create(tiles_dir, recursive = TRUE, showWarnings = FALSE)
  manifest_path <- file.path(output_dir, "run_manifest.json")
  windows <- .wapor_tiled_windows(terra::nrow(template), terra::ncol(template), tile_size)
  grid <- .wapor_grid_signature(template)
  config_hash <- manifest_extra$config_hash %||% digest::digest(
    list(
      period = job$period,
      reference_year = job$reference_year,
      min_coverage = job$min_coverage,
      profiles = job$profiles$key,
      specs = lapply(job$specs, function(s) {
        list(s$variable, basename(s$paths), s$method, lapply(s$sets, `[[`, "coef"))
      }),
      tile_size = as.integer(tile_size),
      grid = grid
    ),
    algo = "sha256"
  )

  existing_by_id <- list()
  if (isTRUE(resume) && file.exists(manifest_path)) {
    existing <- .wapor_read_run_manifest(manifest_path)
    if (!identical(existing$config_hash %||% NA_character_, config_hash)) {
      stop("Existing tiled run manifest does not match this configuration; refuse to resume.",
           call. = FALSE)
    }
    for (tile in existing$tiles) {
      if (!is.null(tile$id)) existing_by_id[[tile$id]] <- tile
    }
  }

  write_tile <- function(r, path) {
    # Doubles keep tiled results identical to memory mode.
    if (isTRUE(cog)) {
      wapor_write_cog(r, path, overwrite = TRUE, datatype = "FLT8S")
    } else {
      terra::writeRaster(r, path, overwrite = TRUE, datatype = "FLT8S")
    }
    path
  }

  run_tile <- function(win) {
    tile_template <- .wapor_window_template(grid, win)
    res <- .wapor_kernel_window(job, tile_template, plan$batch_size)
    cols <- .wapor_flatten_window(res)
    outputs <- list()
    checksums <- list()
    for (nm in out_names) {
      p <- file.path(tiles_dir, sprintf("%s_%s.tif", win$id, .wapor_tile_output_label(nm)))
      write_tile(make_raster(tile_template, cols, nm), p)
      outputs[[.wapor_tile_output_label(nm)]] <- p
      checksums[[.wapor_tile_output_label(nm)]] <- .wapor_file_sha256(p)
    }
    list(
      id = win$id, row = win$row, col = win$col, nrows = win$nrows, ncols = win$ncols,
      status = "complete", outputs = outputs, checksums = checksums,
      sources = lapply(job$specs, function(s) list(variable = s$variable, path = s$path)),
      reducer = "block", used_full_engine = FALSE
    )
  }

  is_done <- vapply(windows, function(win) {
    prev <- existing_by_id[[win$id]]
    if (!isTRUE(resume) || is.null(prev)) return(FALSE)
    .wapor_tile_is_complete(prev, .wapor_window_template(grid, win))
  }, logical(1))

  todo <- which(!is_done)
  n_workers <- plan$workers
  records <- vector("list", length(windows))
  records[is_done] <- lapply(windows[is_done], function(win) existing_by_id[[win$id]])

  run_one <- function(i) {
    .wapor_worker_init(n_workers)
    rec <- .wapor_with_gdal_chunk(plan$gdal_chunk_bytes, run_tile(windows[[i]]))
    # Return the finished tile's working memory before the next tile starts.
    invisible(gc(verbose = FALSE))
    rec
  }
  if (length(todo)) {
    if (n_workers > 1L && length(todo) > 1L) {
      progress_callback(0.5, sprintf("Processing %d tile(s) on %d worker(s)...", length(todo), n_workers))
      records[todo] <- future.apply::future_lapply(todo, run_one, future.seed = TRUE)
    } else {
      for (k in seq_along(todo)) {
        i <- todo[k]
        win <- windows[[i]]
        progress_callback(k / length(todo), sprintf(
          "Tile %d / %d (%s rows %d-%d cols %d-%d)...", k, length(todo), win$id,
          win$row, win$row + win$nrows - 1L, win$col, win$col + win$ncols - 1L
        ))
        records[[i]] <- run_one(i)
      }
    }
  }

  rasters <- list()
  for (nm in out_names) {
    label <- .wapor_tile_output_label(nm)
    paths <- vapply(records, function(t) t$outputs[[label]] %||% NA_character_, character(1))
    vrt <- .wapor_assemble_vrt(paths[!is.na(paths)], file.path(output_dir, paste0(label, ".vrt")))
    if (!is.null(vrt)) {
      r <- terra::rast(vrt)
      names(r) <- nm
      rasters[[nm]] <- r
    }
  }

  manifest <- c(list(
    manifest_version = 1L,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    config_hash = config_hash,
    grid = grid,
    tile_size = as.integer(tile_size),
    cog = isTRUE(cog),
    versions = .wapor_runtime_versions(),
    processing = list(mode = plan$mode, batch_size = plan$batch_size, workers = plan$workers),
    coverage = list(
      n_tiles = length(windows),
      n_complete = sum(vapply(records, function(t) identical(t$status, "complete"), logical(1))),
      n_resumed = sum(is_done),
      n_written = length(todo),
      complete = all(vapply(records, function(t) identical(t$status, "complete"), logical(1)))
    ),
    tiles = records
  ), manifest_extra[setdiff(names(manifest_extra), "config_hash")])
  .wapor_write_run_manifest(manifest_path, manifest)
  if (!isTRUE(manifest$coverage$complete)) {
    stop("Tiled analysis is incomplete; one or more tiles failed validation.", call. = FALSE)
  }

  list(rasters = rasters, n_tiles = length(windows), n_tiles_resumed = sum(is_done),
       n_tiles_written = length(todo), manifest_path = manifest_path)
}

#' Geometry-only raster for one row/col window of a grid signature
#'
#' Built arithmetically so tiles never need the full-area raster and parallel
#' workers receive only plain numbers.
#' @keywords internal
#' @noRd
.wapor_window_template <- function(grid, win) {
  xmin <- grid$xmin + (win$col - 1L) * grid$resx
  ymax <- grid$ymax - (win$row - 1L) * grid$resy
  terra::rast(
    nrows = win$nrows, ncols = win$ncols,
    xmin = xmin, xmax = xmin + win$ncols * grid$resx,
    ymin = ymax - win$nrows * grid$resy, ymax = ymax,
    crs = grid$crs
  )
}

#' Stable file label for a kernel output (manifest and tile file names)
#' @keywords internal
#' @noRd
.wapor_tile_output_label <- function(nm) {
  if (identical(nm, "aeti__season")) return("seasonal_aeti")
  gsub("[^A-Za-z0-9_-]", "_", nm)
}
