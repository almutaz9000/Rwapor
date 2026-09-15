# R/analysis_tiled.R
# =============================================================================
# Out-of-Core Tiled / Windowed Seasonal Analysis Engine
# =============================================================================

.wapor_tiled_row_windows <- function(nrow, tile_size) {
  tile_size <- max(1L, as.integer(tile_size))
  starts <- seq(1L, as.integer(nrow), by = tile_size)
  lapply(starts, function(r0) {
    list(row = r0, nrows = min(tile_size, as.integer(nrow) - r0 + 1L))
  })
}

.wapor_tiled_windows <- function(nrow, ncol, tile_size) {
  tile_size <- max(1L, as.integer(tile_size))
  nrow <- as.integer(nrow)
  ncol <- as.integer(ncol)
  row_starts <- seq(1L, nrow, by = tile_size)
  col_starts <- seq(1L, ncol, by = tile_size)
  tiles <- vector("list", length(row_starts) * length(col_starts))
  k <- 1L
  for (r0 in row_starts) {
    nrows <- min(tile_size, nrow - r0 + 1L)
    for (c0 in col_starts) {
      ncols <- min(tile_size, ncol - c0 + 1L)
      tiles[[k]] <- list(
        id = sprintf("r%04dc%04d", r0, c0),
        row = as.integer(r0),
        col = as.integer(c0),
        nrows = as.integer(nrows),
        ncols = as.integer(ncols)
      )
      k <- k + 1L
    }
  }
  tiles
}

.wapor_note_tiled_cells <- function(n) {
  n <- as.numeric(n)
  if (!is.finite(n) || n <= 0) {
    return(invisible(n))
  }
  current <- getOption("Rwapor.tiled_max_cells", 0)
  options(Rwapor.tiled_max_cells = max(current, n))
  invisible(n)
}

.wapor_crop_raster_window <- function(r, win) {
  if (is.null(r) || !inherits(r, "SpatRaster")) {
    return(r)
  }
  r0 <- as.integer(win$row)
  r1 <- r0 + as.integer(win$nrows) - 1L
  c0 <- as.integer(win$col)
  c1 <- c0 + as.integer(win$ncols) - 1L
  nr <- as.integer(terra::nrow(r))
  nc <- as.integer(terra::ncol(r))
  if (r0 == 1L && c0 == 1L && r1 == nr && c1 == nc) {
    .wapor_note_tiled_cells(as.numeric(nr) * as.numeric(nc))
    return(r)
  }
  if (r0 < 1L || c0 < 1L || r1 > nr || c1 > nc) {
    if (nr <= as.integer(win$nrows) && nc <= as.integer(win$ncols)) {
      .wapor_note_tiled_cells(as.numeric(nr) * as.numeric(nc))
      return(r)
    }
    stop("Tile window is outside the raster grid.", call. = FALSE)
  }
  out <- r[r0:r1, c0:c1, drop = FALSE]
  .wapor_note_tiled_cells(as.numeric(terra::ncell(out)))
  out
}

.wapor_grid_signature <- function(template) {
  e <- terra::ext(template)
  list(
    crs = terra::crs(template),
    nrow = as.integer(terra::nrow(template)),
    ncol = as.integer(terra::ncol(template)),
    xmin = as.numeric(e$xmin),
    xmax = as.numeric(e$xmax),
    ymin = as.numeric(e$ymin),
    ymax = as.numeric(e$ymax),
    resx = as.numeric(terra::xres(template)),
    resy = as.numeric(terra::yres(template))
  )
}

.wapor_tiled_config_hash <- function(config, tile_size, grid) {
  digest::digest(
    list(
      period = config$period,
      indicators = config$indicators,
      aeti_var = config$aeti_var,
      ret_var = config$ret_var,
      precip_var = config$precip_var,
      npp_var = config$npp_var,
      t_var = config$t_var,
      data_source = config$data_source,
      folder = config$folder,
      reference_layer = config$reference_layer %||% "aeti",
      tile_size = as.integer(tile_size),
      grid = grid
    ),
    algo = "sha256"
  )
}

.wapor_file_sha256 <- function(path) {
  digest::digest(file = path, algo = "sha256")
}

.wapor_validate_tile_asset <- function(path, expected = NULL) {
  if (!is.character(path) || length(path) != 1L || !nzchar(path) || !file.exists(path)) {
    return(FALSE)
  }
  got <- tryCatch(terra::rast(path), error = function(e) NULL)
  if (is.null(got) || !inherits(got, "SpatRaster")) {
    return(FALSE)
  }
  if (is.null(expected)) {
    return(TRUE)
  }
  isTRUE(terra::compareGeom(
    got,
    expected,
    stopOnError = FALSE,
    crs = TRUE,
    res = TRUE,
    ext = TRUE,
    rowcol = TRUE
  ))
}

.wapor_runtime_versions <- function() {
  gdal_ver <- tryCatch(as.character(terra::gdal()), error = function(e) NA_character_)
  list(
    package = as.character(utils::packageVersion("Rwapor")),
    terra = as.character(utils::packageVersion("terra")),
    gdal = gdal_ver[[1]]
  )
}

