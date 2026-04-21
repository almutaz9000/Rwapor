# monitoring_helpers.R
# Helper functions for enhanced farm monitoring module

# Null-coalescing operator (if not already defined by the Shiny runtime)
if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b
}

#' Calculate enhanced zonal statistics from raster
#' 
#' @param raster terra SpatRaster object
#' @param polygon sf object with farm boundaries
#' @param threshold_percentile Percentile threshold (0-50) to filter low values
#' @return data.frame with mean, min, max, std, p05, p95, pixels_used, pixels_total
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
        mean_val = NA_real_,
        min_val = NA_real_,
        max_val = NA_real_,
        std_val = NA_real_,
        p05_val = NA_real_,
        p95_val = NA_real_,
        threshold_pct = threshold_percentile,
        pixels_used = 0L,
        pixels_total = 0L
      ))
    }
    
    # Get raster values (first column is the value, 'coverage_fraction' is weights)
    rast_vals <- vals[[1]]  # First column contains raster values
    weights <- if ("coverage_fraction" %in% names(vals)) vals$coverage_fraction else rep(1, length(rast_vals))
    
    # Remove NA values
    valid_idx <- !is.na(rast_vals) & !is.na(weights)
    rast_vals <- rast_vals[valid_idx]
    weights <- weights[valid_idx]
    
    pixels_total <- length(rast_vals)
    
    if (pixels_total == 0) {
      return(data.frame(
        mean_val = NA_real_,
        min_val = NA_real_,
        max_val = NA_real_,
        std_val = NA_real_,
        p05_val = NA_real_,
        p95_val = NA_real_,
        threshold_pct = threshold_percentile,
        pixels_used = 0L,
        pixels_total = 0L
      ))
    }
    
    # Apply threshold filtering if specified
    if (threshold_percentile > 0 && threshold_percentile <= 50) {
      threshold_val <- stats::quantile(rast_vals, probs = threshold_percentile / 100, na.rm = TRUE)
      keep_idx <- rast_vals >= threshold_val
      rast_vals <- rast_vals[keep_idx]
      weights <- weights[keep_idx]
    }
    
    pixels_used <- length(rast_vals)
    
    if (pixels_used == 0) {
      return(data.frame(
        mean_val = NA_real_,
        min_val = NA_real_,
        max_val = NA_real_,
        std_val = NA_real_,
        p05_val = NA_real_,
        p95_val = NA_real_,
        threshold_pct = threshold_percentile,
        pixels_used = 0L,
        pixels_total = pixels_total
      ))
    }
    
    # Calculate weighted statistics
    mean_val <- stats::weighted.mean(rast_vals, weights, na.rm = TRUE)
    min_val <- min(rast_vals, na.rm = TRUE)
    max_val <- max(rast_vals, na.rm = TRUE)
    
    # Weighted standard deviation
    if (pixels_used > 1) {
      variance <- stats::weighted.mean((rast_vals - mean_val)^2, weights, na.rm = TRUE)
      std_val <- sqrt(variance)
    } else {
      std_val <- 0
    }
    
    # Percentiles
    p05_val <- stats::quantile(rast_vals, probs = 0.05, na.rm = TRUE)
    p95_val <- stats::quantile(rast_vals, probs = 0.95, na.rm = TRUE)
    
    data.frame(
      mean_val = mean_val,
      min_val = min_val,
      max_val = max_val,
      std_val = std_val,
      p05_val = as.numeric(p05_val),
      p95_val = as.numeric(p95_val),
      threshold_pct = threshold_percentile,
      pixels_used = pixels_used,
      pixels_total = pixels_total
    )
  })
  
  do.call(rbind, results)
}

#' Extract raster from DuckDB BLOB
#' 
#' @param blob_data Raw vector containing raster BLOB
#' @return terra SpatRaster object
wapor_raster_from_blob <- function(blob_data) {
  if (is.null(blob_data) || length(blob_data) == 0) {
    return(NULL)
  }
  
  temp_file <- tempfile(fileext = ".tif")
  writeBin(blob_data, temp_file)
  r <- terra::rast(temp_file)
  # Keep file until R session ends (terra reads lazily)
  return(r)
}

