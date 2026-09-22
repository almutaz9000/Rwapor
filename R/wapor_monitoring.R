# Current schema version.  Bump this integer whenever a migration step is added
# to .wapor_monitoring_migrate() below.
.RWAPOR_DB_SCHEMA_VERSION <- 2L

#' Initialize a DuckDB database for farm monitoring
#'
#' Creates all required tables (if they do not yet exist) and runs any pending
#' schema migrations against an existing database.  The function is idempotent:
#' calling it on a fully up-to-date database is a no-op.
#'
#' @param con DuckDB connection object.
#' @return The connection object invisibly.
#' @export
wapor_init_monitoring_db <- function(con) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("Package 'duckdb' is required for monitoring databases.")
  }

  # ── 0. Monitoring Metadata (must exist first — stores schema_version) ────────
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS monitoring_metadata (
      key   TEXT PRIMARY KEY,
      value TEXT
    )
  ")

  # ── 1. Farm Time Series ──────────────────────────────────────────────────────
  # season_id: explicit season label (e.g. '2023-2024') enables multi-season
  # queries without relying on date arithmetic.  Added in schema v2.
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS farm_timeseries (
      farm_id       TEXT,
      season_id     TEXT    DEFAULT 'default',
      crop_type     TEXT,
      sowing_date   DATE,
      variable      TEXT,
      start_date    DATE,
      end_date      DATE,
      mean_val      DOUBLE,
      min_val       DOUBLE,
      max_val       DOUBLE,
      std_val       DOUBLE,
      p05_val       DOUBLE,
      p95_val       DOUBLE,
      threshold_pct DOUBLE DEFAULT 0,
      pixels_used   INTEGER,
      pixels_total  INTEGER,
      units         TEXT,
      updated_at    TIMESTAMP DEFAULT current_timestamp,
      PRIMARY KEY (farm_id, season_id, variable, start_date)
    )
  ")

  # ── 2. Monitoring Rasters ────────────────────────────────────────────────────
  # raster_path stores the file-system path to a COG on disk.
  # raster_blob is kept for backward-compatibility but should be NULL for new rows.
  # encoding, gdal_version, terra_version, nodata, band_count enable
  # portable raster blob decoding across R version updates.
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS monitoring_rasters (
      variable      TEXT,
      date_key      DATE,
      raster_path   TEXT,
      raster_blob   BLOB,
      encoding      TEXT    DEFAULT 'geotiff_lzw',
      gdal_version  TEXT,
      terra_version TEXT,
      xmin          DOUBLE,
      xmax          DOUBLE,
      ymin          DOUBLE,
      ymax          DOUBLE,
      nrow          INTEGER,
      ncol          INTEGER,
      resolution_x  DOUBLE,
      resolution_y  DOUBLE,
      nodata        DOUBLE,
      band_count    INTEGER DEFAULT 1,
      units         TEXT,
      crs_epsg      INTEGER DEFAULT 4326,
      updated_at    TIMESTAMP DEFAULT current_timestamp,
      PRIMARY KEY (variable, date_key)
    )
  ")

  # ── 3. Farm Rasters (Legacy / Per-Farm blobs) ────────────────────────────────
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS farm_rasters (
      farm_id      TEXT,
      variable     TEXT,
      date_key     DATE,
      raster_blob  BLOB,
      xmin         DOUBLE,
      xmax         DOUBLE,
      ymin         DOUBLE,
      ymax         DOUBLE,
      nrow         INTEGER,
      ncol         INTEGER,
      resolution_x DOUBLE,
      resolution_y DOUBLE,
      units        TEXT,
      crs_epsg     INTEGER DEFAULT 4326,
      updated_at   TIMESTAMP DEFAULT current_timestamp,
      PRIMARY KEY (farm_id, variable, date_key)
    )
  ")

  # ── 4. Farm Polygons (Geometries) ────────────────────────────────────────────
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS farm_polygons (
      farm_id      TEXT PRIMARY KEY,
      crop_type    TEXT,
      label        TEXT,
      area_ha      DOUBLE,
      geometry_wkt TEXT,
      crs_epsg     INTEGER DEFAULT 4326,
      created_at   TIMESTAMP DEFAULT current_timestamp
    )
  ")

  # ── 5. Raster Grid Registry ──────────────────────────────────────────────────
  # Each (variable, grid_id) row records the canonical geometry for that
  # variable's raster timeseries.  New writes are rejected when the grid
  # does not match the registered entry, preventing silent mixed-resolution
  # timeseries.
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS raster_grid_registry (
      variable      TEXT PRIMARY KEY,
      grid_id       TEXT,
      xmin          DOUBLE,
      xmax          DOUBLE,
      ymin          DOUBLE,
      ymax          DOUBLE,
      nrow          INTEGER,
      ncol          INTEGER,
      res_x         DOUBLE,
      res_y         DOUBLE,
      crs_wkt       TEXT,
      nodata        DOUBLE,
      registered_at TIMESTAMP DEFAULT current_timestamp
    )
  ")

  # ── 6. Seasonal Aggregated Rasters ───────────────────────────────────────────
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS farm_seasonal_rasters (
      farm_id     TEXT,
      variable    TEXT,
      season_id   TEXT,
      raster_blob BLOB,
      xmin        DOUBLE,
      xmax        DOUBLE,
      ymin        DOUBLE,
      ymax        DOUBLE,
      nrow        INTEGER,
      ncol        INTEGER,
      updated_at  TIMESTAMP DEFAULT current_timestamp,
      PRIMARY KEY (farm_id, variable, season_id)
    )
  ")

  # ── 7. Monitoring Logs ───────────────────────────────────────────────────────
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS monitoring_log (
      run_id      TEXT,
      started_at  TIMESTAMP,
      finished_at TIMESTAMP,
      n_records   INTEGER,
      status      TEXT,
      message     TEXT
    )
  ")

  # ── 8. Indexes ───────────────────────────────────────────────────────────────
  tryCatch(DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ts_farm_var    ON farm_timeseries(farm_id, variable)"), error = function(e) NULL)
  tryCatch(DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ts_season      ON farm_timeseries(season_id, variable)"), error = function(e) NULL)
  tryCatch(DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_rast_farm_var  ON farm_rasters(farm_id, variable)"), error = function(e) NULL)
  tryCatch(DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_mon_rast_var   ON monitoring_rasters(variable, date_key)"), error = function(e) NULL)

  # ── 9. Schema migration ──────────────────────────────────────────────────────
  .wapor_monitoring_migrate(con)

  invisible(con)
}

#' Apply pending schema migrations to a monitoring database
#'
#' Called automatically by [wapor_init_monitoring_db()].  Reads the current
#' schema version from `monitoring_metadata` and applies any migration steps
#' whose version number is higher than the stored one.
#'
#' @param con DuckDB connection.
#' @return Invisibly, the new schema version integer.
#' @keywords internal
#' @noRd
.wapor_monitoring_migrate <- function(con) {
  # Read stored version (NULL / NA means legacy pre-versioned DB -> version 0)
  stored_v <- tryCatch({
    r <- DBI::dbGetQuery(con, "SELECT value FROM monitoring_metadata WHERE key = 'schema_version'")
    if (nrow(r) == 0L) 0L else as.integer(r$value[[1]])
  }, error = function(e) 0L)

  if (is.na(stored_v)) stored_v <- 0L
  target_v <- .RWAPOR_DB_SCHEMA_VERSION

  if (stored_v >= target_v) return(invisible(target_v))

  # ── Migration v1: add columns present from v0 legacy DBs ─────────────────
  if (stored_v < 1L) {
    for (stmt in c(
      "ALTER TABLE farm_timeseries ADD COLUMN IF NOT EXISTS units TEXT",
      "ALTER TABLE farm_rasters    ADD COLUMN IF NOT EXISTS resolution_x DOUBLE",
      "ALTER TABLE farm_rasters    ADD COLUMN IF NOT EXISTS resolution_y DOUBLE",
      "ALTER TABLE farm_rasters    ADD COLUMN IF NOT EXISTS units TEXT",
      "ALTER TABLE farm_rasters    ADD COLUMN IF NOT EXISTS crs_epsg INTEGER DEFAULT 4326"
    )) {
      tryCatch(DBI::dbExecute(con, stmt), error = function(e) NULL)
    }
  }

  # ── Migration v2: add season_id, raster_path, encoding, nodata, etc. ──────
  if (stored_v < 2L) {
    for (stmt in c(
      "ALTER TABLE farm_timeseries     ADD COLUMN IF NOT EXISTS season_id TEXT DEFAULT 'default'",
      "ALTER TABLE monitoring_rasters  ADD COLUMN IF NOT EXISTS raster_path   TEXT",
      "ALTER TABLE monitoring_rasters  ADD COLUMN IF NOT EXISTS encoding      TEXT DEFAULT 'geotiff_lzw'",
      "ALTER TABLE monitoring_rasters  ADD COLUMN IF NOT EXISTS gdal_version  TEXT",
      "ALTER TABLE monitoring_rasters  ADD COLUMN IF NOT EXISTS terra_version TEXT",
      "ALTER TABLE monitoring_rasters  ADD COLUMN IF NOT EXISTS nodata        DOUBLE",
      "ALTER TABLE monitoring_rasters  ADD COLUMN IF NOT EXISTS band_count    INTEGER DEFAULT 1"
    )) {
      tryCatch(DBI::dbExecute(con, stmt), error = function(e) NULL)
    }
  }

  # Record new version
  DBI::dbExecute(con,
    "INSERT OR REPLACE INTO monitoring_metadata (key, value) VALUES ('schema_version', ?)",
    list(as.character(target_v))
  )
  invisible(target_v)
}

#' Validate raster grid homogeneity for a variable
#'
#' Checks that the raster about to be written matches the grid registered for
#' this variable.  If no grid is registered yet, registers this raster as the
#' reference.  Raises an error if the geometry does not match.
#'
#' @param con DuckDB connection.
#' @param variable Character. WaPOR variable code.
#' @param r SpatRaster whose geometry to validate.
#' @return Invisibly TRUE if valid (or newly registered).
#' @keywords internal
#' @noRd
.wapor_validate_raster_grid <- function(con, variable, r) {
  e   <- terra::ext(r)
  nr  <- as.integer(terra::nrow(r))
  nc  <- as.integer(terra::ncol(r))
  rx  <- round(terra::xres(r), digits = 10)
  ry  <- round(terra::yres(r), digits = 10)
  xmn <- round(e$xmin, digits = 8)
  xmx <- round(e$xmax, digits = 8)
  ymn <- round(e$ymin, digits = 8)
  ymx <- round(e$ymax, digits = 8)

  existing <- tryCatch(
    DBI::dbGetQuery(con, "SELECT * FROM raster_grid_registry WHERE variable = ?", list(variable)),
    error = function(e) data.frame()
  )

  if (nrow(existing) == 0L) {
    # Register as canonical grid for this variable
    DBI::dbExecute(con,
      "INSERT OR REPLACE INTO raster_grid_registry
         (variable, grid_id, xmin, xmax, ymin, ymax, nrow, ncol, res_x, res_y, crs_wkt)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      list(variable, paste0(variable, "_grid"), xmn, xmx, ymn, ymx, nr, nc, rx, ry, terra::crs(r))
    )
    return(invisible(TRUE))
  }

  reg <- existing[1L, ]
  mismatches <- character(0)
  tol <- 1e-7
  if (abs(xmn - reg$xmin) > tol) mismatches <- c(mismatches, sprintf("xmin %.8f != registered %.8f", xmn, reg$xmin))
  if (abs(xmx - reg$xmax) > tol) mismatches <- c(mismatches, sprintf("xmax %.8f != registered %.8f", xmx, reg$xmax))
  if (abs(ymn - reg$ymin) > tol) mismatches <- c(mismatches, sprintf("ymin %.8f != registered %.8f", ymn, reg$ymin))
  if (abs(ymx - reg$ymax) > tol) mismatches <- c(mismatches, sprintf("ymax %.8f != registered %.8f", ymx, reg$ymax))
  if (nr != as.integer(reg$nrow))  mismatches <- c(mismatches, sprintf("nrow %d != registered %d", nr, as.integer(reg$nrow)))
  if (nc != as.integer(reg$ncol))  mismatches <- c(mismatches, sprintf("ncol %d != registered %d", nc, as.integer(reg$ncol)))

  if (length(mismatches)) {
    stop(sprintf(
      "Raster grid mismatch for variable '%s':\n  %s\n\nThe registered grid was set from the first downloaded layer. All layers must share the same grid for a homogeneous timeseries. Use wapor_harmonize_raster() to align before writing, or clear the registry entry to re-register.",
      variable, paste(mismatches, collapse = "\n  ")
    ), call. = FALSE)
  }
  invisible(TRUE)
}

#' Run the monitoring update loop for a set of farms
#'
#' @param con DuckDB connection.
#' @param farms_sf sf object containing farm polygons with a `farm_id` column.
#' @param variables Vector of WaPOR variable codes to monitor.
#' @param period Date range c(start, end).
#' @param save_rasters Logical; if TRUE, saves clipped raster blobs to the database.
#' @param l3_region Optional L3 region code for L3 variables.
#' @param log_fn Optional function for logging messages (e.g. `message` or a custom function).
#' @return A list with statistics about the run.
#' @export
wapor_run_monitoring <- function(con, farms_sf, variables, period, 
                                 save_rasters = TRUE, l3_region = NULL, 
                                 log_fn = message) {
  
  if (!"farm_id" %in% names(farms_sf)) {
    stop("farms_sf must contain a 'farm_id' column.")
  }

  # Ensure DuckDB connection is valid
  if (is.null(con)) {
    stop("DuckDB connection 'con' cannot be NULL.")
  }

  run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
  run_start <- Sys.time()
  total_new_ts <- 0L

  # Ensure database is initialized
  wapor_init_monitoring_db(con)

  # Save Global Metadata (BBOX and Geometry)
  tryCatch({
    bbox <- sf::st_bbox(farms_sf)
    bbox_json <- jsonlite::toJSON(as.list(bbox), auto_unbox = TRUE)
    geom_wkt <- sf::st_as_text(sf::st_geometry(sf::st_union(farms_sf))[[1]])
    
    DBI::dbExecute(con, "INSERT OR REPLACE INTO monitoring_metadata (key, value) VALUES ('global_bbox', ?)", list(bbox_json))
    DBI::dbExecute(con, "INSERT OR REPLACE INTO monitoring_metadata (key, value) VALUES ('global_geometry_wkt', ?)", list(geom_wkt))
  }, error = function(e) log_fn(sprintf("  Warning: could not save global metadata: %s", e$message)))

  # Loop through variables
  for (var in variables) {
    log_fn(sprintf("Monitoring variable: %s", var))
    
    # Determine target unit conversion (matches download module logic)
    unit_conv <- resolve_output_unit_conversion(var, NULL)
    if (identical(unit_conv, "dekad")) {
      log_fn("  Variable is Dekadal. Scaling to unit/dekad.")
    }

    # 1. Fetch Time Series (Incremental)
    tryCatch({
      # Check last date in DB for this variable
      last_date_query <- DBI::dbGetQuery(con, 
        "SELECT MAX(end_date) as last_date FROM farm_timeseries WHERE variable = ?", 
        params = list(var))
      
      effective_start <- if (!is.na(last_date_query$last_date)) {
        as.character(as.Date(last_date_query$last_date) + 1)
      } else {
        period[1]
      }

      if (as.Date(effective_start) > as.Date(period[2])) {
        log_fn(sprintf("  Up to date for %s", var))
      } else {
        log_fn(sprintf("  Fetching TS from %s to %s...", effective_start, period[2]))
        
        ts_df <- Rwapor::wapor_ts(
          region          = farms_sf,
          variable        = var,
          period          = c(effective_start, period[2]),
          identifier      = "farm_id",
          unit_conversion = unit_conv,
          l3_region       = if (grepl("^L3-", var)) l3_region else NULL,
          batching        = TRUE
        )

        if (!is.null(ts_df) && nrow(ts_df) > 0) {
          # Get harmonized units from the resulting data frame attribute
          var_units <- attr(ts_df, "units") %||% NA_character_

          # Prepare for insertion (Match full schema to avoid append errors)
          insert_df <- data.frame(
            farm_id       = as.character(ts_df$farm_id),
            season_id     = paste(period[1], period[2], sep = "/"),
            crop_type     = if ("crop_type" %in% names(ts_df)) as.character(ts_df$crop_type) else NA_character_,
            sowing_date   = as.Date(period[1]),
            variable      = var,
            start_date    = as.Date(ts_df$start_date),
            end_date      = as.Date(ts_df$end_date),
            mean_val      = as.numeric(ts_df$mean),
            min_val       = if ("min" %in% names(ts_df)) as.numeric(ts_df$min) else NA_real_,
            max_val       = if ("max" %in% names(ts_df)) as.numeric(ts_df$max) else NA_real_,
            std_val       = if ("std" %in% names(ts_df)) as.numeric(ts_df$std) else NA_real_,
            p05_val       = NA_real_,
            p95_val       = NA_real_,
            threshold_pct = 0,
            pixels_used   = if ("pixels_used" %in% names(ts_df)) as.integer(ts_df$pixels_used) else NA_integer_,
            pixels_total  = if ("pixels_total" %in% names(ts_df)) as.integer(ts_df$pixels_total) else NA_integer_,
            units         = var_units,
            stringsAsFactors = FALSE
          )

          # Use INSERT OR REPLACE (upsert) to handle reruns of overlapping
          # periods without PRIMARY KEY violations. Each row is identified by
          # (farm_id, season_id, variable, start_date).
          if (nrow(insert_df) > 0L) {
            tmp_tbl <- paste0("_rwapor_ts_tmp_", format(Sys.time(), "%H%M%S"))
            DBI::dbWriteTable(con, tmp_tbl, insert_df, overwrite = TRUE, temporary = TRUE)
            cols <- paste(names(insert_df)[names(insert_df) != "updated_at"], collapse = ", ")
            DBI::dbExecute(con, sprintf(
              "INSERT OR REPLACE INTO farm_timeseries (%s) SELECT %s FROM %s",
              cols, cols, tmp_tbl
            ))
            tryCatch(DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s", tmp_tbl)), error = function(e) NULL)
          }
          total_new_ts <- total_new_ts + nrow(insert_df)
          log_fn(sprintf("  Saved/updated %d TS records.", nrow(insert_df)))
        }
      }
    }, error = function(e) {
      log_fn(sprintf("  Error fetching TS for %s: %s", var, e$message))
    })

    # 2. Save Raster Blobs
    if (save_rasters) {
      tryCatch({
        log_fn(sprintf("  Processing raster blobs for %s...", var))
        wapor_save_raster_blobs(con, farms_sf, var, period, log_fn, l3_region)
      }, error = function(e) {
        log_fn(sprintf("  Error saving raster blobs for %s: %s", var, e$message))
      })
    }
  }

  # Final Log
  DBI::dbExecute(con,
    "INSERT INTO monitoring_log (run_id, started_at, finished_at, n_records, status, message)
     VALUES (?,?,?,?,?,?)",
    params = list(run_id,
      format(run_start, "%Y-%m-%d %H:%M:%S"),
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      as.integer(total_new_ts), "success", "Monitoring run completed"))

  list(run_id = run_id, total_ts = total_new_ts)
}

#' Resolve the on-disk directory used for file-backed monitoring rasters
#'
#' Rasters are stored as COGs alongside the DuckDB file whenever the
#' connection has a real file path (raster_store/ sibling directory);
#' falls back to a session tempdir for in-memory or unusual connections so
#' the write path never errors.
#'
#' @param con DuckDB connection.
#' @return Character path to the store directory (created if missing).
#' @keywords internal
#' @noRd
.wapor_monitoring_raster_store_dir <- function(con) {
  dbdir <- tryCatch(DBI::dbGetInfo(con)$dbname, error = function(e) NA_character_)
  store_dir <- if (!is.null(dbdir) && length(dbdir) == 1L && nzchar(dbdir) &&
                    !identical(dbdir, ":memory:") && dir.exists(dirname(dbdir))) {
    file.path(dirname(dbdir), paste0(tools::file_path_sans_ext(basename(dbdir)), "_raster_store"))
  } else {
    file.path(tempdir(), "rwapor_raster_store")
  }
  dir.create(store_dir, recursive = TRUE, showWarnings = FALSE)
  store_dir
}

#' Save clipped WaPOR raster blobs to a monitoring database
#'
#' Writes each cropped seasonal/dekadal layer both as an in-memory
#' compressed GeoTIFF blob (backward-compatible, unchanged read path) and as
#' a file-backed COG under `.wapor_monitoring_raster_store_dir()`, recorded
#' in the raster_path column together with gdal_version, terra_version, and
#' band_count provenance. Remote layers for one variable are opened as a
#' single batched /vsicurl/ stack rather than one GDAL dataset handle per
#' layer, cutting per-layer header round-trips.
#'
#' @param con DuckDB connection.
#' @param farms_sf sf object with farm polygons.
#' @param variable WaPOR variable code.
#' @param period Date range c(start, end).
#' @param log_fn Function for logging.
#' @param l3_region Optional L3 region code.
#' @return NULL (invisibly).
#' @keywords internal
wapor_save_raster_blobs <- function(con, farms_sf, variable, period, log_fn = message, l3_region = NULL) {
  if (!requireNamespace("duckdb", quietly = TRUE)) return(invisible(NULL))

  tryCatch({
    # Determine target unit conversion
    unit_conv <- resolve_output_unit_conversion(variable, NULL)

    # Look up final harmonized units
    var_units <- tryCatch({
      m <- Rwapor::wapor_variable_metadata(variable)
      if (is.null(m)) return(NA_character_)
      res_u <- m$units %||% NA_character_
      if (grepl("^AGERA5-(TMIN|TMAX)-", variable, ignore.case = FALSE)) res_u <- sub("^K$", "degC", res_u)
      if (unit_conv != "none") {
        parts <- strsplit(res_u, "/")[[1]]
        if (length(parts) > 1) res_u <- paste0(paste(parts[-length(parts)], collapse = "/"), "/", unit_conv)
      }
      res_u
    }, error = function(e) NA_character_)

    # Build bounding-box AOI for the whole project
    bb      <- sf::st_bbox(farms_sf)
    aoi_ext <- terra::ext(bb["xmin"], bb["xmax"], bb["ymin"], bb["ymax"])

    urls <- tryCatch(
      Rwapor::wapor_generate_urls(
        variable,
        l3_region = if (grepl("^L3-", variable)) l3_region else NULL,
        period    = period
      ),
      error = function(e) { log_fn(sprintf("  Raster URLs error: %s", e$message)); NULL }
    )
    if (is.null(urls) || length(urls) == 0) return(invisible(NULL))

    urls_vs <- .wapor_resolve_remote_sources(urls)
    log_fn(sprintf("  Clipping & saving %d global raster layers for %s...", length(urls_vs), variable))

    # Query already-saved dates in the global table
    existing_dates <- tryCatch(
      DBI::dbGetQuery(con,
        "SELECT CAST(date_key AS VARCHAR) AS dk FROM monitoring_rasters WHERE variable = ?",
        params = list(variable)
      )$dk,
      error = function(e) character(0)
    )

    # Pre-compute date keys for every URL up front so we can skip already-saved
    # dates BEFORE opening any remote dataset.
    date_keys <- vapply(seq_along(urls), function(i) {
      tryCatch({
        di <- Rwapor::wapor_date_info(urls[i], sub(".*-([A-Z])$", "\\1", variable))
        as.character(di$start_date)
      }, error = function(e) {
        m <- regmatches(basename(urls[i]), regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}", basename(urls[i])))
        if (length(m) > 0) m[1] else format(Sys.Date(), "%Y-%m-%d")
      })
    }, character(1))

    pending_idx <- which(!(date_keys %in% existing_dates))
    n_ok   <- 0L
    n_skip <- length(urls) - length(pending_idx)

    if (length(pending_idx) == 0L) {
      log_fn(sprintf("  All %d layers already saved for %s.", length(urls), variable))
      return(invisible(NULL))
    }

    # 1. BATCH OPEN: open every pending layer's vsicurl URL for this variable
    # in a single terra::rast() call instead of one dataset handle per layer.
    # Layers of one WaPOR variable share a grid, so this is a single
    # multi-band SpatRaster rather than N sequential single-band opens.
    r_stack <- tryCatch(
      suppressWarnings(terra::rast(urls_vs[pending_idx])),
      error = function(e) {
        log_fn(sprintf("  Batched open failed (%s); falling back to per-layer open.", e$message))
        NULL
      }
    )

    if (is.null(r_stack)) {
      # Fallback: open one dataset at a time (previous behavior), still
      # writing both blob and file-backed COG for each successfully opened
      # layer.
      layer_rasters <- lapply(pending_idx, function(i) {
        tryCatch(suppressWarnings(terra::rast(urls_vs[i])), error = function(e) NULL)
      })
      ok_pos <- !vapply(layer_rasters, is.null, logical(1))
      if (!any(ok_pos)) {
        log_fn(sprintf("  Error loading any layer for %s.", variable))
        return(invisible(NULL))
      }
      pending_idx <- pending_idx[ok_pos]
      r_stack <- terra::rast(layer_rasters[ok_pos])
    }

    # 2. CRS HANDLING: Some variables are WGS84 (L1/L2), some are UTM (L3).
    # Determined once for the whole batch since all layers of one variable
    # share the same source grid/CRS.
    is_projected <- !isTRUE(terra::is.lonlat(r_stack))

    if (is_projected) {
      r_crs <- terra::crs(r_stack)
      aoi_poly <- sf::st_as_sfc(sf::st_bbox(aoi_ext, crs = 4326))
      aoi_proj <- sf::st_transform(aoi_poly, r_crs)
      check_ext <- terra::ext(as.numeric(sf::st_bbox(aoi_proj)))
    } else {
      check_ext <- aoi_ext
    }

    # 3. SPATIAL CHECK: Ensure the batch overlaps the AOI in its own CRS
    r_ext <- terra::ext(r_stack)
    if (check_ext$xmin >= r_ext$xmax || check_ext$xmax <= r_ext$xmin ||
        check_ext$ymin >= r_ext$ymax || check_ext$ymax <= r_ext$ymin) {
      log_fn(sprintf("  Batch for %s does not overlap AOI; skipping.", variable))
      return(invisible(NULL))
    }

    # 4. CHUNKED CLIPPING: crop the whole stack once (vsicurl only downloads
    # the pixels within the BBOX, across all bands in one request set).
    r_stack_crop <- tryCatch(terra::crop(r_stack, check_ext), error = function(e) NULL)
    if (is.null(r_stack_crop)) {
      log_fn(sprintf("  Batch crop failed for %s.", variable))
      return(invisible(NULL))
    }

    store_dir     <- .wapor_monitoring_raster_store_dir(con)
    gdal_version  <- tryCatch(as.character(terra::gdal()), error = function(e) NA_character_)
    terra_version <- tryCatch(as.character(utils::packageVersion("terra")), error = function(e) NA_character_)

    # 5. PER-LAYER FINISH: unit conversion, temperature conversion,
    # metadata, optional WGS84 reprojection, blob + file-backed COG write.
    for (k in seq_along(pending_idx)) {
      i <- pending_idx[k]
      date_key <- date_keys[i]

      r_crop <- tryCatch(r_stack_crop[[k]], error = function(e) NULL)
      if (is.null(r_crop)) { n_skip <- n_skip + 1L; next }

      r_crop <- Rwapor::wapor_convert_raster(r_crop, variable, urls[i], unit_conv)
      r_crop <- Rwapor::wapor_convert_temperature(r_crop, variable)
      r_crop <- assign_raster_metadata(r_crop, variable, unit_conv, var_units)

      # RE-PROJECT TO WGS84: Store all blobs in a standard geographic CRS for the dashboard
      if (is_projected) {
        r_crop <- tryCatch({
          src_res <- terra::res(r_crop)
          center_lat <- (as.numeric(aoi_ext$ymin) + as.numeric(aoi_ext$ymax)) / 2
          res_y_deg <- src_res[2] / 111320
          res_x_deg <- src_res[1] / (111320 * cos(center_lat * pi / 180))

          wgs84_template <- terra::rast(ext = aoi_ext, res = c(res_x_deg, res_y_deg))
          terra::crs(wgs84_template) <- "EPSG:4326"

          terra::project(r_crop, wgs84_template, method = "bilinear")
        }, error = function(e) NULL)
        if (is.null(r_crop)) { n_skip <- n_skip + 1L; next }
      }

      # Final metadata for the cropped/projected result
      dims      <- dim(r_crop)
      res_xy    <- terra::res(r_crop)
      ext_final <- terra::ext(r_crop)
      band_count <- as.integer(terra::nlyr(r_crop))
      nodata_val <- tryCatch({
        nd <- suppressWarnings(terra::NAflag(r_crop))
        if (length(nd) == 0 || is.na(nd[1])) NA_real_ else as.numeric(nd[1])
      }, error = function(e) NA_real_)

      # In-memory compressed blob (backward-compatible read path)
      temp_file <- tempfile(fileext = ".tif")
      terra::writeRaster(r_crop, temp_file, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))
      raster_blob <- readBin(temp_file, "raw", n = file.info(temp_file)$size)
      if (file.exists(temp_file)) unlink(temp_file)

      # File-backed COG, one per (variable, date_key)
      raster_path <- tryCatch({
        cog_path <- file.path(store_dir, sprintf("%s_%s.tif", gsub("[^A-Za-z0-9_-]", "_", variable), date_key))
        Rwapor::wapor_write_cog(r_crop, cog_path, overwrite = TRUE)
        cog_path
      }, error = function(e) {
        log_fn(sprintf("  Warning: COG write failed for %s %s: %s", variable, date_key, e$message))
        NA_character_
      })

      # Save to optimized global table
      tryCatch({
        .package_save_global_raster_blob_to_db(
          con, variable, date_key, raster_blob,
          ext_final$xmin, ext_final$xmax, ext_final$ymin, ext_final$ymax,
          dims[1], dims[2], res_xy[1], res_xy[2], var_units,
          raster_path = raster_path, gdal_version = gdal_version,
          terra_version = terra_version, nodata = nodata_val, band_count = band_count
        )
        n_ok <- n_ok + 1L
      }, error = function(e) log_fn(sprintf("  Error saving global blob: %s", e$message)))
    }

    log_fn(sprintf("  Processed %d global layers for variable %s (%d already saved).", n_ok, variable, n_skip))

  }, error = function(e) {
    log_fn(sprintf("  wapor_save_raster_blobs error: %s", e$message))
  })
}

# Optimized helper for Global Raster Blobs
.package_save_global_raster_blob_to_db <- function(con, variable, date_key, raster_blob,
                                                   xmin, xmax, ymin, ymax, nrow, ncol,
                                                   res_x, res_y, units,
                                                   raster_path = NA_character_,
                                                   gdal_version = NA_character_,
                                                   terra_version = NA_character_,
                                                   nodata = NA_real_,
                                                   band_count = 1L) {
  insert_sql <- "
    INSERT INTO monitoring_rasters (
      variable, date_key, raster_blob,
      xmin, xmax, ymin, ymax, nrow, ncol,
      resolution_x, resolution_y, units, crs_epsg,
      raster_path, gdal_version, terra_version, nodata, band_count
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (variable, date_key)
    DO UPDATE SET
      raster_blob   = EXCLUDED.raster_blob,
      xmin          = EXCLUDED.xmin,
      xmax          = EXCLUDED.xmax,
      ymin          = EXCLUDED.ymin,
      ymax          = EXCLUDED.ymax,
      nrow          = EXCLUDED.nrow,
      ncol          = EXCLUDED.ncol,
      resolution_x  = EXCLUDED.resolution_x,
      resolution_y  = EXCLUDED.resolution_y,
      units         = EXCLUDED.units,
      raster_path   = EXCLUDED.raster_path,
      gdal_version  = EXCLUDED.gdal_version,
      terra_version = EXCLUDED.terra_version,
      nodata        = EXCLUDED.nodata,
      band_count    = EXCLUDED.band_count,
      crs_epsg      = EXCLUDED.crs_epsg
  "
  DBI::dbExecute(con, insert_sql, params = list(
    variable, as.character(date_key), list(raster_blob),
    xmin, xmax, ymin, ymax, nrow, ncol,
    res_x, res_y, units, 4326L,
    raster_path, gdal_version, terra_version, nodata, band_count
  ))
}

#' Extract Raster from DuckDB BLOB
#'
#' @param blob_data Raw vector containing raster BLOB
#' @return terra SpatRaster object
#' @keywords internal
wapor_raster_from_blob <- function(blob_data) {
  if (is.null(blob_data) || length(blob_data) == 0) {
    return(NULL)
  }

  temp_file <- tempfile(fileext = ".tif")
  writeBin(blob_data, temp_file)
  r <- terra::rast(temp_file)
  return(r)
}

#' Calculate Enhanced Zonal Statistics
#'
#' Extracts pixel values within a polygon and applies a percentile-based
#' threshold filter to remove noise or edge pixels.
#'
#' @param raster terra SpatRaster object
#' @param polygon sf object with farm boundaries
#' @param threshold_percentile Numeric (0-50). Percentile threshold to filter low values.
#' @return data.frame with mean, min, max, std, and pixel counts.
#' @export
wapor_enhanced_zonal_stats <- function(raster, polygon, threshold_percentile = 0) {
  if (!requireNamespace("exactextractr", quietly = TRUE)) {
    stop("Package 'exactextractr' required for zonal statistics")
  }

  # Extract all pixel values within polygon
  pixel_values <- exactextractr::exact_extract(raster, polygon, progress = FALSE)

  # Calculate stats for each polygon
  results <- lapply(seq_along(pixel_values), function(i) {
    vals <- pixel_values[[i]]

    if (is.null(vals) || nrow(vals) == 0) {
      return(data.frame(
        mean_val = NA_real_, min_val = NA_real_, max_val = NA_real_,
        std_val = NA_real_, threshold_pct = threshold_percentile,
        pixels_used = 0L, pixels_total = 0L
      ))
    }

    # Get raster values
    rast_vals <- vals[[1]]
    weights <- if ("coverage_fraction" %in% names(vals)) vals$coverage_fraction else rep(1, length(rast_vals))

    # Remove NA values
    valid_idx <- !is.na(rast_vals) & !is.na(weights)
    rast_vals <- rast_vals[valid_idx]
    weights <- weights[valid_idx]
    pixels_total <- length(rast_vals)

    if (pixels_total == 0) {
      return(data.frame(
        mean_val = NA_real_, min_val = NA_real_, max_val = NA_real_,
        std_val = NA_real_, threshold_pct = threshold_percentile,
        pixels_used = 0L, pixels_total = 0L
      ))
    }

    # Apply threshold filtering
    if (threshold_percentile > 0 && threshold_percentile <= 50) {
      threshold_val <- stats::quantile(rast_vals, probs = threshold_percentile / 100, na.rm = TRUE)
      keep_idx <- rast_vals >= threshold_val
      rast_vals <- rast_vals[keep_idx]
      weights <- weights[keep_idx]
    }

    pixels_used <- length(rast_vals)

    if (pixels_used == 0) {
      return(data.frame(
        mean_val = NA_real_, min_val = NA_real_, max_val = NA_real_,
        std_val = NA_real_, threshold_pct = threshold_percentile,
        pixels_used = 0L, pixels_total = pixels_total
      ))
    }

    # Calculate weighted statistics
    mean_val <- stats::weighted.mean(rast_vals, weights, na.rm = TRUE)
    min_val <- min(rast_vals, na.rm = TRUE)
    max_val <- max(rast_vals, na.rm = TRUE)
    std_val <- if (pixels_used > 1) {
      sqrt(stats::weighted.mean((rast_vals - mean_val)^2, weights, na.rm = TRUE))
    } else 0

    data.frame(
      mean_val = mean_val, min_val = min_val, max_val = max_val,
      std_val = std_val, threshold_pct = threshold_percentile,
      pixels_used = pixels_used, pixels_total = pixels_total
    )
  })

  do.call(rbind, results)
}

#' Recalculate Statistics from Saved Rasters
#'
#' Queries all saved raster blobs for a farm from DuckDB and recalculates
#' zonal statistics using a new percentile threshold. Updates the
#' farm_timeseries table.
#'
#' @param con DuckDB connection
#' @param farm_id Farm identifier
#' @param polygon sf object with farm boundary
#' @param threshold_pct New threshold percentile (0-50)
#' @return data.frame with updated statistics
#' @keywords internal
wapor_recalculate_stats_from_rasters <- function(con, farm_id, polygon, threshold_pct = 5) {
  if (is.null(con) || is.null(polygon)) return(NULL)

  # Read metadata only. Legacy BLOBs are fetched one row at a time below.
  rasters <- DBI::dbGetQuery(con, "
    SELECT variable, date_key, raster_path
    FROM monitoring_rasters
    ORDER BY variable, date_key
  ")
  legacy_mode <- FALSE
  if (nrow(rasters) == 0) {
    rasters <- DBI::dbGetQuery(con,
      "SELECT variable, date_key FROM farm_rasters WHERE farm_id = ? ORDER BY variable, date_key",
      params = list(farm_id))
    legacy_mode <- TRUE
    if (nrow(rasters) == 0) {
      message("No rasters found for farm_id=", farm_id)
      return(NULL)
    }
  }

  # Process one raster at a time. Prefer the file-backed COG; only retrieve a
  # legacy BLOB for the current row when no usable raster_path exists.
  updated_stats <- lapply(seq_len(nrow(rasters)), function(i) {
    row <- rasters[i, ]
    raster <- NULL
    if (!legacy_mode && "raster_path" %in% names(row) &&
        is.character(row$raster_path) && nzchar(row$raster_path) &&
        file.exists(row$raster_path)) {
      raster <- tryCatch(terra::rast(row$raster_path), error = function(e) NULL)
    }
    if (is.null(raster)) {
      blob_row <- if (legacy_mode) row else DBI::dbGetQuery(
        con,
        "SELECT raster_blob FROM monitoring_rasters WHERE variable = ? AND date_key = ?",
        params = list(row$variable, as.character(row$date_key))
      )
      if (nrow(blob_row) == 0L) return(NULL)
      raster <- wapor_raster_from_blob(blob_row$raster_blob[[1]])
    }
    if (is.null(raster)) return(NULL)

    # DYNAMIC CLIP: Clip global raster to individual farm polygon
    tryCatch({
      # Get farm extent
      f_bb <- sf::st_bbox(polygon)
      f_ext <- terra::ext(as.numeric(f_bb$xmin), as.numeric(f_bb$xmax), 
                         as.numeric(f_bb$ymin), as.numeric(f_bb$ymax))
      
      # Crop global raster to farm extent
      r_farm <- terra::crop(raster, f_ext)
      
      stats <- wapor_enhanced_zonal_stats(r_farm, polygon, threshold_pct)
      data.frame(
        farm_id = farm_id, variable = row$variable,
        date_key = as.Date(row$date_key), stats,
        stringsAsFactors = FALSE
      )
    }, error = function(e) NULL)
  })

  all_stats <- do.call(rbind, updated_stats[!sapply(updated_stats, is.null)])
  if (is.null(all_stats) || nrow(all_stats) == 0) return(NULL)

  # Update database
  update_sql <- "
    UPDATE farm_timeseries
    SET mean_val = ?, min_val = ?, max_val = ?, std_val = ?,
        threshold_pct = ?, pixels_used = ?, pixels_total = ?,
        updated_at = current_timestamp
    WHERE farm_id = ? AND variable = ? AND start_date = ?
  "

  for (i in seq_len(nrow(all_stats))) {
    row <- all_stats[i, ]
    DBI::dbExecute(con, update_sql, params = list(
      row$mean_val, row$min_val, row$max_val, row$std_val,
      row$threshold_pct, row$pixels_used, row$pixels_total,
      row$farm_id, row$variable, as.character(row$date_key)
    ))
  }

  message(sprintf("Recalculated %d records for %s with %s%% threshold",
                  nrow(all_stats), farm_id, threshold_pct))

  return(all_stats)
}

#' Generate seasonal aggregate raster from DuckDB dekadal blobs
#' 
#' @param con DuckDB connection
#' @param farm_id Farm identifier
#' @param farm_geom sf object for the farm
#' @param variable WaPOR variable
#' @param start_date Seasonal start date
#' @param end_date Seasonal end date
#' @return terra SpatRaster aggregate or NULL
#' @export
wapor_generate_seasonal_raster <- function(con, farm_id, farm_geom, variable, start_date, end_date) {
  if (is.null(con) || is.null(farm_id)) return(NULL)
  
  # Query all dekadal rasters in range
  query <- "
    SELECT date_key, raster_blob
    FROM monitoring_rasters
    WHERE variable = ?
      AND date_key >= ? AND date_key <= ?
    ORDER BY date_key
  "
  
  df <- DBI::dbGetQuery(con, query, params = list(
    variable, 
    as.character(start_date), 
    as.character(end_date)
  ))
  
  if (nrow(df) == 0) {
    # Fallback to legacy
    df <- DBI::dbGetQuery(con, 
      "SELECT date_key, raster_blob FROM farm_rasters WHERE farm_id = ? AND variable = ? AND date_key >= ? AND date_key <= ? ORDER BY date_key",
      params = list(farm_id, variable, as.character(start_date), as.character(end_date)))
    
    if (nrow(df) == 0) return(NULL)
  }
  
  # Collect rasters
  # DYNAMIC CLIP: Each global raster must be clipped to the farm geom
  f_bb <- sf::st_bbox(farm_geom)
  f_ext <- terra::ext(as.numeric(f_bb$xmin), as.numeric(f_bb$xmax), 
                     as.numeric(f_bb$ymin), as.numeric(f_bb$ymax))

  r_list <- lapply(seq_len(nrow(df)), function(i) {
    r_global <- wapor_raster_from_blob(df$raster_blob[[i]])
    if (is.null(r_global)) return(NULL)
    terra::crop(r_global, f_ext)
  })
  r_list <- r_list[!sapply(r_list, is.null)]
  if (length(r_list) == 0) return(NULL)
  
  # Stack rasters
  s <- terra::rast(r_list)
  
  # Determine aggregation method
  is_flux <- grepl("AETI|PCP|NPP|^-T-|^E-", variable, ignore.case = TRUE)
  
  if (is_flux) {
    res <- terra::app(s, fun = "sum", na.rm = TRUE)
  } else {
    res <- terra::app(s, fun = "mean", na.rm = TRUE)
  }
  
  return(res)
}

#' Apply Seasonal Adaptive Mask and Recalculate Stats
#'
#' Creates a spatial mask based on the total seasonal sum of a reference variable
#' (e.g., L3-AETI-D or L3-NPP-D). Pixels that fall below a certain percentile
#' of the total seasonal sum are considered "bare" or "non-cultivated" for that
#' specific season and are excluded from the statistics of all variables.
#'
#' @param con DuckDB connection
#' @param farm_id Farm identifier
#' @param polygon sf object with farm boundary
#' @param start_date Start of the season
#' @param end_date End of the season
#' @param mask_variable Variable to use for creating the mask (default "L3-AETI-D")
#' @param percentile_threshold Percentile of the seasonal sum to use as the cutoff (default 50)
#' @return data.frame with updated statistics
#' @export
wapor_apply_seasonal_mask_recalc <- function(con, farm_id, polygon, 
                                            start_date, end_date, 
                                            mask_variable = "L3-AETI-D", 
                                            percentile_threshold = 50) {
  if (is.null(con) || is.null(polygon)) return(NULL)

  # 1. Generate the Seasonal Sum Raster for the mask_variable
  query_mask <- "
    SELECT date_key, raster_blob
    FROM monitoring_rasters
    WHERE variable = ?
      AND date_key >= ? AND date_key <= ?
  "
  mask_df <- DBI::dbGetQuery(con, query_mask, params = list(
    mask_variable, as.character(start_date), as.character(end_date)
  ))

  if (nrow(mask_df) == 0) {
    # Fallback to legacy
    mask_df <- DBI::dbGetQuery(con, 
      "SELECT date_key, raster_blob FROM farm_rasters WHERE farm_id = ? AND variable = ? AND date_key >= ? AND date_key <= ?",
      params = list(farm_id, mask_variable, as.character(start_date), as.character(end_date)))
    
    if (nrow(mask_df) == 0) {
      message(sprintf("  [SKIP] No rasters found for mask_variable %s in season %s to %s", 
                      mask_variable, start_date, end_date))
      return(NULL)
    }
  }

  # Accumulate the seasonal sum
  r_list <- lapply(mask_df$raster_blob, wapor_raster_from_blob)
  
  # DYNAMIC CLIP for the seasonal sum base
  f_bb <- sf::st_bbox(polygon)
  f_ext <- terra::ext(as.numeric(f_bb$xmin), as.numeric(f_bb$xmax), 
                     as.numeric(f_bb$ymin), as.numeric(f_bb$ymax))
  
  r_list_clipped <- lapply(r_list, function(r) terra::crop(r, f_ext))
  seasonal_sum <- terra::app(terra::rast(r_list_clipped), "sum", na.rm = TRUE)
  
  # 2. Create the Binary Mask
  # Get all pixel values within the polygon from the seasonal sum
  sum_vals <- exactextractr::exact_extract(seasonal_sum, polygon)[[1]]
  sum_vals_clean <- sum_vals[[1]][!is.na(sum_vals[[1]])]
  
  if (length(sum_vals_clean) == 0) return(NULL)
  
  # Determine threshold from seasonal sum distribution
  cutoff <- stats::quantile(sum_vals_clean, probs = percentile_threshold / 100, na.rm = TRUE)
  
  # Create a binary mask (1 = keep, 0 = mask out)
  seasonal_mask <- seasonal_sum >= cutoff
  
  message(sprintf("  Created seasonal mask for %s using %s: Cutoff = %.1f (kept %d%% pixels)", 
                  farm_id, mask_variable, cutoff, 100 - percentile_threshold))

  # 3. Apply mask to ALL variables in this season
  # Get all variables available in this range
  query_vars <- "
    SELECT DISTINCT variable
    FROM monitoring_rasters
    WHERE date_key >= ? AND date_key <= ?
  "
  vars_in_season <- DBI::dbGetQuery(con, query_vars, params = list(
    as.character(start_date), as.character(end_date)
  ))$variable
  
  if (length(vars_in_season) == 0) {
    # Fallback
    vars_in_season <- DBI::dbGetQuery(con, 
      "SELECT DISTINCT variable FROM farm_rasters WHERE farm_id = ? AND date_key >= ? AND date_key <= ?",
      params = list(farm_id, as.character(start_date), as.character(end_date)))$variable
  }

  updated_results <- list()

  for (var in vars_in_season) {
    # Get all dates for this variable
    query_data <- "
      SELECT date_key, raster_blob
      FROM monitoring_rasters
      WHERE variable = ?
        AND date_key >= ? AND date_key <= ?
    "
    data_df <- DBI::dbGetQuery(con, query_data, params = list(
      var, as.character(start_date), as.character(end_date)
    ))
    
    if (nrow(data_df) == 0) {
      data_df <- DBI::dbGetQuery(con, 
        "SELECT date_key, raster_blob FROM farm_rasters WHERE farm_id = ? AND variable = ? AND date_key >= ? AND date_key <= ?",
        params = list(farm_id, var, as.character(start_date), as.character(end_date)))
    }

    for (i in seq_len(nrow(data_df))) {
      r_global <- wapor_raster_from_blob(data_df$raster_blob[[i]])
      if (is.null(r_global)) next
      
      # DYNAMIC CLIP
      r_dekad <- terra::crop(r_global, f_ext)
      
      # Harmonize mask to dekad resolution if different
      mask_h <- terra::resample(seasonal_mask, r_dekad, method = "near")
      
      # Apply mask
      r_masked <- terra::mask(r_dekad, mask_h, maskvalues = 0)
      
      # Calculate stats on masked raster
      stats <- wapor_enhanced_zonal_stats(r_masked, polygon, threshold_percentile = 0)
      
      res <- data.frame(
        farm_id = farm_id, variable = var,
        date_key = as.Date(data_df$date_key[i]), 
        stats,
        stringsAsFactors = FALSE
      )
      res$threshold_pct <- -percentile_threshold 
      updated_results[[length(updated_results) + 1]] <- res
    }
  }

  all_updated <- do.call(rbind, updated_results)
  if (is.null(all_updated)) return(NULL)

  # 4. Update Database
  update_sql <- "
    UPDATE farm_timeseries
    SET mean_val = ?, min_val = ?, max_val = ?, std_val = ?,
        threshold_pct = ?, pixels_used = ?, pixels_total = ?,
        updated_at = current_timestamp
    WHERE farm_id = ? AND variable = ? AND start_date = ?
  "

  for (i in seq_len(nrow(all_updated))) {
    row <- all_updated[i, ]
    DBI::dbExecute(con, update_sql, params = list(
      row$mean_val, row$min_val, row$max_val, row$std_val,
      row$threshold_pct, row$pixels_used, row$pixels_total,
      row$farm_id, row$variable, as.character(row$date_key)
    ))
  }

  message(sprintf("  Successfully updated %d dekads for %s using seasonal mask.", 
                  nrow(all_updated), farm_id))
  
  return(all_updated)
}