.wapor_tile_bbox <- function(template, win) {
  tile <- .wapor_crop_raster_window(template, win)
  e <- terra::ext(tile)
  c(
    as.numeric(e$xmin),
    as.numeric(e$ymin),
    as.numeric(e$xmax),
    as.numeric(e$ymax)
  )
}

.wapor_requested_variables <- function(config) {
  vars <- c(config$aeti_var, config$ret_var, config$precip_var, config$npp_var, config$t_var)
  vars <- vars[!vapply(vars, function(v) is.null(v) || !nzchar(v), logical(1))]
  unique(as.character(vars))
}

.wapor_resolve_source_paths <- function(config, var) {
  if (is.null(var) || !nzchar(var)) {
    return(character(0))
  }
  if (!is.null(config$source_urls) && !is.null(config$source_urls[[var]])) {
    return(as.character(config$source_urls[[var]]))
  }
  if (identical(config$data_source, "local")) {
    wapor_local_rasters(config$folder, var, config$period[1], config$period[2])
  } else {
    urls <- Rwapor::wapor_generate_urls(var, l3_region = config$l3_code, period = config$period)
    if (!length(urls)) {
      return(character(0))
    }
    paste0("/vsicurl/", urls)
  }
}

.wapor_window_source_rasters <- function(config, win, template, dest_dir) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  tile_template <- .wapor_crop_raster_window(template, win)
  sources <- list()
  for (var in .wapor_requested_variables(config)) {
    paths <- .wapor_resolve_source_paths(config, var)
    if (!length(paths)) {
      next
    }
    var_dir <- file.path(dest_dir, var)
    dir.create(var_dir, recursive = TRUE, showWarnings = FALSE)
    written <- character(0)
    for (p in paths) {
      layer <- terra::rast(p)
      if (terra::nlyr(layer) > 1L) {
        layer <- layer[[1]]
      }
      cropped <- tryCatch(
        .wapor_crop_raster_window(layer, win),
        error = function(e) terra::crop(layer, tile_template, snap = "out")
      )
      if (!isTRUE(terra::compareGeom(cropped, tile_template, stopOnError = FALSE))) {
        cropped <- terra::resample(cropped, tile_template, method = "near")
      }
      out_path <- file.path(var_dir, basename(p))
      if (!grepl("\\.tif$", out_path, ignore.case = TRUE)) {
        out_path <- paste0(out_path, ".tif")
      }
      terra::writeRaster(cropped, out_path, overwrite = TRUE)
      written <- c(written, out_path)
    }
    sources[[var]] <- written
  }
  list(folder = dest_dir, sources = sources)
}

.wapor_temporal_weighted_sum_window <- function(paths, template, win, weights, multipliers) {
  if (!length(paths)) {
    stop("'paths' must contain at least one raster", call. = FALSE)
  }
  if (length(weights) != length(paths) || length(multipliers) != length(paths)) {
    stop("weights and multipliers must match the number of paths", call. = FALSE)
  }
  tile_template <- .wapor_crop_raster_window(template, win)
  total <- NULL
  for (i in seq_along(paths)) {
    layer <- terra::rast(paths[[i]])
    if (terra::nlyr(layer) > 1L) {
      layer <- layer[[1]]
    }
    layer <- .wapor_crop_raster_window(layer, win)
    if (!isTRUE(terra::compareGeom(layer, tile_template, stopOnError = FALSE))) {
      layer <- terra::resample(layer, tile_template, method = "near")
    }
    contrib <- layer * (weights[[i]] * multipliers[[i]])
    total <- if (is.null(total)) contrib else total + contrib
  }
  total
}