#' Save raster to DuckDB with metadata
#'
#' @param con DuckDB connection
#' @param farm_id Farm identifier
#' @param variable WaPOR variable name
#' @param date_key Date of the raster
#' @param raster terra SpatRaster object
#' @param resolution_x Pixel width in degrees (optional, derived from raster if NULL)
#' @param resolution_y Pixel height in degrees (optional, derived from raster if NULL)
#' @param units Variable units string (optional)
#' @return Number of rows inserted/updated (should be 1)
wapor_save_raster_to_db <- function(con, farm_id, variable, date_key, raster,
                                    resolution_x = NULL, resolution_y = NULL,
                                    units = NA_character_) {
  if (is.null(raster) || is.null(con)) {
    return(0L)
  }

  # Save raster to temporary file
  temp_file <- tempfile(fileext = ".tif")
  on.exit(unlink(temp_file), add = TRUE)

  terra::writeRaster(raster, temp_file, overwrite = TRUE, gdal = c("COMPRESS=LZW"))

  # Read as BLOB
  raster_blob <- readBin(temp_file, "raw", n = file.info(temp_file)$size)

  # Get extent and dimensions
  ext  <- terra::ext(raster)
  dims <- dim(raster)

  # Resolution: derive from raster if not supplied
  if (is.null(resolution_x) || is.null(resolution_y)) {
    res_xy       <- terra::res(raster)
    resolution_x <- res_xy[1]
    resolution_y <- res_xy[2]
  }

  # CRS EPSG code (best-effort)
  crs_epsg <- tryCatch({
    epsg <- terra::crs(raster, describe = TRUE)$code
    if (!is.null(epsg) && !is.na(epsg) && nzchar(epsg)) as.integer(epsg) else 4326L
  }, error = function(e) 4326L)

  # Insert into database (upsert)
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
    farm_id,
    variable,
    as.character(date_key),
    list(raster_blob),
    ext$xmin,
    ext$xmax,
    ext$ymin,
    ext$ymax,
    dims[1],       # nrow
    dims[2],       # ncol
    resolution_x,
    resolution_y,
    as.character(units %||% NA_character_),
    crs_epsg
  ))
}

