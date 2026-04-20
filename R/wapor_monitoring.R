#' Initialize a DuckDB database for farm monitoring
#'
#' @param con DuckDB connection object.
#' @return The connection object (invisibly).
#' @export
wapor_init_monitoring_db <- function(con) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("Package 'duckdb' is required for monitoring databases.")
  }

  # 1. Farm Time Series
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS farm_timeseries (
      farm_id       TEXT,
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
      PRIMARY KEY (farm_id, variable, start_date)
    )
  ")
  
  # Ensure units column exists for legacy databases
  tryCatch(DBI::dbExecute(con, "ALTER TABLE farm_timeseries ADD COLUMN IF NOT EXISTS units TEXT"), error = function(e) NULL)

  # 2. Farm Rasters (Blobs)
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
  
  # Ensure resolution and unit columns exist for legacy databases
  tryCatch(DBI::dbExecute(con, "ALTER TABLE farm_rasters ADD COLUMN IF NOT EXISTS resolution_x DOUBLE"), error = function(e) NULL)
  tryCatch(DBI::dbExecute(con, "ALTER TABLE farm_rasters ADD COLUMN IF NOT EXISTS resolution_y DOUBLE"), error = function(e) NULL)
  tryCatch(DBI::dbExecute(con, "ALTER TABLE farm_rasters ADD COLUMN IF NOT EXISTS units TEXT"), error = function(e) NULL)
  tryCatch(DBI::dbExecute(con, "ALTER TABLE farm_rasters ADD COLUMN IF NOT EXISTS crs_epsg INTEGER DEFAULT 4326"), error = function(e) NULL)

  # 3. Farm Polygons (Geometries)
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

  # 4. Seasonal Aggregated Rasters
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

  # 5. Monitoring Logs
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

  # 6. Indexes
  tryCatch(DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ts_farm_var ON farm_timeseries(farm_id, variable)"), error = function(e) NULL)
  tryCatch(DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_rast_farm_var ON farm_rasters(farm_id, variable)"), error = function(e) NULL)

  invisible(con)
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

  run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
  run_start <- Sys.time()
  total_new_ts <- 0L

  # Ensure database is initialized
  wapor_init_monitoring_db(con)

  # Loop through variables
  for (var in variables) {
    log_fn(sprintf("Monitoring variable: %s", var))

    # 1. Fetch Time Series (Incremental)
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
      
      ts_df <- tryCatch({
        Rwapor::wapor_ts(
          region          = farms_sf,
          variable        = var,
          period          = c(effective_start, period[2]),
          identifier      = "farm_id",
          unit_conversion = if (grepl("-D$", var)) "dekad" else "none",
          l3_region       = if (grepl("^L3-", var)) l3_region else NULL,
          batching        = TRUE
        )
      }, error = function(e) {
        log_fn(sprintf("  Error in wapor_ts for %s: %s", var, e$message))
        NULL
      })

      if (!is.null(ts_df) && nrow(ts_df) > 0) {
        # Determine units
        var_units <- tryCatch({
          m <- Rwapor::wapor_variable_metadata(var)
          raw_u <- m$units %||% ""
          if (grepl("-D$", var) && grepl("/day$", raw_u)) sub("/day$", "/dekad", raw_u) else raw_u
        }, error = function(e) NA_character_)

        # Prepare for insertion
        insert_df <- data.frame(
          farm_id     = as.character(ts_df$farm_id),
          crop_type   = if ("crop_type" %in% names(ts_df)) as.character(ts_df$crop_type) else NA_character_,
          sowing_date = as.Date(period[1]),
          variable    = var,
          start_date  = as.Date(ts_df$start_date),
          end_date    = as.Date(ts_df$end_date),
          mean_val    = as.numeric(ts_df$mean),
          min_val     = if ("min" %in% names(ts_df)) as.numeric(ts_df$min) else NA_real_,
          max_val     = if ("max" %in% names(ts_df)) as.numeric(ts_df$max) else NA_real_,
          units       = var_units,
          stringsAsFactors = FALSE
        )
        
        duckdb::dbWriteTable(con, "farm_timeseries", insert_df, append = TRUE)
        total_new_ts <- total_new_ts + nrow(insert_df)
        log_fn(sprintf("  Saved %d new TS records.", nrow(insert_df)))
      }
    }

    # 2. Save Raster Blobs
    if (save_rasters) {
      log_fn(sprintf("  Processing raster blobs for %s...", var))
      wapor_save_raster_blobs(con, farms_sf, var, period, log_fn, l3_region)
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

#' Save clipped WaPOR raster blobs to a monitoring database
#'
#' @param con DuckDB connection.
#' @param farms_sf sf object with farm polygons.
#' @param variable WaPOR variable code.
#' @param period Date range c(start, end).
#' @param log_fn Function for logging.
#' @param l3_region Optional L3 region code.
#' @return NULL (invisibly).
#' @export
wapor_save_raster_blobs <- function(con, farms_sf, variable, period, log_fn = message, l3_region = NULL) {
  if (!requireNamespace("duckdb", quietly = TRUE)) return(invisible(NULL))

  tryCatch({
    # Determine target unit conversion (defaulting to dekad for -D variables)
    unit_conv <- if (grepl("-D$", variable)) "dekad" else "none"

    # Look up variable units from package metadata
    var_units <- tryCatch({
      m <- Rwapor::wapor_variable_metadata(variable)
      raw_u <- m$units %||% NA_character_
      if (unit_conv == "dekad" && grepl("/day$", raw_u)) {
        sub("/day$", "/dekad", raw_u)
      } else {
        raw_u
      }
    }, error = function(e) NA_character_)

    # Build bounding-box AOI
    bb      <- sf::st_bbox(sf::st_union(farms_sf))
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

    urls_vs <- paste0("/vsicurl/", urls)
    log_fn(sprintf("  Clipping & saving %d raster layers for %s...", length(urls_vs), variable))

    # Query already-saved dates per farm
    farm_ids <- as.character(farms_sf$farm_id)
    existing_by_farm <- stats::setNames(
      lapply(farm_ids, function(fid) {
        tryCatch(
          DBI::dbGetQuery(con,
            "SELECT CAST(date_key AS VARCHAR) AS dk FROM farm_rasters WHERE farm_id = ? AND variable = ?",
            params = list(fid, variable)
          )$dk,
          error = function(e) character(0)
        )
      }),
      farm_ids
    )

    n_ok   <- 0L
    n_skip <- 0L

    for (i in seq_along(urls_vs)) {
      # Load layer
      r_full <- tryCatch(
        suppressWarnings(terra::rast(urls_vs[i])),
        error = function(e) {
          log_fn(sprintf("  Error loading layer %d: %s", i, e$message))
          NULL
        }
      )
      if (is.null(r_full)) { n_skip <- n_skip + 1L; next }

      # CRS
      if (is.na(terra::crs(r_full)) || !nzchar(terra::crs(r_full))) {
        terra::crs(r_full) <- "EPSG:4326"
      }

      is_projected <- !isTRUE(terra::is.lonlat(r_full))
      if (is_projected) {
        aoi_vect_proj <- tryCatch({
          aoi_sf_tmp <- sf::st_as_sfc(sf::st_bbox(
            c(xmin = as.numeric(aoi_ext$xmin), ymin = as.numeric(aoi_ext$ymin),
              xmax = as.numeric(aoi_ext$xmax), ymax = as.numeric(aoi_ext$ymax)),
            crs = sf::st_crs(4326L)))
          terra::project(suppressWarnings(terra::vect(aoi_sf_tmp)),
                         terra::crs(r_full))
        }, error = function(e) NULL)
        if (is.null(aoi_vect_proj)) { n_skip <- n_skip + 1L; next }
        check_ext <- terra::ext(aoi_vect_proj)
      } else {
        check_ext <- aoi_ext
      }

      # Extent check
      r_ext <- terra::ext(r_full)
      if (check_ext$xmin >= r_ext$xmax || check_ext$xmax <= r_ext$xmin ||
          check_ext$ymin >= r_ext$ymax || check_ext$ymax <= r_ext$ymin) {
        n_skip <- n_skip + 1L; next
      }

      # Crop & Process
      r_full <- terra::crop(r_full, check_ext)
      r_full <- Rwapor::wapor_convert_raster(r_full, variable, urls[i], unit_conv)
      r_full <- Rwapor::wapor_convert_temperature(r_full, variable)

      if (is_projected) {
        r_full <- tryCatch({
          wgs84_ext <- terra::ext(as.numeric(aoi_ext$xmin), as.numeric(aoi_ext$xmax),
                                  as.numeric(aoi_ext$ymin), as.numeric(aoi_ext$ymax))
          # Build template for projection
          wgs84_template <- terra::rast(ext = wgs84_ext, res = 0.0001) # Approx resolution
          terra::crs(wgs84_template) <- "EPSG:4326"
          terra::project(r_full, wgs84_template)
        }, error = function(e) NULL)
        if (is.null(r_full)) { n_skip <- n_skip + 1L; next }
      }

      res_xy <- terra::res(r_full)
      
      # Date Key extraction
      fname    <- basename(urls[i])
      date_key <- tryCatch({
        di <- Rwapor::wapor_date_info(urls[i], sub(".*-([A-Z])$", "\\1", variable))
        di$start_date
      }, error = function(e) {
         # Fallback regex
         m <- regmatches(fname, regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}", fname))
         if (length(m) > 0) m[1] else format(Sys.Date(), "%Y-%m-%d")
      })

      # Clip per farm
      for (j in seq_len(nrow(farms_sf))) {
        fid   <- farm_ids[j]
        if (date_key %in% existing_by_farm[[fid]]) next

        farm_bb  <- sf::st_bbox(farms_sf[j, ])
        farm_ext <- terra::ext(as.numeric(farm_bb["xmin"]), as.numeric(farm_bb["xmax"]),
                               as.numeric(farm_bb["ymin"]), as.numeric(farm_bb["ymax"]))

        tryCatch({
          r_farm <- terra::crop(r_full, farm_ext)
          
          # Internal save to DB (we should expose this or keep it in mod_monitoring helper)
          # For the package function, we'll implement a standalone save_blob helper.
          .package_save_raster_to_db(con, fid, variable, date_key, r_farm, res_xy[1], res_xy[2], var_units)
        }, error = function(e) NULL)
      }
      n_ok <- n_ok + 1L
    }
    log_fn(sprintf("  Processed %d layers for %d farms.", n_ok, nrow(farms_sf)))

  }, error = function(e) {
    log_fn(sprintf("  wapor_save_raster_blobs error: %s", e$message))
  })
  invisible(NULL)
}

# Internal helper for DuckDB raster blobs (mirrors monitoring_helpers.R)
.package_save_raster_to_db <- function(con, farm_id, variable, date_key, raster,
                                       res_x, res_y, units) {
  temp_file <- tempfile(fileext = ".tif")
  on.exit(unlink(temp_file))
  terra::writeRaster(raster, temp_file, overwrite = TRUE, gdal = c("COMPRESS=LZW"))
  raster_blob <- readBin(temp_file, "raw", n = file.info(temp_file)$size)
  ext <- terra::ext(raster)
  dims <- dim(raster)
  
  insert_sql <- "
    INSERT INTO farm_rasters (
      farm_id, variable, date_key, raster_blob,
      xmin, xmax, ymin, ymax, nrow, ncol,
      resolution_x, resolution_y, units, crs_epsg
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (farm_id, variable, date_key)
    DO UPDATE SET
      raster_blob  = EXCLUDED.raster_blob,
      xmin         = EXCLUDED.xmin,
      xmax         = EXCLUDED.xmax,
      ymin         = EXCLUDED.ymin,
      ymax         = EXCLUDED.ymax,
      nrow         = EXCLUDED.nrow,
      ncol         = EXCLUDED.ncol,
      resolution_x = EXCLUDED.resolution_x,
      resolution_y = EXCLUDED.resolution_y,
      units        = EXCLUDED.units,
      crs_epsg     = EXCLUDED.crs_epsg
  "
  DBI::dbExecute(con, insert_sql, params = list(
    farm_id, variable, as.character(date_key), list(raster_blob),
    ext$xmin, ext$xmax, ext$ymin, ext$ymax, dims[1], dims[2],
    res_x, res_y, units, 4326L
  ))
}
