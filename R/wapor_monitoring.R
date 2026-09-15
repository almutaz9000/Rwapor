#' Initialize a DuckDB database for farm monitoring
#'
#' @param con DuckDB connection object.
#' @return The connection object invisibly.
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

  # 2. Farm Rasters (Blobs) - Legacy / Per-Farm
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
  
  # 2b. Monitoring Rasters (Optimized - One per time step for the whole project)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS monitoring_rasters (
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
      PRIMARY KEY (variable, date_key)
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

  # 3b. Monitoring Metadata (Global project-level info)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS monitoring_metadata (
      key   TEXT PRIMARY KEY,
      value TEXT
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
          
          duckdb::dbWriteTable(con, "farm_timeseries", insert_df, append = TRUE)
          total_new_ts <- total_new_ts + nrow(insert_df)
          log_fn(sprintf("  Saved %d new TS records.", nrow(insert_df)))
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

#' Save clipped WaPOR raster blobs to a monitoring database
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

    urls_vs <- paste0("/vsicurl/", urls)
    log_fn(sprintf("  Clipping & saving %d global raster layers for %s...", length(urls_vs), variable))

    # Query already-saved dates in the global table
    existing_dates <- tryCatch(
      DBI::dbGetQuery(con,
        "SELECT CAST(date_key AS VARCHAR) AS dk FROM monitoring_rasters WHERE variable = ?",
        params = list(variable)
      )$dk,
      error = function(e) character(0)
    )

    n_ok   <- 0L
    n_skip <- 0L

    # Loop through layers
    for (i in seq_along(urls_vs)) {
      # Date Key extraction
      date_key <- tryCatch({
        di <- Rwapor::wapor_date_info(urls[i], sub(".*-([A-Z])$", "\\1", variable))
        as.character(di$start_date)
      }, error = function(e) {
         m <- regmatches(basename(urls[i]), regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}", basename(urls[i])))
         if (length(m) > 0) m[1] else format(Sys.Date(), "%Y-%m-%d")
      })

      if (date_key %in% existing_dates) {
        n_skip <- n_skip + 1L
        next
      }

      # Load layer header (Lazy loading via vsicurl)
      r_full <- tryCatch(
        suppressWarnings(terra::rast(urls_vs[i])),
        error = function(e) {
          log_fn(sprintf("  Error loading layer %d: %s", i, e$message))
          NULL
        }
      )
      if (is.null(r_full)) { n_skip <- n_skip + 1L; next }

      # 1. CRS HANDLING: Some variables are WGS84 (L1/L2), some are UTM (L3)
      is_projected <- !isTRUE(terra::is.lonlat(r_full))
      
      if (is_projected) {
        # Project AOI extent to Raster CRS (e.g. UTM) for safe cropping
        r_crs <- terra::crs(r_full)
        aoi_poly <- sf::st_as_sfc(sf::st_bbox(aoi_ext, crs = 4326))
        aoi_proj <- sf::st_transform(aoi_poly, r_crs)
        check_ext <- terra::ext(as.numeric(sf::st_bbox(aoi_proj)))
      } else {
        check_ext <- aoi_ext
      }

      # 2. SPATIAL CHECK: Ensure raster overlaps the AOI in its own CRS
      r_ext <- terra::ext(r_full)
      if (check_ext$xmin >= r_ext$xmax || check_ext$xmax <= r_ext$xmin ||
          check_ext$ymin >= r_ext$ymax || check_ext$ymax <= r_ext$ymin) {
        next
      }

      # 3. CHUNKED CLIPPING: terra::crop on vsicurl only downloads the pixels within the BBOX
      r_crop <- tryCatch(terra::crop(r_full, check_ext), error = function(e) NULL)
      if (is.null(r_crop)) next

      # 4. UNIT CONVERSIONS & METADATA
      r_crop <- Rwapor::wapor_convert_raster(r_crop, variable, urls[i], unit_conv)
      r_crop <- Rwapor::wapor_convert_temperature(r_crop, variable)
      r_crop <- assign_raster_metadata(r_crop, variable, unit_conv, var_units)

      # 5. RE-PROJECT TO WGS84: Store all blobs in a standard geographic CRS for the dashboard
      if (is_projected) {
        r_crop <- tryCatch({
          # Create a template in WGS84 matching our original AOI but at the same resolution
          # Approximate resolution conversion
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
      
      # Prepare compressed blob
      temp_file <- tempfile(fileext = ".tif")
      terra::writeRaster(r_crop, temp_file, overwrite = TRUE, gdal = c("COMPRESS=DEFLATE"))
      raster_blob <- readBin(temp_file, "raw", n = file.info(temp_file)$size)
      if (file.exists(temp_file)) unlink(temp_file)

      # Save to optimized global table
      tryCatch({
        .package_save_global_raster_blob_to_db(
          con, variable, date_key, raster_blob,
          ext_final$xmin, ext_final$xmax, ext_final$ymin, ext_final$ymax,
          dims[1], dims[2], res_xy[1], res_xy[2], var_units
        )
        n_ok <- n_ok + 1L
      }, error = function(e) log_fn(sprintf("  Error saving global blob: %s", e$message)))
    }
    
    log_fn(sprintf("  Processed %d global layers for variable %s.", n_ok, variable))

  }, error = function(e) {
    log_fn(sprintf("  wapor_save_raster_blobs error: %s", e$message))
  })
}

# Optimized helper for Global Raster Blobs
.package_save_global_raster_blob_to_db <- function(con, variable, date_key, raster_blob,
                                                   xmin, xmax, ymin, ymax, nrow, ncol,
                                                   res_x, res_y, units) {
  insert_sql <- "
    INSERT INTO monitoring_rasters (
      variable, date_key, raster_blob,
      xmin, xmax, ymin, ymax, nrow, ncol,
      resolution_x, resolution_y, units, crs_epsg
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (variable, date_key)
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
    variable, as.character(date_key), list(raster_blob),
    xmin, xmax, ymin, ymax, nrow, ncol,
    res_x, res_y, units, 4326L
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

  # Get all optimized global rasters
  query <- "
    SELECT variable, date_key, raster_blob
    FROM monitoring_rasters
    ORDER BY variable, date_key
  "

  rasters <- DBI::dbGetQuery(con, query)
  if (nrow(rasters) == 0) {
    # Fallback to legacy table if new table is empty
    rasters <- DBI::dbGetQuery(con, 
      "SELECT variable, date_key, raster_blob FROM farm_rasters WHERE farm_id = ?",
      params = list(farm_id))
    if (nrow(rasters) == 0) {
      message("No rasters found for farm_id=", farm_id)
      return(NULL)
    }
  }

  # Process each raster
  updated_stats <- lapply(seq_len(nrow(rasters)), function(i) {
    row <- rasters[i, ]
    raster <- wapor_raster_from_blob(row$raster_blob[[1]])
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