#' Save seasonal aggregate raster to DuckDB
#' 
#' @param con DuckDB connection
#' @param farm_id Farm identifier
#' @param variable WaPOR variable name
#' @param season_id Identifier for the season (e.g. "2023_MAIN")
#' @param raster terra SpatRaster aggregate object
#' @return Number of rows inserted
wapor_save_seasonal_raster_to_db <- function(con, farm_id, variable, season_id, raster) {
  if (is.null(raster) || is.null(con)) {
    return(0L)
  }
  
  # Save raster to temporary file
  temp_file <- tempfile(fileext = ".tif")
  on.exit(unlink(temp_file), add = TRUE)
  
  terra::writeRaster(raster, temp_file, overwrite = TRUE, gdal = c("COMPRESS=LZW"))
  
  # Read as BLOB
  raster_blob <- readBin(temp_file, "raw", n = file.info(temp_file)$size)
  
  # Get extent and dimensions
  ext <- terra::ext(raster)
  dims <- dim(raster)
  
  # Insert into database
  insert_sql <- "
    INSERT INTO farm_seasonal_rasters (farm_id, variable, season_id, raster_blob, xmin, xmax, ymin, ymax, nrow, ncol)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (farm_id, variable, season_id) 
    DO UPDATE SET 
      raster_blob = EXCLUDED.raster_blob,
      xmin = EXCLUDED.xmin,
      xmax = EXCLUDED.xmax,
      ymin = EXCLUDED.ymin,
      ymax = EXCLUDED.ymax,
      nrow = EXCLUDED.nrow,
      ncol = EXCLUDED.ncol
  "
  
  DBI::dbExecute(con, insert_sql, params = list(
    farm_id,
    variable,
    as.character(season_id),
    list(raster_blob),
    ext$xmin,
    ext$xmax,
    ext$ymin,
    ext$ymax,
    dims[1],  # nrow
    dims[2]   # ncol
  ))
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
wapor_generate_seasonal_raster <- function(con, farm_id, farm_geom, variable, start_date, end_date) {
  if (is.null(con) || is.null(farm_id)) return(NULL)
  
  # 1. Query all dekadal rasters in range from GLOBAL table
  query_global <- "
    SELECT date_key, raster_blob
    FROM monitoring_rasters
    WHERE variable = ?
      AND date_key >= ? AND date_key <= ?
    ORDER BY date_key
  "
  
  df <- DBI::dbGetQuery(con, query_global, params = list(
    variable, 
    as.character(start_date), 
    as.character(end_date)
  ))
  
  if (nrow(df) == 0) {
    # 2. Fallback to LEGACY table
    query_legacy <- "
      SELECT date_key, raster_blob
      FROM farm_rasters
      WHERE farm_id = ? AND variable = ?
        AND date_key >= ? AND date_key <= ?
      ORDER BY date_key
    "
    df <- DBI::dbGetQuery(con, query_legacy, params = list(
      farm_id, variable, as.character(start_date), as.character(end_date)
    ))
    
    if (nrow(df) == 0) return(NULL)
  }
  
  # DYNAMIC CLIP: Each raster must be clipped to the farm geom
  f_bb <- sf::st_bbox(farm_geom)
  f_ext <- terra::ext(as.numeric(f_bb$xmin), as.numeric(f_bb$xmax), 
                     as.numeric(f_bb$ymin), as.numeric(f_bb$ymax))

  r_list <- lapply(seq_len(nrow(df)), function(i) {
    r_full <- wapor_raster_from_blob(df$raster_blob[[i]])
    if (is.null(r_full)) return(NULL)
    terra::crop(r_full, f_ext)
  })
  r_list <- r_list[!sapply(r_list, is.null)]
  if (length(r_list) == 0) return(NULL)
  
  # Collect rasters
  r_list <- lapply(seq_len(nrow(df)), function(i) {
    wapor_raster_from_blob(df$raster_blob[[i]])
  })
  
  # Stack rasters
  # Important: they might have slightly different extents if grid shifted?
  # But here they are clipped to the same farm_geom extent in theory.
  # Let's check for overlap and align.
  s <- terra::rast(r_list)
  
  # Determine aggregation method
  # Sum for flux/consumption: AETI, PCP, NPP, T, E
  # Mean for state/indices: RET, RSM, ETa/ETp
  is_flux <- grepl("AETI|PCP|NPP|^-T-|^E-", variable, ignore.case = TRUE)
  
  if (is_flux) {
    res <- terra::app(s, fun = "sum", na.rm = TRUE)
  } else {
    res <- terra::app(s, fun = "mean", na.rm = TRUE)
  }
  
  return(res)
}

#' Get combined extent of all farms from database
#' 
#' @param con DuckDB connection
#' @return Numeric vector c(xmin, xmax, ymin, ymax) or NULL
wapor_get_farms_extent <- function(con) {
  if (is.null(con)) return(NULL)
  
  # 1. Try to get extent from monitoring_metadata (Best)
  meta_q <- "SELECT xmin, xmax, ymin, ymax FROM monitoring_metadata LIMIT 1"
  extent_df <- tryCatch(DBI::dbGetQuery(con, meta_q), error = function(e) NULL)
  
  if (!is.null(extent_df) && nrow(extent_df) > 0 && !is.na(extent_df$xmin[1])) {
    return(c(xmin = extent_df$xmin[1], xmax = extent_df$xmax[1], 
             ymin = extent_df$ymin[1], ymax = extent_df$ymax[1]))
  }

  # 2. Try to get extent from monitoring_rasters
  rast_q <- "SELECT MIN(xmin) as xmin, MAX(xmax) as xmax, MIN(ymin) as ymin, MAX(ymax) as ymax FROM monitoring_rasters"
  extent_df <- tryCatch(DBI::dbGetQuery(con, rast_q), error = function(e) NULL)
  
  if (!is.null(extent_df) && nrow(extent_df) > 0 && !is.na(extent_df$xmin[1])) {
    return(c(xmin = extent_df$xmin[1], xmax = extent_df$xmax[1], 
             ymin = extent_df$ymin[1], ymax = extent_df$ymax[1]))
  }
  
  # 3. Fallback to farm_rasters (Legacy)
  extent_query <- "
    SELECT 
      MIN(xmin) as xmin,
      MAX(xmax) as xmax,
      MIN(ymin) as ymin,
      MAX(ymax) as ymax
    FROM farm_rasters
    WHERE xmin IS NOT NULL
  "
  
  extent_df <- tryCatch(
    DBI::dbGetQuery(con, extent_query),
    error = function(e) NULL
  )
  
  if (!is.null(extent_df) && nrow(extent_df) > 0 && !is.na(extent_df$xmin[1])) {
    return(c(
      xmin = extent_df$xmin[1],
      xmax = extent_df$xmax[1],
      ymin = extent_df$ymin[1],
      ymax = extent_df$ymax[1]
    ))
  }
  
  # Fallback to farm_metadata if available
  meta_query <- "
    SELECT 
      MIN(xmin) as xmin,
      MAX(xmax) as xmax,
      MIN(ymin) as ymin,
      MAX(ymax) as ymax
    FROM farm_metadata
    WHERE xmin IS NOT NULL
  "
  
  extent_df <- tryCatch(
    DBI::dbGetQuery(con, meta_query),
    error = function(e) NULL
  )
  
  if (!is.null(extent_df) && nrow(extent_df) > 0 && !is.na(extent_df$xmin[1])) {
    return(c(
      xmin = extent_df$xmin[1],
      xmax = extent_df$xmax[1],
      ymin = extent_df$ymin[1],
      ymax = extent_df$ymax[1]
    ))
  }
  
  NULL
}

#' Update farm metadata extent and area from polygon
#' 
#' @param con DuckDB connection
#' @param farm_id Farm identifier
#' @param polygon sf object (single feature)
#' @return Number of rows updated
wapor_update_farm_metadata <- function(con, farm_id, polygon) {
  if (is.null(con) || is.null(polygon)) {
    return(0L)
  }
  
  # Get extent
  bbox <- sf::st_bbox(polygon)
  
  # Calculate area in hectares
  # Transform to equal-area projection for accurate area calculation
  polygon_aea <- sf::st_transform(polygon, crs = "+proj=aea +lat_1=20 +lat_2=60 +lat_0=40 +lon_0=0")
  area_m2 <- as.numeric(sf::st_area(polygon_aea))
  area_ha <- area_m2 / 10000
  
  update_sql <- "
    UPDATE farm_metadata
    SET 
      xmin = ?,
      xmax = ?,
      ymin = ?,
      ymax = ?,
      area_ha = ?
    WHERE farm_id = ?
  "
  
  DBI::dbExecute(con, update_sql, params = list(
    bbox$xmin,
    bbox$xmax,
    bbox$ymin,
    bbox$ymax,
    area_ha,
    farm_id
  ))
}

#' Plot raster time series for a farm
#' 
#' @param con DuckDB connection
#' @param farm_id Farm identifier
#' @param variable WaPOR variable
#' @param date_range Optional date range c(start, end)
#' @return ggplot2 object or NULL
wapor_plot_raster_timeseries <- function(con, farm_id, variable, date_range = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    message("ggplot2 package required for plotting")
    return(NULL)
  }
  
  # Query timeseries data
  query <- "
    SELECT 
      start_date as date,
      mean_val as mean,
      min_val as min,
      max_val as max,
      std_val as std,
      p05_val as p05,
      p95_val as p95,
      threshold_pct,
      pixels_used,
      pixels_total
    FROM farm_timeseries
    WHERE farm_id = ? AND variable = ?
    ORDER BY start_date
  "
  
  df <- DBI::dbGetQuery(con, query, params = list(farm_id, variable))
  
  if (nrow(df) == 0) {
    message("No data found for farm_id=", farm_id, ", variable=", variable)
    return(NULL)
  }
  
  # Convert to Date
  df$date <- as.Date(df$date)
  
  # Filter by date range if provided
  if (!is.null(date_range) && length(date_range) == 2) {
    df <- df[df$date >= date_range[1] & df$date <= date_range[2], ]
  }
  
  if (nrow(df) == 0) {
    message("No data in specified date range")
    return(NULL)
  }
  
  # Create plot
  p <- ggplot2::ggplot(df, ggplot2::aes(x = date)) +
    # Ribbon for min-max range
    ggplot2::geom_ribbon(ggplot2::aes(ymin = min, ymax = max), alpha = 0.2, fill = "lightblue") +
    # Ribbon for std deviation
    ggplot2::geom_ribbon(ggplot2::aes(ymin = mean - std, ymax = mean + std), 
                         alpha = 0.3, fill = "blue", na.rm = TRUE) +
    # Mean line
    ggplot2::geom_line(ggplot2::aes(y = mean), color = "darkblue", linewidth = 1) +
    # Points
    ggplot2::geom_point(ggplot2::aes(y = mean), color = "darkblue", size = 2) +
    # Labels
    ggplot2::labs(
      title = paste("Time Series:", farm_id, "-", variable),
      x = "Date",
      y = "Value",
      subtitle = sprintf("Blue line = mean, shaded = ±1 std, light = min-max range")
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold"),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
    )
  
  p
}

