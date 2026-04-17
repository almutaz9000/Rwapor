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
  
  # Query all dekadal rasters in range
  query <- "
    SELECT date_key, raster_blob
    FROM farm_rasters
    WHERE farm_id = ? AND variable = ?
      AND date_key >= ? AND date_key <= ?
    ORDER BY date_key
  "
  
  df <- DBI::dbGetQuery(con, query, params = list(
    farm_id, 
    variable, 
    as.character(start_date), 
    as.character(end_date)
  ))
  
  if (nrow(df) == 0) return(NULL)
  
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
  
  # Try to get extent from farm_rasters first (most accurate)
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
  
  # Get unique farms
  farms_query <- "SELECT DISTINCT farm_id FROM farm_rasters ORDER BY farm_id"
  farms <- tryCatch(
    DBI::dbGetQuery(con, farms_query)$farm_id,
    error = function(e) character(0)
  )
  
  # Get unique variables
  vars_query <- "SELECT DISTINCT variable FROM farm_rasters ORDER BY variable"
  variables <- tryCatch(
    DBI::dbGetQuery(con, vars_query)$variable,
    error = function(e) character(0)
  )
  
  # Get date range
  date_query <- "SELECT MIN(date_key) as min_date, MAX(date_key) as max_date FROM farm_rasters"
  date_df <- tryCatch(
    DBI::dbGetQuery(con, date_query),
    error = function(e) data.frame(min_date = NA, max_date = NA)
  )
  
  date_range <- NULL
  if (!is.na(date_df$min_date[1])) {
    date_range <- c(as.Date(date_df$min_date[1]), as.Date(date_df$max_date[1]))
  }
  
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
  
  # Get all rasters for this farm
  query <- "
    SELECT variable, date_key, raster_blob
    FROM farm_rasters
    WHERE farm_id = ?
    ORDER BY variable, date_key
  "
  
  rasters <- DBI::dbGetQuery(con, query, params = list(farm_id))
  
  if (nrow(rasters) == 0) {
    message("No rasters found for farm_id=", farm_id)
    return(NULL)
  }
  
  # Process each raster
  updated_stats <- lapply(seq_len(nrow(rasters)), function(i) {
    row <- rasters[i, ]
    
    # Extract raster from BLOB
    raster <- wapor_raster_from_blob(row$raster_blob[[1]])
    if (is.null(raster)) {
      return(NULL)
    }
    
    # Calculate enhanced stats with new threshold
    stats <- wapor_enhanced_zonal_stats(raster, polygon, threshold_pct)
    
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

# ── Internal: clip and save raster blobs to DuckDB ────────────────────────────
#
# Downloads WaPOR rasters for a variable/period, clips each dekadal layer per
# farm polygon, and stores them as compressed BLOBs in farm_rasters.
# Also records resolution (degrees/pixel), variable units, and CRS.
# Incremental: (farm, variable, date) triples already in the DB are skipped.
#
.save_raster_blobs <- function(con, farms_sf, variable, period, add_log_fn, l3_region = NULL) {
  if (!requireNamespace("duckdb", quietly = TRUE)) return(invisible(NULL))

  tryCatch({
    # Look up variable units from package metadata (raw, as stored in the GeoTIFF)
    var_units <- tryCatch({
      m <- Rwapor::wapor_variable_metadata(variable)
      m$units %||% NA_character_
    }, error = function(e) NA_character_)

    # Build bounding-box AOI from the union of all farm polygons
    bb      <- sf::st_bbox(sf::st_union(farms_sf))
    aoi_ext <- terra::ext(bb["xmin"], bb["xmax"], bb["ymin"], bb["ymax"])

    urls <- tryCatch(
      Rwapor::wapor_generate_urls(
        variable,
        l3_region = if (grepl("^L3-", variable)) l3_region else NULL,
        period    = period
      ),
      error = function(e) { add_log_fn(sprintf("  Raster URLs error: %s", e$message)); NULL }
    )
    if (is.null(urls) || length(urls) == 0) return(invisible(NULL))

    urls_vs <- paste0("/vsicurl/", urls)
    add_log_fn(sprintf("  Clipping & saving %d raster layers for %s...", length(urls_vs), variable))

    # Query already-saved dates per farm (enables incremental updates)
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

    # Upsert farm_metadata once per farm (outside the heavy raster loop)
    for (j in seq_len(nrow(farms_sf))) {
      fid   <- farm_ids[j]
      fgeom <- farms_sf[j, ]
      tryCatch({
        if (nrow(DBI::dbGetQuery(con, "SELECT farm_id FROM farm_metadata WHERE farm_id = ?",
                                 params = list(fid))) == 0L) {
          DBI::dbExecute(con, "INSERT INTO farm_metadata (farm_id) VALUES (?)", params = list(fid))
        }
        wapor_update_farm_metadata(con, fid, fgeom)
      }, error = function(e) {
        add_log_fn(sprintf("  Warning: metadata update failed for %s: %s", fid, e$message))
      })
    }

    n_ok      <- 0L
    n_skip    <- 0L
    var_is_coarse <- FALSE  # updated on first successful layer load

    for (i in seq_along(urls_vs)) {

      # Load the full-resolution layer; on failure log and continue to next URL
      r_full <- tryCatch(
        suppressWarnings(terra::rast(urls_vs[i])),
        error = function(e) {
          add_log_fn(sprintf("  Error loading layer %d: %s", i, e$message))
          NULL
        }
      )
      if (is.null(r_full)) { n_skip <- n_skip + 1L; next }

      # Ensure CRS (vsicurl sources sometimes drop it)
      if (is.na(terra::crs(r_full)) || !nzchar(terra::crs(r_full))) {
        terra::crs(r_full) <- "EPSG:4326"
      }

      # Handle projected CRS (e.g. L3 rasters in UTM).
      # Convert the geographic AOI extent to the raster's CRS for the overlap
      # check and crop, then reproject the clipped tile back to WGS84 so all
      # stored blobs are in a consistent geographic coordinate system.
      is_projected <- !isTRUE(terra::is.lonlat(r_full))
      if (is_projected) {
        aoi_vect_proj <- tryCatch({
          aoi_sf_tmp <- sf::st_as_sfc(sf::st_bbox(
            c(xmin = as.numeric(aoi_ext$xmin), ymin = as.numeric(aoi_ext$ymin),
              xmax = as.numeric(aoi_ext$xmax), ymax = as.numeric(aoi_ext$ymax)),
            crs = sf::st_crs(4326L)))
          terra::project(suppressWarnings(terra::vect(aoi_sf_tmp)),
                         terra::crs(r_full))
        }, error = function(e) {
          add_log_fn(sprintf("  Warning: AOI reprojection failed for layer %d: %s", i, e$message))
          NULL
        })
        if (is.null(aoi_vect_proj)) { n_skip <- n_skip + 1L; next }
        check_ext <- terra::ext(aoi_vect_proj)
      } else {
        check_ext <- aoi_ext
      }

      # Skip layer if it does not overlap the combined farm AOI
      r_ext <- terra::ext(r_full)
      if (check_ext$xmin >= r_ext$xmax || check_ext$xmax <= r_ext$xmin ||
          check_ext$ymin >= r_ext$ymax || check_ext$ymax <= r_ext$ymin) {
        add_log_fn(sprintf("  Skipped layer %d: AOI outside raster extent", i))
        n_skip <- n_skip + 1L
        next
      }

      # Crop to AOI to reduce memory before per-farm loops
      r_full <- tryCatch(
        terra::crop(r_full, check_ext),
        error = function(e) {
          add_log_fn(sprintf("  Error cropping layer %d to AOI: %s", i, e$message))
          NULL
        }
      )
      if (is.null(r_full)) { n_skip <- n_skip + 1L; next }

      # Re-project to WGS84 if the raster was in a projected CRS.
      # Supply an explicit template so terra can determine the output extent
      # even for small cropped tiles.
      if (is_projected) {
        r_full <- tryCatch({
          # Estimate output resolution: UTM metres → approximate degrees
          utm_res_m  <- mean(terra::res(r_full))
          farm_lat   <- mean(c(as.numeric(aoi_ext$ymin), as.numeric(aoi_ext$ymax)))
          deg_per_m  <- 1 / (111320 * cos(farm_lat * pi / 180))
          approx_deg <- max(utm_res_m * deg_per_m, 1e-5)

          # Build template in two steps (terra::rast crs= arg unreliable in 1.9)
          wgs84_ext <- terra::ext(
            as.numeric(aoi_ext$xmin), as.numeric(aoi_ext$xmax),
            as.numeric(aoi_ext$ymin), as.numeric(aoi_ext$ymax)
          )
          wgs84_template <- terra::rast(ext = wgs84_ext, res = approx_deg)
          terra::crs(wgs84_template) <- "EPSG:4326"

          terra::project(r_full, wgs84_template)
        }, error = function(e) {
          add_log_fn(sprintf("  Error projecting layer %d to WGS84: %s", i, e$message))
          NULL
        })
        if (is.null(r_full)) { n_skip <- n_skip + 1L; next }
      }

      # Capture resolution after cropping
      res_xy <- terra::res(r_full)

      # Detect coarse-resolution variables (e.g. L1-RET-D ~30km, L1-PCP-D ~5km).
      # When a single pixel is larger than ~1km (0.009°), one pixel can cover the
      # entire farm polygon, so there is no benefit in cropping per farm.
      # We save the same AOI-wide raster blob for every farm instead.
      is_coarse     <- max(res_xy) > 0.009  # ~1 km threshold in degrees
      var_is_coarse <- var_is_coarse || is_coarse

      # Extract date key from the URL filename.
      # WaPOR uses YYYY-MM-Dn (D1=1st, D2=11th, D3=21st) or plain YYYY-MM-DD.
      fname    <- basename(urls[i])
      date_key <- {
        m1 <- regmatches(fname, regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}", fname))
        if (length(m1) > 0 && nzchar(m1)) {
          m1
        } else {
          m2 <- regmatches(fname, regexpr("[0-9]{4}-[0-9]{2}-D[123]", fname))
          if (length(m2) > 0 && nzchar(m2)) {
            parts <- strsplit(m2, "-")[[1]]
            dkday <- c("01", "11", "21")[as.integer(sub("D", "", parts[3]))]
            paste(parts[1], parts[2], dkday, sep = "-")
          } else {
            format(Sys.Date() - (length(urls_vs) - i) * 10L, "%Y-%m-%d")
          }
        }
      }

      if (is_coarse) {
        # ── Coarse-resolution path ───────────────────────────────────────────
        # Save the same AOI-cropped raster for every farm (no per-farm crop).
        # This prevents N redundant downloads/crops for RET, PCP, etc.
        for (j in seq_len(nrow(farms_sf))) {
          fid <- farm_ids[j]
          if (date_key %in% existing_by_farm[[fid]]) next
          tryCatch({
            wapor_save_raster_to_db(
              con, fid, variable, date_key, r_full,
              resolution_x = res_xy[1],
              resolution_y = res_xy[2],
              units        = var_units
            )
          }, error = function(e) {
            add_log_fn(sprintf("    Skipped farm %s layer %d (%s): %s", fid, i, date_key, e$message))
          })
        }
      } else {
        # ── Fine-resolution path (default) ───────────────────────────────────
        # Clip and save per farm
        for (j in seq_len(nrow(farms_sf))) {
          fid   <- farm_ids[j]
          fgeom <- farms_sf[j, ]

          # Skip if already saved
          if (date_key %in% existing_by_farm[[fid]]) next

          farm_bb  <- sf::st_bbox(fgeom)
          farm_ext <- terra::ext(
            as.numeric(farm_bb["xmin"]), as.numeric(farm_bb["xmax"]),
            as.numeric(farm_bb["ymin"]), as.numeric(farm_bb["ymax"])
          )

          # Skip farm if its bbox does not overlap the (AOI-cropped) layer
          r_ext2 <- terra::ext(r_full)
          if (farm_ext$xmin >= r_ext2$xmax || farm_ext$xmax <= r_ext2$xmin ||
              farm_ext$ymin >= r_ext2$ymax || farm_ext$ymax <= r_ext2$ymin) next

          tryCatch({
            r_farm <- terra::crop(r_full, farm_ext)
            wapor_save_raster_to_db(
              con, fid, variable, date_key, r_farm,
              resolution_x = res_xy[1],
              resolution_y = res_xy[2],
              units        = var_units
            )
          }, error = function(e) {
            add_log_fn(sprintf("    Skipped farm %s layer %d (%s): %s", fid, i, date_key, e$message))
          })
        }
      }

      n_ok <- n_ok + 1L
    }

    coarse_note <- if (var_is_coarse) " [coarse res \u2013 AOI raster shared across farms]" else ""
    add_log_fn(sprintf("  \u2713 %d/%d layers processed for %d farm(s) (%d skipped)%s",
                       n_ok, length(urls_vs), nrow(farms_sf), n_skip, coarse_note))

  }, error = function(e) {
    add_log_fn(sprintf("  .save_raster_blobs error: %s", e$message))
  })
  invisible(NULL)
}

# ── Raster grid (spatial) time-series plot ────────────────────────────────────
#
# Loads saved raster BLOBs from the farm_rasters table and produces a
# faceted grid of spatial maps – one panel per time step.  This shows the
# actual pixel distribution across the farm extent rather than a scalar
# line chart.
#
# @param con       DuckDB connection (read-only is fine)
# @param farm_id   Farm identifier string
# @param variable  WaPOR variable name
# @param max_panels Maximum number of time steps to show (default 16).
#                   Earlier panels are sampled when more layers are stored.
# @param date_range Optional c(start_date, end_date) to filter layers.
# @param palette    Name of the colour palette: "viridis", "magma",
#                   "RdYlGn", "RdYlBu", or "Spectral". Default "viridis".
# @return A ggplot object (requires ggplot2 + tidyterra), or NULL on error.
wapor_plot_raster_grid <- function(con, farm_id, variable,
                                   max_panels = 16L,
                                   date_range = NULL,
                                   palette    = "viridis") {
  if (is.null(con) || is.null(farm_id) || is.null(variable)) return(NULL)

  if (!requireNamespace("ggplot2",   quietly = TRUE)) {
    message("ggplot2 package required for wapor_plot_raster_grid")
    return(NULL)
  }
  if (!requireNamespace("tidyterra", quietly = TRUE)) {
    message("tidyterra package required for wapor_plot_raster_grid; install with install.packages('tidyterra')")
    return(NULL)
  }

  # ── 1. Fetch raster BLOBs ────────────────────────────────────────────────
  query <- "
    SELECT CAST(date_key AS VARCHAR) AS date_key, raster_blob
    FROM farm_rasters
    WHERE farm_id = ? AND variable = ?
    ORDER BY date_key
  "
  params <- list(farm_id, variable)

  if (!is.null(date_range) && length(date_range) == 2) {
    query <- "
      SELECT CAST(date_key AS VARCHAR) AS date_key, raster_blob
      FROM farm_rasters
      WHERE farm_id = ? AND variable = ?
        AND date_key >= ? AND date_key <= ?
      ORDER BY date_key
    "
    params <- list(farm_id, variable,
                   as.character(date_range[1]),
                   as.character(date_range[2]))
  }

  df <- tryCatch(
    DBI::dbGetQuery(con, query, params = params),
    error = function(e) {
      message("wapor_plot_raster_grid DB error: ", e$message)
      NULL
    }
  )

  if (is.null(df) || nrow(df) == 0) {
    message("No raster data found for farm=", farm_id, " variable=", variable)
    return(NULL)
  }

  # ── 2. Sub-sample if too many panels ────────────────────────────────────
  n_layers <- nrow(df)
  if (n_layers > max_panels) {
    idx <- round(seq(1, n_layers, length.out = max_panels))
    df  <- df[idx, , drop = FALSE]
  }

  # ── 3. Read rasters and build a named SpatRaster stack ──────────────────
  r_list <- vector("list", nrow(df))
  valid  <- logical(nrow(df))
  for (k in seq_len(nrow(df))) {
    r_k <- tryCatch(
      wapor_raster_from_blob(df$raster_blob[[k]]),
      error = function(e) NULL
    )
    if (!is.null(r_k) && terra::nlyr(r_k) > 0) {
      r_list[[k]] <- r_k
      valid[k]    <- TRUE
    }
  }

  r_list  <- r_list[valid]
  df_valid <- df[valid, , drop = FALSE]

  if (length(r_list) == 0) {
    message("All raster BLOBs failed to decode for farm=", farm_id)
    return(NULL)
  }

  # Align all rasters to a common extent/resolution using the first layer
  # as template (required for terra::rast(list)).
  template <- r_list[[1]]
  r_aligned <- lapply(r_list, function(r) {
    if (!isTRUE(all.equal(terra::ext(r), terra::ext(template))) ||
        !isTRUE(all.equal(terra::res(r), terra::res(template)))) {
      tryCatch(terra::resample(r, template, method = "bilinear"),
               error = function(e) r)
    } else {
      r
    }
  })

  # Stack and assign meaningful layer names (the date strings)
  r_stack <- tryCatch(
    terra::rast(r_aligned),
    error = function(e) {
      message("Could not stack rasters: ", e$message)
      NULL
    }
  )
  if (is.null(r_stack)) return(NULL)

  # Name each layer by its date for facet labels
  date_labels <- df_valid$date_key
  names(r_stack) <- date_labels

  # ── 4. Build colour scale ────────────────────────────────────────────────
  pal_colors <- switch(palette,
    "magma"    = c("#000004", "#3b0f70", "#8c2981", "#de4968", "#fe9f6d", "#fcfdbf"),
    "RdYlGn"   = grDevices::colorRampPalette(c("#d73027","#f46d43","#fdae61",
                                                "#fee08b","#d9ef8b","#a6d96a",
                                                "#66bd63","#1a9850"))(50),
    "RdYlBu"   = grDevices::colorRampPalette(c("#d73027","#f46d43","#fdae61",
                                                "#fee090","#e0f3f8","#abd9e9",
                                                "#74add1","#4575b4"))(50),
    "Spectral"  = grDevices::colorRampPalette(c("#9e0142","#d53e4f","#f46d43",
                                                 "#fdae61","#fee08b","#ffffbf",
                                                 "#e6f598","#abdda4","#66c2a5",
                                                 "#3288bd","#5e4fa2"))(50),
    # default: viridis
    c("#440154","#31688e","#35b779","#fde725")
  )

  # ── 5. Build ggplot with faceted spatial rasters ─────────────────────────
  ncol_grid <- min(4L, ceiling(sqrt(terra::nlyr(r_stack))))

  # Determine global value range for a consistent colour scale
  all_vals <- terra::values(r_stack, na.rm = TRUE)
  val_range <- if (length(all_vals) > 0 && !all(is.na(all_vals))) {
    range(all_vals, na.rm = TRUE)
  } else {
    c(0, 1)
  }

  p <- ggplot2::ggplot() +
    tidyterra::geom_spatraster(data = r_stack, na.rm = TRUE) +
    ggplot2::facet_wrap(~lyr, ncol = ncol_grid) +
    ggplot2::scale_fill_gradientn(
      colours  = pal_colors,
      limits   = val_range,
      na.value = "transparent",
      name     = variable
    ) +
    ggplot2::labs(
      title    = sprintf("Raster Time Series  —  Farm: %s  |  Variable: %s", farm_id, variable),
      subtitle = sprintf("%d time steps shown (earliest → latest)", terra::nlyr(r_stack)),
      x = "Longitude", y = "Latitude"
    ) +
    ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(
      plot.title      = ggplot2::element_text(face = "bold", size = 12),
      strip.text      = ggplot2::element_text(face = "bold", size = 8),
      axis.text       = ggplot2::element_text(size = 6),
      legend.key.height = ggplot2::unit(1.5, "cm"),
      panel.border    = ggplot2::element_rect(colour = "grey70", fill = NA, linewidth = 0.3)
    )

  p
}