.wapor_write_run_manifest <- function(path, manifest) {
  jsonlite::write_json(manifest, path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  path
}

.wapor_read_run_manifest <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

.wapor_assemble_vrt <- function(paths, vrt_path) {
  paths <- paths[file.exists(paths)]
  if (!length(paths)) {
    return(NULL)
  }
  dir.create(dirname(vrt_path), recursive = TRUE, showWarnings = FALSE)
  terra::vrt(unname(paths), filename = vrt_path, overwrite = TRUE)
  vrt_path
}

.wapor_ymd_from_name <- function(nm) {
  m <- regmatches(nm, regexpr("\\d{4}-\\d{2}-\\d{2}", nm))
  if (length(m)) return(m)
  m <- regmatches(nm, regexpr("(?<![0-9])\\d{12}(?![0-9])", nm, perl = TRUE))
  if (length(m)) {
    return(paste(substr(m, 1, 4), substr(m, 5, 6), substr(m, 7, 8), sep = "-"))
  }
  m <- regmatches(nm, regexpr("(?<![0-9])\\d{8}(?![0-9])", nm, perl = TRUE))
  if (length(m)) {
    return(paste(substr(m, 1, 4), substr(m, 5, 6), substr(m, 7, 8), sep = "-"))
  }
  NA_character_
}

.wapor_align_paths_to_dekads <- function(paths, dekad_keys) {
  labels <- vapply(paths, function(p) .wapor_ymd_from_name(basename(p)), character(1), USE.NAMES = FALSE)
  idx <- match(as.character(dekad_keys), labels)
  if (any(is.na(idx))) {
    stop("Missing data for some dekads in the analysis period.", call. = FALSE)
  }
  paths[idx]
}

.wapor_read_window_layer <- function(path, win, tile_template) {
  layer <- terra::rast(path)
  if (terra::nlyr(layer) > 1L) {
    layer <- layer[[1]]
  }
  cropped <- tryCatch(
    .wapor_crop_raster_window(layer, win),
    error = function(e) terra::crop(layer, tile_template, snap = "out")
  )
  if (!isTRUE(terra::compareGeom(cropped, tile_template, stopOnError = FALSE))) {
    cropped <- terra::resample(cropped, tile_template, method = "near")
  }
  cropped
}

.wapor_weighted_sum_from_paths <- function(paths, win, tile_template, weight_layers, multipliers) {
  total <- NULL
  for (i in seq_along(paths)) {
    layer <- .wapor_read_window_layer(paths[[i]], win, tile_template)
    contrib <- layer * (weight_layers[[i]] * multipliers[[i]])
    total <- if (is.null(total)) contrib else total + contrib
  }
  total
}

.wapor_reduce_tile_indicators <- function(config, crop_params, rasters, win, template) {
  indicators <- wapor_normalize_analysis_indicators(config$indicators)
  tile_template <- .wapor_crop_raster_window(template, win)
  h_mask <- if (isTRUE(config$use_crop_mask) && inherits(rasters$crop_mask, "SpatRaster")) {
    wapor_harmonize_crop_mask(.wapor_crop_raster_window(rasters$crop_mask, win), tile_template)
  } else {
    tile_template * 0 + 1L
  }
  ref_year <- config$ref_year %||% as.integer(format(as.Date(config$period[1]), "%Y"))
  h_start <- if (isTRUE(config$use_season_rasters) && inherits(rasters$season_start, "SpatRaster")) {
    Rwapor::wapor_harmonize_raster(.wapor_crop_raster_window(rasters$season_start, win), tile_template, method = "near")
  } else {
    tile_template * 0 + Rwapor::wapor_continuous_julian(config$period[1], ref_year)
  }
  h_end <- if (isTRUE(config$use_season_rasters) && inherits(rasters$season_end, "SpatRaster")) {
    Rwapor::wapor_harmonize_raster(.wapor_crop_raster_window(rasters$season_end, win), tile_template, method = "near")
  } else {
    tile_template * 0 + Rwapor::wapor_continuous_julian(config$period[2], ref_year)
  }

  sw <- Rwapor::wapor_build_season_weights(config$period[1], config$period[2], h_start, h_end, ref_year)
  dekad_table <- sw$dekad_table
  weight_layers <- lapply(seq_len(terra::nlyr(sw$weights)), function(i) sw$weights[[i]])
  valid_mask <- terra::ifel(is.na(h_mask), NA, 1L)

  aeti_paths <- if (!is.null(config$aeti_var) && nzchar(config$aeti_var)) {
    .wapor_align_paths_to_dekads(.wapor_resolve_source_paths(config, config$aeti_var), dekad_table$dekad_key)
  } else {
    character(0)
  }
  ret_paths <- if (!is.null(config$ret_var) && nzchar(config$ret_var)) {
    .wapor_align_paths_to_dekads(.wapor_resolve_source_paths(config, config$ret_var), dekad_table$dekad_key)
  } else {
    character(0)
  }
  precip_paths <- if (!is.null(config$precip_var) && nzchar(config$precip_var)) {
    .wapor_align_paths_to_dekads(.wapor_resolve_source_paths(config, config$precip_var), dekad_table$dekad_key)
  } else {
    character(0)
  }
  npp_paths <- if (!is.null(config$npp_var) && nzchar(config$npp_var)) {
    .wapor_align_paths_to_dekads(.wapor_resolve_source_paths(config, config$npp_var), dekad_table$dekad_key)
  } else {
    character(0)
  }
  t_paths <- if (!is.null(config$t_var) && nzchar(config$t_var)) {
    .wapor_align_paths_to_dekads(.wapor_resolve_source_paths(config, config$t_var), dekad_table$dekad_key)
  } else {
    character(0)
  }

  aeti_mult <- if (length(aeti_paths)) get_analysis_layer_multipliers(config$aeti_var, dekad_table) else NULL
  ret_mult <- if (length(ret_paths)) get_analysis_layer_multipliers(config$ret_var, dekad_table) else NULL
  precip_mult <- if (length(precip_paths)) get_analysis_layer_multipliers(config$precip_var, dekad_table) else NULL
  npp_mult <- if (length(npp_paths)) get_analysis_layer_multipliers(config$npp_var, dekad_table) else NULL
  t_mult <- if (length(t_paths)) get_analysis_layer_multipliers(config$t_var, dekad_table) else NULL

  seasonal_aeti <- if (length(aeti_paths)) {
    terra::mask(.wapor_weighted_sum_from_paths(aeti_paths, win, tile_template, weight_layers, aeti_mult), valid_mask)
  } else {
    NULL
  }
  seasonal_ret <- if (length(ret_paths)) {
    terra::mask(.wapor_weighted_sum_from_paths(ret_paths, win, tile_template, weight_layers, ret_mult), valid_mask)
  } else {
    NULL
  }
  seasonal_pcp <- if (length(precip_paths) && any(c("agg_pcp", "agg_peff", "green_water", "blue_water") %in% indicators)) {
    terra::mask(.wapor_weighted_sum_from_paths(precip_paths, win, tile_template, weight_layers, precip_mult), valid_mask)
  } else {
    NULL
  }
  seasonal_t <- if (length(t_paths) && any(c("agg_t", "beneficial_fraction") %in% indicators)) {
    terra::mask(.wapor_weighted_sum_from_paths(t_paths, win, tile_template, weight_layers, t_mult), valid_mask)
  } else {
    NULL
  }
  seasonal_biomass <- if (length(npp_paths) && any(c("agg_biomass_kg", "agg_biomass_t", "yield_npp", "cwp_bwp") %in% indicators)) {
    terra::mask(
      .wapor_weighted_sum_from_paths(npp_paths, win, tile_template, weight_layers, npp_mult) * 22.222 / 1000,
      valid_mask
    )
  } else {
    NULL
  }

  layer_dates <- if ("dekad_start" %in% names(dekad_table)) as.Date(dekad_table$dekad_start) else as.Date(dekad_table$dekad_key)
  month_keys <- format(layer_dates, "%Y-%m")
  month_order <- unique(month_keys)
  seasonal_peff <- NULL
  if (length(precip_paths) && any(c("agg_peff", "green_water", "blue_water") %in% indicators)) {
    monthly_peff <- list()
    for (month_key in month_order) {
      idx <- which(month_keys == month_key)
      monthly_pcp <- .wapor_weighted_sum_from_paths(
        precip_paths[idx], win, tile_template, weight_layers[idx], precip_mult[idx]
      )
      monthly_peff[[month_key]] <- terra::ifel(
        monthly_pcp <= 250,
        monthly_pcp * (125 - 0.2 * monthly_pcp) / 125,
        125 + 0.1 * monthly_pcp
      )
    }
    seasonal_peff <- monthly_peff[[1]]
    if (length(monthly_peff) > 1L) {
      for (i in seq_along(monthly_peff)[-1]) {
        seasonal_peff <- seasonal_peff + monthly_peff[[i]]
      }
    }
    seasonal_peff <- terra::mask(seasonal_peff, valid_mask)
  }

  etc_seasonal <- NULL
  if (any(c("etc", "adequacy_etc") %in% indicators)) {
    if (!length(ret_paths)) {
      stop("RET stack is required for ETc/Adequacy.", call. = FALSE)
    }
    profile_table <- wapor_build_season_profile_table(h_mask, h_start, h_end, crop_params$class_value)
    if (nrow(profile_table) > 0) {
      kc_profiles <- list()
      profile_table$kc_key <- NA_character_
      for (i in seq_len(nrow(profile_table))) {
        profile_row <- profile_table[i, ]
        cp <- crop_params[crop_params$class_value == profile_row$class_value, , drop = FALSE]
        if (nrow(cp) == 0) next
        fixed_sum <- cp$l_ini_days + cp$l_mid_days + cp$l_late_days
        l_dev <- as.integer(profile_row$total_days - fixed_sum)
        if (l_dev < 0L) l_dev <- 0L
        kc_daily <- Rwapor::wapor_build_kc(
          kc_ini = cp$kc_ini[1], kc_mid = cp$kc_mid[1], kc_end = cp$kc_end[1],
          l_ini = cp$l_ini_days[1], l_dev = l_dev, l_mid = cp$l_mid_days[1], l_late = cp$l_late_days[1]
        )
        season_start_date <- as.Date(sprintf("%04d-01-01", ref_year)) + profile_row$start_jd - 1L
        kc_dekad <- Rwapor::wapor_aggregate_kc(kc_daily, dekad_table, season_start_date)
        kc_key <- paste(round(kc_dekad, 6), collapse = ",")
        profile_table$kc_key[i] <- kc_key
        if (is.null(kc_profiles[[kc_key]])) kc_profiles[[kc_key]] <- kc_dekad
      }
      unique_etc <- list()
      for (key in names(kc_profiles)) {
        unique_etc[[key]] <- .wapor_weighted_sum_from_paths(
          ret_paths, win, tile_template, weight_layers, ret_mult * kc_profiles[[key]]
        )
      }
      for (i in seq_len(nrow(profile_table))) {
        key <- profile_table$kc_key[i]
        if (is.na(key) || is.null(unique_etc[[key]])) next
        profile_mask <- terra::ifel(
          (h_mask == profile_table$class_value[i]) &
            (h_start == profile_table$start_jd[i]) &
            (h_end == profile_table$end_jd[i]),
          1L,
          NA
        )
        profile_etc <- unique_etc[[key]] * profile_mask
        etc_seasonal <- if (is.null(etc_seasonal)) profile_etc else terra::cover(etc_seasonal, profile_etc)
      }
      if (!is.null(etc_seasonal)) {
        etc_seasonal <- terra::mask(etc_seasonal, valid_mask)
      }
    }
  }

  adequacy_etc <- if ("adequacy_etc" %in% indicators && !is.null(seasonal_aeti) && !is.null(etc_seasonal)) {
    terra::mask(Rwapor::wapor_calc_adequacy_etc(seasonal_aeti, etc_seasonal), valid_mask)
  } else {
    NULL
  }
  green_water <- if ("green_water" %in% indicators && !is.null(seasonal_aeti) && !is.null(seasonal_peff)) {
    terra::mask(Rwapor::wapor_calc_green_water(seasonal_aeti, seasonal_peff), valid_mask)
  } else {
    NULL
  }
  blue_water <- if ("blue_water" %in% indicators && !is.null(seasonal_aeti) && !is.null(seasonal_peff)) {
    terra::mask(Rwapor::wapor_calc_blue_water(seasonal_aeti, seasonal_peff), valid_mask)
  } else {
    NULL
  }
  beneficial_fraction <- if ("beneficial_fraction" %in% indicators && !is.null(seasonal_aeti) && !is.null(seasonal_t)) {
    terra::mask(Rwapor::wapor_calc_beneficial_fraction(seasonal_t, seasonal_aeti), valid_mask)
  } else {
    NULL
  }

  list(
    seasonal_aeti = seasonal_aeti,
    seasonal_ret = seasonal_ret,
    seasonal_pcp = seasonal_pcp,
    seasonal_t = seasonal_t,
    seasonal_peff = seasonal_peff,
    seasonal_biomass = seasonal_biomass,
    etc_seasonal = etc_seasonal,
    adequacy_etc = adequacy_etc,
    green_water = green_water,
    blue_water = blue_water,
    beneficial_fraction = beneficial_fraction,
    used_full_engine = FALSE,
    reducer = "block"
  )
}

.wapor_remote_cog_fixture <- function(nrow = 128L, ncol = 128L) {
  src_dir <- tempfile("rwapor-cog-src-")
  dir.create(src_dir, recursive = TRUE)
  template <- terra::rast(
    nrows = nrow, ncols = ncol, xmin = 0, xmax = ncol, ymin = 0, ymax = nrow,
    crs = "EPSG:4326", vals = seq_len(nrow * ncol)
  )
  path <- file.path(src_dir, "WAPOR-3.L1-AETI-D.2023-01-01.tif")
  wapor_write_cog(template, path, overwrite = TRUE)
  old_chunk <- Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE", unset = NA_character_)
  Sys.setenv(CPL_VSIL_CURL_CHUNK_SIZE = "4096")
  Sys.setenv(GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")
  log_path <- file.path(src_dir, "http.log")
  py <- file.path(src_dir, "serve.py")
  writeLines(c(
    "import http.server, socketserver, os, json, sys",
    "root = os.path.dirname(os.path.abspath(__file__))",
    "os.chdir(root)",
    "log_path = os.path.join(root, 'http.log')",
    "class H(http.server.SimpleHTTPRequestHandler):",
    "    protocol_version = 'HTTP/1.1'",
    "    def do_GET(self):",
    "        path = self.translate_path(self.path)",
    "        if not os.path.isfile(path):",
    "            self.send_error(404); return",
    "        size = os.path.getsize(path)",
    "        rng = self.headers.get('Range')",
    "        with open(path, 'rb') as f:",
    "            if rng and rng.startswith('bytes='):",
    "                spec = rng.split('=',1)[1]",
    "                start_s, end_s = (spec.split('-') + [''])[:2]",
    "                start = int(start_s or 0)",
    "                end = int(end_s) if end_s else size-1",
    "                end = min(end, size-1)",
    "                length = end-start+1",
    "                f.seek(start)",
    "                data = f.read(length)",
    "                self.send_response(206)",
    "                self.send_header('Content-Type','image/tiff')",
    "                self.send_header('Accept-Ranges','bytes')",
    "                self.send_header('Content-Range', f'bytes {start}-{end}/{size}')",
    "                self.send_header('Content-Length', str(length))",
    "                self.end_headers(); self.wfile.write(data)",
    "                rec = {'bytes': length, 'requests': 1, 'range': True}",
    "            else:",
    "                data = f.read()",
    "                self.send_response(200)",
    "                self.send_header('Content-Type','image/tiff')",
    "                self.send_header('Accept-Ranges','bytes')",
    "                self.send_header('Content-Length', str(size))",
    "                self.end_headers(); self.wfile.write(data)",
    "                rec = {'bytes': size, 'requests': 1, 'range': False}",
    "        with open(log_path,'a') as lf: lf.write(json.dumps(rec)+'\\n')",
    "    def log_message(self, *args): pass",
    "class Reuse(socketserver.TCPServer): allow_reuse_address = True",
    "httpd = Reuse(('127.0.0.1', 0), H)",
    "open(os.path.join(root,'port.txt'),'w').write(str(httpd.server_address[1]))",
    "open(os.path.join(root,'pid.txt'),'w').write(str(os.getpid()))",
    "httpd.serve_forever()"
  ), py)
  py_bin <- Sys.which("python")
  if (!nzchar(py_bin)) py_bin <- Sys.which("python3")
  if (!nzchar(py_bin)) {
    stop("Python is required for the remote COG fixture.", call. = FALSE)
  }
  port_file <- file.path(src_dir, "port.txt")
  pid_file <- file.path(src_dir, "pid.txt")
  system2(py_bin, shQuote(py), wait = FALSE, stdout = FALSE, stderr = FALSE)
  deadline <- Sys.time() + 8
  while (!file.exists(port_file) && Sys.time() < deadline) {
    Sys.sleep(0.1)
  }
  if (!file.exists(port_file)) {
    stop("Failed to start remote COG fixture server.", call. = FALSE)
  }
  port <- as.integer(readLines(port_file, warn = FALSE)[[1]])
  pid <- if (file.exists(pid_file)) as.integer(readLines(pid_file, warn = FALSE)[[1]]) else NA_integer_
  url <- sprintf("/vsicurl/http://127.0.0.1:%d/%s", port, basename(path))
  list(
    template = template,
    variable = "L1-AETI-D",
    urls = url,
    full_file_bytes = as.integer(file.info(path)$size),
    config = list(
      period = c("2023-01-01", "2023-01-10"),
      aeti_var = "L1-AETI-D",
      data_source = "remote",
      folder = src_dir,
      source_urls = list(`L1-AETI-D` = url)
    ),
    http_stats = function() {
      if (!file.exists(log_path)) return(list(bytes = 0L, requests = 0L, range_requests = 0L))
      rows <- jsonlite::stream_in(file(log_path), verbose = FALSE)
      list(
        bytes = sum(rows$bytes),
        requests = sum(rows$requests),
        range_requests = sum(isTRUE(rows$range) | rows$range == TRUE)
      )
    },
    cleanup = function() {
      if (!is.na(pid)) {
        try(tools::pskill(pid), silent = TRUE)
      }
      if (is.na(old_chunk)) {
        Sys.unsetenv("CPL_VSIL_CURL_CHUNK_SIZE")
      } else {
        Sys.setenv(CPL_VSIL_CURL_CHUNK_SIZE = old_chunk)
      }
      unlink(src_dir, recursive = TRUE, force = TRUE)
    }
  )
}

.wapor_tiled_memory_benchmark <- function(nrow = 16L, ncol = 16L, tile_size = 4L, n_layers = 3L) {
  analysis_dir <- tempfile("rwapor-mem-src-")
  out_dir <- tempfile("rwapor-mem-out-")
  dir.create(analysis_dir, recursive = TRUE)
  dir.create(out_dir, recursive = TRUE)
  on.exit(unlink(c(analysis_dir, out_dir), recursive = TRUE, force = TRUE), add = TRUE)

  template <- terra::rast(
    nrows = nrow, ncols = ncol, xmin = 0, xmax = ncol, ymin = 0, ymax = nrow,
    crs = "EPSG:4326", vals = 1
  )
  crop_mask <- terra::setValues(template, 1L)
  season_start <- terra::setValues(template, 1L)
  season_end <- terra::setValues(template, 31L)
  dates <- as.character(as.Date("2023-01-01") + c(0, 10, 20)[seq_len(n_layers)])
  var_dir <- file.path(analysis_dir, "L1-AETI-D")
  dir.create(var_dir, recursive = TRUE)
  for (i in seq_along(dates)) {
    r <- terra::setValues(template, i)
    terra::writeRaster(r, file.path(var_dir, sprintf("WAPOR-3.L1-AETI-D.%s.tif", dates[i])), overwrite = TRUE)
  }
  config <- list(
    period = c("2023-01-01", "2023-01-31"),
    ref_year = 2023,
    aeti_var = "L1-AETI-D",
    ret_var = NULL,
    precip_var = NULL,
    npp_var = NULL,
    t_var = NULL,
    data_source = "local",
    folder = analysis_dir,
    indicators = "agg_aeti",
    use_crop_mask = TRUE,
    use_season_rasters = TRUE,
    incremental = FALSE
  )
  crop_params <- data.frame(class_value = 1L, crop_label = "Wheat", stringsAsFactors = FALSE)
  options(Rwapor.tiled_max_cells = 0)
  tiled <- wapor_run_seasonal_analysis_tiled(
    config = config,
    crop_params = crop_params,
    rasters = list(crop_mask = crop_mask, season_start = season_start, season_end = season_end),
    output_dir = out_dir,
    tile_size = tile_size
  )
  max_cells <- getOption("Rwapor.tiled_max_cells", 0)
  list(
    n_tiles = tiled$n_tiles,
    peak_bytes = as.numeric(max_cells) * 8,
    full_aoi_bytes = as.numeric(nrow) * as.numeric(ncol) * as.numeric(n_layers) * 8
  )
}

.wapor_tile_is_complete <- function(tile, expected = NULL) {
  if (!identical(tile$status, "complete")) {
    return(FALSE)
  }
  outputs <- tile$outputs
  if (is.null(outputs) || !length(outputs)) {
    return(FALSE)
  }
  for (nm in names(outputs)) {
    path <- outputs[[nm]]
    if (!.wapor_validate_tile_asset(path, expected)) {
      return(FALSE)
    }
    expected_hash <- tile$checksums[[nm]]
    if (!is.null(expected_hash) && !identical(.wapor_file_sha256(path), expected_hash)) {
      return(FALSE)
    }
  }
  TRUE
}

#' Run Windowed / Tiled Seasonal Analysis Engine
#'
#' Processes seasonal analysis in deterministic spatial tiles so large
#' extents do not need the full cube in RAM. Each tile is cropped, run
#' through tile-local block reducers, written as an immutable
#' GeoTIFF/COG, and recorded in a versioned run manifest. Completed tiles
#' can be resumed. Tile assets are assembled with a VRT rather than by
#' keeping a full-AOI mosaic in memory.
#'
#' @param config List of configuration parameters.
#' @param crop_params data.frame of crop class parameters.
#' @param rasters List of SpatRaster objects (mask, start, end).
#' @param output_dir Character. Output directory for tiled GeoTIFF products.
#' @param tile_size Integer. Square tile width/height in pixels (default: 512).
#' @param progress_callback Optional progress function(value, detail).
#' @param cog Logical. Write outputs with [wapor_write_cog()]. Default `FALSE`.
#' @param resume Logical. Reuse valid completed tiles from an existing
#'   run manifest in `output_dir`. Default `FALSE`.
#' @return List with paths to written raster files, the run manifest, tile
#'   counts, and VRT-backed `results` rasters.
#' @export
wapor_run_seasonal_analysis_tiled <- function(
  config,
  crop_params,
  rasters,
  output_dir = tempdir(),
  tile_size = 512L,
  progress_callback = NULL,
  cog = FALSE,
  resume = FALSE
) {
  if (is.null(progress_callback)) progress_callback <- function(v, d) NULL

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }
  tiles_dir <- file.path(output_dir, "tiles")
  dir.create(tiles_dir, recursive = TRUE, showWarnings = FALSE)
  manifest_path <- file.path(output_dir, "run_manifest.json")

  write_out <- function(r, path) {
    if (is.null(r)) {
      return(invisible(NULL))
    }
    if (isTRUE(cog)) {
      wapor_write_cog(r, path, overwrite = TRUE)
    } else {
      terra::writeRaster(r, path, overwrite = TRUE)
    }
    path
  }

  template_candidates <- Filter(
    function(x) inherits(x, "SpatRaster"),
    list(rasters$crop_mask, rasters$season_start, rasters$season_end)
  )
  template <- if (length(template_candidates)) template_candidates[[1]] else NULL
  if (is.null(template)) {
    stop("Tiled analysis requires rasters$crop_mask, season_start, or season_end as a template.", call. = FALSE)
  }
  if (terra::nlyr(template) > 1L) {
    template <- template[[1]]
  }

  n_row <- as.integer(terra::nrow(template))
  n_col <- as.integer(terra::ncol(template))
  windows <- .wapor_tiled_windows(n_row, n_col, tile_size)
  n_tiles <- length(windows)
  grid <- .wapor_grid_signature(template)
  config_hash <- .wapor_tiled_config_hash(config, tile_size, grid)

  existing <- NULL
  if (isTRUE(resume) && file.exists(manifest_path)) {
    existing <- .wapor_read_run_manifest(manifest_path)
    existing_hash <- existing$config_hash %||% NA_character_
    if (!identical(existing_hash, config_hash)) {
      stop(
        "Existing tiled run manifest does not match this configuration; refuse to resume.",
        call. = FALSE
      )
    }
  } else if (isTRUE(resume) && !file.exists(manifest_path)) {
    existing <- NULL
  }

  existing_by_id <- list()
  if (!is.null(existing) && length(existing$tiles)) {
    for (tile in existing$tiles) {
      if (!is.null(tile$id)) {
        existing_by_id[[tile$id]] <- tile
      }
    }
  }

  tile_records <- vector("list", n_tiles)
  tile_aeti_paths <- character(n_tiles)
  tile_adeq_paths <- character(n_tiles)
  tile_biomass_paths <- character(n_tiles)
  n_tiles_resumed <- 0L
  n_tiles_written <- 0L

  for (i in seq_along(windows)) {
    win <- windows[[i]]
    progress_callback(
      i / n_tiles,
      sprintf("Tile %d / %d (%s rows %d-%d cols %d-%d)...",
              i, n_tiles, win$id, win$row, win$row + win$nrows - 1L,
              win$col, win$col + win$ncols - 1L)
    )
    tile_template <- .wapor_crop_raster_window(template, win)
    prev <- existing_by_id[[win$id]]
    if (isTRUE(resume) && !is.null(prev) && .wapor_tile_is_complete(prev, tile_template)) {
      tile_records[[i]] <- prev
      tile_aeti_paths[i] <- prev$outputs$seasonal_aeti %||% NA_character_
      tile_adeq_paths[i] <- prev$outputs$adequacy_etc %||% NA_character_
      tile_biomass_paths[i] <- prev$outputs$seasonal_biomass %||% NA_character_
      n_tiles_resumed <- n_tiles_resumed + 1L
      next
    }

    tile_sources <- .wapor_window_source_rasters(
      config = config,
      win = win,
      template = template,
      dest_dir = file.path(tiles_dir, win$id, "sources")
    )
    tile_res <- .wapor_reduce_tile_indicators(
      config = config,
      crop_params = crop_params,
      rasters = rasters,
      win = win,
      template = template
    )

    snap_to_tile <- function(r) {
      if (is.null(r) || !inherits(r, "SpatRaster")) {
        return(r)
      }
      if (isTRUE(terra::compareGeom(r, tile_template, stopOnError = FALSE))) {
        return(r)
      }
      terra::resample(r, tile_template, method = "near")
    }

    aeti_r <- snap_to_tile(tile_res$seasonal_aeti)
    adeq_r <- snap_to_tile(tile_res$adequacy_etc)
    biomass_r <- snap_to_tile(tile_res$seasonal_biomass)

    outputs <- list()
    checksums <- list()
    if (!is.null(aeti_r)) {
      path <- file.path(tiles_dir, sprintf("%s_seasonal_aeti.tif", win$id))
      write_out(aeti_r, path)
      if (!.wapor_validate_tile_asset(path, tile_template)) {
        stop(sprintf("Tile %s seasonal_aeti failed geometry validation.", win$id), call. = FALSE)
      }
      outputs$seasonal_aeti <- path
      checksums$seasonal_aeti <- .wapor_file_sha256(path)
      tile_aeti_paths[i] <- path
    }
    if (!is.null(adeq_r)) {
      path <- file.path(tiles_dir, sprintf("%s_adequacy_etc.tif", win$id))
      write_out(adeq_r, path)
      outputs$adequacy_etc <- path
      checksums$adequacy_etc <- .wapor_file_sha256(path)
      tile_adeq_paths[i] <- path
    }
    if (!is.null(biomass_r)) {
      path <- file.path(tiles_dir, sprintf("%s_seasonal_biomass.tif", win$id))
      write_out(biomass_r, path)
      outputs$seasonal_biomass <- path
      checksums$seasonal_biomass <- .wapor_file_sha256(path)
      tile_biomass_paths[i] <- path
    }

    tile_records[[i]] <- list(
      id = win$id,
      row = win$row,
      col = win$col,
      nrows = win$nrows,
      ncols = win$ncols,
      status = "complete",
      outputs = outputs,
      checksums = checksums,
      sources = tile_sources$sources,
      reducer = tile_res$reducer %||% "block",
      used_full_engine = isTRUE(tile_res$used_full_engine)
    )
    n_tiles_written <- n_tiles_written + 1L
  }

  n_complete <- sum(vapply(tile_records, function(t) identical(t$status, "complete"), logical(1)))
  coverage <- list(
    n_tiles = n_tiles,
    n_complete = n_complete,
    n_resumed = n_tiles_resumed,
    n_written = n_tiles_written,
    complete = isTRUE(n_complete == n_tiles)
  )
  if (!isTRUE(coverage$complete)) {
    stop("Tiled analysis is incomplete; one or more tiles failed validation.", call. = FALSE)
  }

  vrt_aeti <- .wapor_assemble_vrt(
    tile_aeti_paths[!is.na(tile_aeti_paths) & nzchar(tile_aeti_paths)],
    file.path(output_dir, "seasonal_aeti.vrt")
  )
  vrt_adeq <- .wapor_assemble_vrt(
    tile_adeq_paths[!is.na(tile_adeq_paths) & nzchar(tile_adeq_paths)],
    file.path(output_dir, "adequacy_etc.vrt")
  )
  vrt_biomass <- .wapor_assemble_vrt(
    tile_biomass_paths[!is.na(tile_biomass_paths) & nzchar(tile_biomass_paths)],
    file.path(output_dir, "seasonal_biomass.vrt")
  )

  merged_aeti <- if (!is.null(vrt_aeti)) terra::rast(vrt_aeti) else NULL
  merged_adeq <- if (!is.null(vrt_adeq)) terra::rast(vrt_adeq) else NULL
  merged_biomass <- if (!is.null(vrt_biomass)) terra::rast(vrt_biomass) else NULL

  saved_files <- list()
  if (!is.null(merged_aeti)) {
    saved_files$seasonal_aeti_vrt <- vrt_aeti
    saved_files$seasonal_aeti <- write_out(merged_aeti, file.path(output_dir, "seasonal_aeti.tif"))
  }
  if (!is.null(merged_biomass)) {
    saved_files$seasonal_biomass_vrt <- vrt_biomass
    saved_files$seasonal_biomass <- write_out(merged_biomass, file.path(output_dir, "seasonal_biomass.tif"))
  }
  if (!is.null(merged_adeq)) {
    saved_files$adequacy_etc_vrt <- vrt_adeq
    saved_files$adequacy_etc <- write_out(merged_adeq, file.path(output_dir, "adequacy_etc.tif"))
  }

  manifest <- list(
    manifest_version = 1L,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    config_hash = config_hash,
    grid = grid,
    tile_size = as.integer(tile_size),
    cog = isTRUE(cog),
    versions = .wapor_runtime_versions(),
    sources = lapply(.wapor_requested_variables(config), function(var) {
      list(variable = var, paths = .wapor_resolve_source_paths(config, var))
    }),
    coverage = coverage,
    tiles = tile_records
  )
  .wapor_write_run_manifest(manifest_path, manifest)

  progress_callback(1.0, "Tiled seasonal processing complete.")
  list(
    results = list(
      seasonal_aeti = list(raster = merged_aeti),
      seasonal_biomass = merged_biomass,
      adequacy_etc = merged_adeq
    ),
    saved_files = saved_files,
    manifest_path = manifest_path,
    n_tiles = n_tiles,
    n_tiles_resumed = n_tiles_resumed,
    n_tiles_written = n_tiles_written
  )
}