#' Get available raster data summary
#' 
#' @param con DuckDB connection
#' @return List with farms, variables, and date range
wapor_get_available_raster_data <- function(con) {
  if (is.null(con)) {
    return(list(farms = character(0), variables = character(0), date_range = NULL))
  }
  
  # Variables from both global and legacy
  variables <- tryCatch({
    v1 <- DBI::dbGetQuery(con, "SELECT DISTINCT variable FROM monitoring_rasters")$variable
    v2 <- DBI::dbGetQuery(con, "SELECT DISTINCT variable FROM farm_rasters")$variable
    sort(unique(c(v1, v2)))
  }, error = function(e) character(0))

  # Farms (always check polygons or timeseries as global table doesn't have farm_id)
  farms <- tryCatch({
    DBI::dbGetQuery(con, "SELECT DISTINCT farm_id FROM farm_polygons")$farm_id
  }, error = function(e) {
    DBI::dbGetQuery(con, "SELECT DISTINCT farm_id FROM farm_timeseries")$farm_id
  })
  
  # Date range
  date_range <- tryCatch({
    d1 <- DBI::dbGetQuery(con, "SELECT MIN(date_key) as mn, MAX(date_key) as mx FROM monitoring_rasters")
    d2 <- DBI::dbGetQuery(con, "SELECT MIN(date_key) as mn, MAX(date_key) as mx FROM farm_rasters")
    mn <- min(as.Date(c(d1$mn, d2$mn)), na.rm = TRUE)
    mx <- max(as.Date(c(d1$mx, d2$mx)), na.rm = TRUE)
    c(mn, mx)
  }, error = function(e) NULL)
  
  list(
    farms = farms,
    variables = variables,
    date_range = date_range
  )
}

