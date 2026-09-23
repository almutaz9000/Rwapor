# R/analysis_tiled.R
# =============================================================================
# Out-of-Core Tiled / Windowed Seasonal Analysis Engine
# =============================================================================
#
# Tiling itself lives in the shared kernel (R/processing_kernel.R). This file
# keeps the tile-window geometry, run-manifest helpers, test fixtures, and the
# exported wrapper that forces tiled mode.

#' Suggest a safe tile size for the tiled seasonal analysis engine
#'
#' Computes the largest square tile (in pixels) that fits within
#' `target_ram_mb` of working memory, given the number of raster layers,
#' variables and parallel workers. [wapor_plan_processing()] chooses a tile
#' size automatically; use this helper to pick one by hand for
#' [wapor_run_seasonal_analysis_tiled()].
#'
#' @param n_layers Integer. Number of raster layers to hold in memory at once
#'   (e.g. total dekadal layers in the season).
#' @param n_workers Integer. Number of parallel tile workers. Each worker
#'   holds one tile in RAM simultaneously. Default `1L`.
#' @param bytes_per_val Integer. Bytes per cell in memory. terra holds values
#'   as 8-byte doubles, so the default is `8L`.
#' @param target_ram_mb Numeric. RAM budget in megabytes. Default `4096` (4 GB).
#' @param min_tile Integer. Minimum tile size to return. Default `64L`.
#' @param max_tile Integer. Maximum tile size to return. Default `4096L`.
#' @param n_vars Integer. Number of variables read per tile. Default `1L`.
#' @param overhead Numeric. Multiplier for temporaries. Default `2.5`.
#'
#' @return A single integer: recommended tile side length in pixels.
#'
#' @details
#' Formula:
#'   bytes_per_tile = tile_size^2 * n_layers * n_vars * bytes_per_val * overhead
#'   total_bytes    = bytes_per_tile * n_workers
#'
#' The result is clamped to \[min_tile, max_tile\] so extreme inputs produce
#' a usable value rather than an error.
#'
#' @examples
#' # 36 dekadal layers, 2 workers, 8 GB RAM budget
#' wapor_suggest_tile_size(n_layers = 36L, n_workers = 2L, target_ram_mb = 8192)
#'
#' @export
wapor_suggest_tile_size <- function(n_layers,
                                    n_workers    = 1L,
                                    bytes_per_val = 8L,
                                    target_ram_mb = 4096,
                                    min_tile      = 64L,
                                    max_tile      = 4096L,
                                    n_vars        = 1L,
                                    overhead      = 2.5) {
  n_layers      <- max(1L, as.integer(n_layers))
  n_workers     <- max(1L, as.integer(n_workers))
  bytes_per_val <- max(1L, as.integer(bytes_per_val))
  target_ram_mb <- max(1, as.numeric(target_ram_mb))
  min_tile      <- max(1L, as.integer(min_tile))
  max_tile      <- max(min_tile, as.integer(max_tile))
  n_vars        <- max(1L, as.integer(n_vars))
  overhead      <- max(1, as.numeric(overhead))

  budget_bytes <- target_ram_mb * 1024^2
  per_cell     <- as.numeric(n_layers) * n_vars * bytes_per_val * overhead * n_workers
  raw_tile     <- floor(sqrt(budget_bytes / per_cell))
  tile         <- as.integer(max(min_tile, min(max_tile, raw_tile)))

  message(sprintf(
    "wapor_suggest_tile_size: %d px (n_layers=%d, n_vars=%d, n_workers=%d, budget=%.0f MB, %.1f MB/tile)",
    tile, n_layers, n_vars, n_workers, target_ram_mb,
    (as.numeric(tile)^2 * n_layers * n_vars * bytes_per_val * overhead) / 1024^2
  ))
  tile
}


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
  # WaPOR dekad labels: YYYY-MM-D1 / D2 / D3 start on day 01 / 11 / 21.
  m <- regmatches(nm, regexpr("\\d{4}-\\d{2}-D[123]", nm))
  if (length(m)) {
    day <- c(D1 = "01", D2 = "11", D3 = "21")[[substr(m, 9, 10)]]
    return(paste0(substr(m, 1, 8), day))
  }
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
#' Runs [wapor_run_seasonal_analysis()] with `processing = "tiled"`: the
#' analysis area is split into square tiles, each tile is aggregated from
#' windowed source reads, written as an immutable GeoTIFF/COG and recorded in
#' a versioned run manifest. Completed tiles can be resumed. Tile outputs are
#' assembled with a VRT rather than by holding a full-area mosaic in memory.
#'
#' Results are identical to the in-memory engine; only memory use differs.
#' Tiles run in parallel under the active [future::plan()].
#'
#' @param config List of configuration parameters (see
#'   [wapor_run_seasonal_analysis()]).
#' @param crop_params data.frame of crop class parameters.
#' @param rasters List of SpatRaster objects (mask, start, end).
#' @param output_dir Character. Output directory for tiled GeoTIFF products.
#' @param tile_size Integer. Square tile width/height in pixels (default: 512).
#' @param progress_callback Optional progress function(value, detail).
#' @param cog Logical. Write outputs with [wapor_write_cog()]. Default `FALSE`.
#' @param resume Logical. Reuse valid completed tiles from an existing
#'   run manifest in `output_dir`. Default `FALSE`.
#' @return List with paths to written raster files (`saved_files`), the run
#'   manifest path, tile counts, VRT-backed `results` rasters, and the full
#'   engine result as `analysis`.
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
  if (is.list(config$period)) {
    stop("wapor_run_seasonal_analysis_tiled() runs one season; call it once per period.", call. = FALSE)
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }
  cfg <- config
  cfg$processing <- "tiled"
  cfg$tile_size <- as.integer(tile_size)
  cfg$output_dir <- output_dir
  cfg$cog <- isTRUE(cog)
  cfg$resume <- isTRUE(resume)
  cfg$keep_intermediates <- cfg$keep_intermediates %||% FALSE

  res <- wapor_run_seasonal_analysis(
    config = cfg,
    crop_params = crop_params,
    rasters = rasters,
    progress_callback = progress_callback
  )

  write_out <- function(r, path) {
    if (is.null(r)) {
      return(NULL)
    }
    if (isTRUE(cog)) {
      wapor_write_cog(r, path, overwrite = TRUE, datatype = "FLT8S")
    } else {
      terra::writeRaster(r, path, overwrite = TRUE, datatype = "FLT8S")
    }
    path
  }

  aeti <- res$seasonal_aeti$raster
  saved_files <- list()
  if (!is.null(aeti)) {
    saved_files$seasonal_aeti_vrt <- file.path(output_dir, "seasonal_aeti.vrt")
    saved_files$seasonal_aeti <- write_out(aeti, file.path(output_dir, "seasonal_aeti.tif"))
  }
  if (!is.null(res$seasonal_biomass)) {
    saved_files$seasonal_biomass <- write_out(res$seasonal_biomass, file.path(output_dir, "seasonal_biomass.tif"))
  }
  if (!is.null(res$adequacy_etc)) {
    saved_files$adequacy_etc <- write_out(res$adequacy_etc, file.path(output_dir, "adequacy_etc.tif"))
  }

  list(
    results = list(
      seasonal_aeti = list(raster = aeti),
      seasonal_biomass = res$seasonal_biomass,
      adequacy_etc = res$adequacy_etc
    ),
    saved_files = saved_files,
    manifest_path = res$processing_run$manifest_path,
    n_tiles = res$processing_run$n_tiles,
    n_tiles_resumed = res$processing_run$n_tiles_resumed,
    n_tiles_written = res$processing_run$n_tiles_written,
    analysis = res
  )
}