#' Get available seasonal raster data summary
#' 
#' @param con DuckDB connection
#' @return List with farms, variables, and seasons
wapor_get_available_seasonal_data <- function(con) {
  if (is.null(con)) {
    return(list(farms = character(0), variables = character(0), seasons = character(0)))
  }
  
  # Get unique farms
  farms <- tryCatch(
    DBI::dbGetQuery(con, "SELECT DISTINCT farm_id FROM farm_seasonal_rasters ORDER BY farm_id")$farm_id,
    error = function(e) character(0)
  )
  
  # Get unique variables
  variables <- tryCatch(
    DBI::dbGetQuery(con, "SELECT DISTINCT variable FROM farm_seasonal_rasters ORDER BY variable")$variable,
    error = function(e) character(0)
  )
  
  # Get seasons
  seasons <- tryCatch(
    DBI::dbGetQuery(con, "SELECT DISTINCT season_id FROM farm_seasonal_rasters ORDER BY season_id")$season_id,
    error = function(e) character(0)
  )
  
  list(
    farms = farms,
    variables = variables,
    seasons = seasons
  )
}

#' Plot raster time series for multiple farms and variables
#' 
#' @param con DuckDB connection
#' @param farm_ids Vector of farm identifiers (or "all")
#' @param variables Vector of WaPOR variables
#' @param date_range Optional date range c(start, end)
#' @return ggplot2 object or NULL
wapor_plot_raster_timeseries_multi <- function(con, farm_ids, variables, date_range = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    message("ggplot2 package required for plotting")
    return(NULL)
  }
  
  # Handle "all" farms
  if (length(farm_ids) == 1 && farm_ids[1] == "all") {
    farm_ids <- DBI::dbGetQuery(con, "SELECT DISTINCT farm_id FROM farm_timeseries")$farm_id
  }
  
  # Build query with multiple farms and variables
  placeholders_farms <- paste(rep("?", length(farm_ids)), collapse = ", ")
  placeholders_vars <- paste(rep("?", length(variables)), collapse = ", ")
  
  query <- sprintf("
    SELECT 
      farm_id,
      variable,
      start_date as date,
      mean_val as mean,
      min_val as min,
      max_val as max,
      std_val as std,
      threshold_pct,
      pixels_used,
      pixels_total
    FROM farm_timeseries
    WHERE farm_id IN (%s) AND variable IN (%s)
    ORDER BY farm_id, variable, start_date
  ", placeholders_farms, placeholders_vars)
  
  df <- DBI::dbGetQuery(con, query, params = c(as.list(farm_ids), as.list(variables)))
  
  if (nrow(df) == 0) {
    message("No data found for selected farms and variables")
    return(NULL)
  }
  
  # Convert to Date
  df$date <- as.Date(df$date)
  
  # Filter by date range if provided
  if (!is.null(date_range) && length(date_range) == 2) {
    df <- df[df$date >= date_range[1] & df$date <= date_range[2], ]
  }
  
  if (nrow(df) == 0) {
    message("No data in specified date range")
    return(NULL)
  }
  
  # Add threshold info to subtitle
  threshold_info <- ""
  if (!is.null(df$threshold_pct) && !all(is.na(df$threshold_pct))) {
    avg_threshold <- mean(df$threshold_pct, na.rm = TRUE)
    if (!is.na(df$pixels_used[1])) {
      avg_pct <- mean(df$pixels_used / df$pixels_total * 100, na.rm = TRUE)
      threshold_info <- sprintf("(Avg threshold: %.1f%%, %.0f%% pixels retained)", 
                               avg_threshold, avg_pct)
    } else {
      threshold_info <- sprintf("(Threshold: %.1f%%)", avg_threshold)
    }
  }
  
  # Create faceted plot
  # Strategy: Facet by variable (rows), color by farm
  n_farms <- length(unique(df$farm_id))
  n_vars <- length(unique(df$variable))
  
  p <- ggplot2::ggplot(df, ggplot2::aes(x = date, color = farm_id, fill = farm_id, group = farm_id)) +
    # Mean line
    ggplot2::geom_line(ggplot2::aes(y = mean), linewidth = 0.8) +
    ggplot2::geom_point(ggplot2::aes(y = mean), size = 1.5, alpha = 0.7) +
    # Labels
    ggplot2::labs(
      title = sprintf("Raster Time Series: %d Farm(s) × %d Variable(s)", n_farms, n_vars),
      x = "Date",
      y = "Value",
      subtitle = paste("Mean values from clipped rasters", threshold_info),
      color = "Farm ID",
      fill = "Farm ID"
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 14),
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      legend.position = if (n_farms > 10) "none" else "right",
      strip.text = ggplot2::element_text(face = "bold")
    )
  
  # Add faceting if multiple variables
  if (n_vars > 1) {
    p <- p + ggplot2::facet_wrap(~ variable, scales = "free_y", ncol = 1)
  }
  
  # Add std ribbons only if single farm (too cluttered otherwise)
  if (n_farms == 1 && !all(is.na(df$std))) {
    p <- p + 
      ggplot2::geom_ribbon(ggplot2::aes(ymin = mean - std, ymax = mean + std), 
                           alpha = 0.2, color = NA)
  }
  
  p
}

#' Recalculate zonal statistics from saved rasters with new threshold
#' 
#' @param con DuckDB connection
#' @param farm_id Farm identifier
#' @param polygon sf object with farm boundary
#' @param threshold_pct New threshold percentile (0-50)
#' @return data.frame with updated statistics
wapor_recalculate_stats_from_rasters <- function(con, farm_id, polygon, threshold_pct = 5) {
  if (is.null(con) || is.null(polygon)) {
    return(NULL)
  }
  
  # 1. Get all GLOBAL rasters
  query_global <- "
    SELECT variable, date_key, raster_blob
    FROM monitoring_rasters
    ORDER BY variable, date_key
  "
  rasters <- DBI::dbGetQuery(con, query_global)
  
  if (nrow(rasters) == 0) {
    # 2. Fallback to LEGACY
    query_legacy <- "SELECT variable, date_key, raster_blob FROM farm_rasters WHERE farm_id = ?"
    rasters <- DBI::dbGetQuery(con, query_legacy, params = list(farm_id))
    
    if (nrow(rasters) == 0) {
      message("No rasters found for farm_id=", farm_id)
      return(NULL)
    }
  }
  
  # DYNAMIC CLIP for global rasters
  f_bb <- sf::st_bbox(polygon)
  f_ext <- terra::ext(as.numeric(f_bb$xmin), as.numeric(f_bb$xmax), 
                     as.numeric(f_bb$ymin), as.numeric(f_bb$ymax))

  # Process each raster
  updated_stats <- lapply(seq_len(nrow(rasters)), function(i) {
    row <- rasters[i, ]
    r_full <- wapor_raster_from_blob(row$raster_blob[[1]])
    if (is.null(r_full)) return(NULL)
    
    # Crop if global
    r_farm <- terra::crop(r_full, f_ext)
    
    # Calculate enhanced stats
    stats <- wapor_enhanced_zonal_stats(r_farm, polygon, threshold_pct)
    
    # Add metadata
    data.frame(
      farm_id = farm_id,
      variable = row$variable,
      date_key = as.Date(row$date_key),
      stats,
      stringsAsFactors = FALSE
    )
  })
  
  # Combine results
  all_stats <- do.call(rbind, updated_stats[!sapply(updated_stats, is.null)])
  
  if (is.null(all_stats) || nrow(all_stats) == 0) {
    return(NULL)
  }
  
  # Update database
  update_sql <- "
    UPDATE farm_timeseries
    SET 
      mean_val = ?,
      min_val = ?,
      max_val = ?,
      std_val = ?,
      p05_val = ?,
      p95_val = ?,
      threshold_pct = ?,
      pixels_used = ?,
      pixels_total = ?,
      updated_at = current_timestamp
    WHERE farm_id = ? AND variable = ? AND start_date = ?
  "
  
  for (i in seq_len(nrow(all_stats))) {
    row <- all_stats[i, ]
    DBI::dbExecute(con, update_sql, params = list(
      row$mean_val,
      row$min_val,
      row$max_val,
      row$std_val,
      row$p05_val,
      row$p95_val,
      row$threshold_pct,
      row$pixels_used,
      row$pixels_total,
      row$farm_id,
      row$variable,
      as.character(row$date_key)
    ))
  }
  
  message(sprintf("Recalculated %d records for %s with %s%% threshold",
                  nrow(all_stats), farm_id, threshold_pct))

  all_stats
}
# Functions in this file are now mostly superseded by core package functions 
# in R/wapor_monitoring.R. UI-specific helpers remain.
