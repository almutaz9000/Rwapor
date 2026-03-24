#' Extract Time Series with Zonal Statistics
#'
#' Downloads WaPOR or AgERA5 raster data and extracts time series of zonal
#' statistics (mean, min, max) for specified polygons or regions.
#'
#' @param region Region definition. One of:
#'   * Path to a vector file (shapefile, GeoJSON, GeoPackage) containing polygons
#'   * L3 region code (3 uppercase letters, e.g., "AWA")
#'   * Numeric bounding box: `c(xmin, ymin, xmax, ymax)` in WGS84
#' @param variable Character. Variable name following WaPOR/AgERA5 naming
#'   convention (e.g., "L1-AETI-D", "L2-NPP-M", "AGERA5-ET0-E").
#' @param period Character vector of length 2. Date range as
#'   `c(start_date, end_date)` in "YYYY-MM-DD" format.
#' @param identifier Character. Optional column name in vector file to identify
#'   polygons in output. If NULL, numeric IDs are used.
#' @param unit_conversion Character. Target temporal unit for conversion.
#'   One of: "none", "day", "dekad", "month", "year".
#'   Default is NULL, which dynamically sets the default based on variable type:
#'   * "dekad" for Dekadal variables (files end in "D" but contain daily rates)
#'   * "none" for others
#' @param seasonal Logical. If `TRUE`, calculates a single seasonal aggregate
#'   (sum/mean) for each polygon over the entire period. Default is `FALSE`.
#' @param download_locally Logical. Deprecated and ignored. Data are streamed
#'   with `/vsicurl/`. Kept for backward compatibility.
#' @param parallel Logical. If `TRUE`, attempts to use `future.apply` for parallel processing
#'   within or across batches. Default is `FALSE`.
#' @param batching Logical. If `TRUE` (default), processes data in chunks of `batch_size`.
#'   If `FALSE`, loads all layers at once.
#' @param batch_size Integer. Number of remote raster layers loaded and processed
#'   per batch. Lower values reduce peak memory usage for long time series.
#'   Default is `12L` (~4 months of dekadal data).
#'
#' @return A data.frame with columns:
#'   * `mean`, `min`, `max`: Zonal statistics for each polygon/time step
#'   * `start_date`, `end_date`: Date range for each time step
#'   * `number_of_days`: Number of days in the time step
#'   * `ID` or custom identifier: Polygon identifier
#'   * `layer_index`: Index of the raster layer
#'
#'   The data.frame also has attributes:
#'   * `units`: The unit of measurement (possibly converted)
#'   * `long_name`: Full variable name
#'   * `original_units`: Original units before conversion (if converted)
#'
#' @details
#' The function uses `exactextractr::exact_extract()` for accurate zonal
#' statistics that properly handle partial pixel coverage at polygon boundaries.
#'
#' @export
#'
#' @importFrom terra rast crop extract global nlyr vect
#' @importFrom dplyr bind_rows mutate group_by summarize left_join
#' @importFrom purrr map_dfr
#' @importFrom sf st_drop_geometry st_crs st_transform st_as_sf
#' @importFrom exactextractr exact_extract
#' @importFrom future.apply future_lapply
#' @importFrom utils tail
#'
#' @examples
#' \dontrun{
#' # Extract time series for a bounding box
#' # For dekadal variables, defaults to mm/dekad (unit_conversion="dekad")
#' df <- wapor_ts(
#'   region = c(35.0, 33.0, 36.0, 34.0),
#'   variable = "L1-AETI-D",
#'   period = c("2023-01-01", "2023-03-31")
#' )
#'
#' # Extract with explicit daily units
#' df <- wapor_ts(
#'   region = "fields.geojson",
#'   variable = "L1-AETI-D",
#'   period = c("2023-01-01", "2023-12-31"),
#'   identifier = "field_name",
#'   unit_conversion = "day"
#' )
#'
#' # Parallel extraction for memory efficiency
#' library(future)
#' plan(multisession)
#' df <- wapor_ts(
#'   region = c(35.0, 33.0, 36.0, 34.0),
#'   variable = "L1-AETI-D",
#'   period = c("2023-01-01", "2023-12-31"),
#'   parallel = TRUE,
#'   batching = TRUE,
#'   batch_size = 3
#' )
#'
#' # Check units
#' attr(df, "units")
#' attr(df, "long_name")
#' }
wapor_ts <- function(region, variable, period, identifier = NULL, unit_conversion = NULL, seasonal = FALSE, download_locally = FALSE, parallel = FALSE, batching = TRUE, batch_size = 12L) {
  # Input validation
  if (!is.character(variable) || length(variable) != 1) {
    stop("'variable' must be a single character string", call. = FALSE)
  }
  if (!is.character(period) || length(period) != 2) {
    stop("'period' must be a character vector of length 2: c(start_date, end_date)", call. = FALSE)
  }
  if (!is.logical(download_locally) || length(download_locally) != 1) {
    stop("'download_locally' must be a single logical value", call. = FALSE)
  }
  if (isTRUE(download_locally)) {
    warning("'download_locally' is deprecated and ignored; data are streamed with /vsicurl/.", call. = FALSE)
  }
  if (!is.logical(batching) || length(batching) != 1) {
    stop("'batching' must be a single logical value", call. = FALSE)
  }
  if (!is.numeric(batch_size) || length(batch_size) != 1 || is.na(batch_size) || batch_size < 1) {
    stop("'batch_size' must be a positive integer", call. = FALSE)
  }
  batch_size <- as.integer(batch_size)
  
  # Determine default unit_conversion if NULL
  if (is.null(unit_conversion)) {
    if (grepl("-D$", variable)) {
      unit_conversion <- "dekad"
      message("Variable is Dekadal (stored as mm/day). Defaulting unit_conversion to 'dekad' (mm/dekad).")
    } else {
      unit_conversion <- "none"
    }
  }

  valid_conversions <- c("none", "day", "dekad", "month", "year")
  if (!unit_conversion %in% valid_conversions) {
    stop(
      sprintf("'unit_conversion' must be one of: %s", paste(valid_conversions, collapse = ", ")),
      call. = FALSE
    )
  }

  # Parse region
  reg_info <- parse_region(region)
  l3_code <- if (reg_info$type == "l3_code") reg_info$value else NULL

  if (is.null(l3_code) && grepl("^L3-", variable)) {
    guessed_codes <- guess_l3_region(variable, reg_info, period)
    if (is.null(guessed_codes)) {
        stop("Region does not intersect with any available WaPOR L3 data for this variable.", call. = FALSE)
    }
    l3_code <- guessed_codes[1]
    if (length(guessed_codes) > 1) {
        warning(sprintf("Region intersects multiple L3 areas (%s). Only extracting data from %s. To extract from others, supply their codes directly.", paste(guessed_codes, collapse=", "), l3_code), call. = FALSE)
    }
  }

  # --- Seasonal mode ---
  if (seasonal) {
    if (!is.null(unit_conversion) && unit_conversion != "none") {
      message("Note: 'unit_conversion' is ignored when seasonal = TRUE. The output is in base physical units (e.g., mm).")
    }
    aggregation_rule <- get_seasonal_aggregation_rule(variable)

    # Prepare region geometry for zonal stats
    vect_data <- NULL
    if (reg_info$type == "vector") {
      vect_data <- reg_info$value
      vect_crs <- sf::st_crs(vect_data)
      if (!is.na(vect_crs) && vect_crs$epsg != 4326) {
        vect_data <- sf::st_transform(vect_data, 4326)
      }
    }

    # Determine number of zones
    if (!is.null(vect_data)) {
      n_zones <- nrow(vect_data)
      zone_ids <- if (!is.null(identifier) && identifier %in% names(vect_data)) {
        sf::st_drop_geometry(vect_data)[[identifier]]
      } else {
        seq_len(n_zones)
      }
    } else {
      n_zones <- 1L
      zone_ids <- 1L
    }

    # Call helper. Use tempdir for intermediate raster download.
    temp_download_folder <- file.path(tempdir(), "wapor_seasonal_ts")
    if (!dir.exists(temp_download_folder)) dir.create(temp_download_folder)
    
    seasonal_data <- download_seasonal_rasters(variable, period, l3_code, reg_info, temp_download_folder)
    
    groups <- seasonal_data$groups
    plan <- seasonal_data$plan
    aggregation_rule <- seasonal_data$aggregation_rule %||% aggregation_rule
    
    # Accumulate seasonal contributions and, when needed, mean denominators.
    sum_values <- rep(0, n_zones)
    total_weights <- if (identical(aggregation_rule, "weighted_mean")) rep(0, n_zones) else NULL
    
    for (g_name in names(groups)) {
      g <- groups[[g_name]]
      r_group <- g$raster
      multipliers <- g$multipliers
      
      # Process each raster layer in this group
      if (parallel) {
        w_r_group <- terra::wrap(r_group)
        layer_sums <- future.apply::future_lapply(seq_len(terra::nlyr(r_group)), function(i) {
          r_group_worker <- terra::unwrap(w_r_group)
          multiplier <- multipliers[i]
          
          if (!is.null(vect_data)) {
            layer_means <- suppressWarnings(exactextractr::exact_extract(
              r_group_worker[[i]], sf::st_as_sf(terra::vect(vect_data)), "mean", progress = FALSE
            ))
            return(layer_means * multiplier)
          } else {
            global_mean <- terra::global(r_group_worker[[i]], fun = "mean", na.rm = TRUE)$mean
            return(global_mean * multiplier)
          }
        }, future.seed = TRUE)
      } else {
        layer_sums <- lapply(seq_len(terra::nlyr(r_group)), function(i) {
          multiplier <- multipliers[i]
          
          if (!is.null(vect_data)) {
            layer_means <- suppressWarnings(exactextractr::exact_extract(
              r_group[[i]], sf::st_as_sf(terra::vect(vect_data)), "mean", progress = FALSE
            ))
            return(layer_means * multiplier)
          } else {
            global_mean <- terra::global(r_group[[i]], fun = "mean", na.rm = TRUE)$mean
            return(global_mean * multiplier)
          }
        })
      }
      
      # Sum the parallel results into the main aggregator
      for (i in seq_along(layer_sums)) {
        sum_values <- sum_values + layer_sums[[i]]
        if (!is.null(total_weights)) {
          if (!is.null(vect_data)) {
            coverage <- suppressWarnings(exactextractr::exact_extract(
              !is.na(r_group[[i]]), sf::st_as_sf(terra::vect(vect_data)), "mean", progress = FALSE
            ))
            total_weights <- total_weights + (coverage * multipliers[i])
          } else {
            has_data <- !is.na(terra::global(r_group[[i]], fun = "mean", na.rm = TRUE)$mean)
            total_weights <- total_weights + if (isTRUE(has_data)) multipliers[i] else 0
          }
        }
      }
    }

    seasonal_values <- if (is.null(total_weights)) {
      sum_values
    } else {
      ifelse(total_weights > 0, sum_values / total_weights, NA_real_)
    }
    value_name <- if (identical(aggregation_rule, "weighted_mean")) "seasonal_mean" else "seasonal_sum"
    
    # Build result data.frame
    result_df <- data.frame(
      start_date = period[1],
      end_date = period[2],
      n_rasters = nrow(plan),
      ID = zone_ids,
      stringsAsFactors = FALSE
    )
    result_df[[value_name]] <- seasonal_values
    
    # Add custom identifier column if specified
    if (!is.null(identifier) && !is.null(vect_data) && identifier %in% names(vect_data)) {
      result_df[[identifier]] <- zone_ids
    }

    # Determine final units from seasonal aggregation semantics.
    source_var_meta <- get_variable_metadata(variable)
    if (!is.null(source_var_meta)) {
      attr(result_df, "units") <- get_seasonal_output_units(variable, aggregation_rule) %||% source_var_meta$units
      attr(result_df, "long_name") <- source_var_meta$long_name
    } else {
      attr(result_df, "units") <- "unknown"
    }
    attr(result_df, "plan") <- plan
    attr(result_df, "aggregation_rule") <- aggregation_rule

    return(result_df)
  }

  # Get URLs
  urls <- wapor_generate_urls(variable, l3_region = l3_code, period = period)
  if (length(urls) == 0) {
    stop("No data found for the specified variable and period.", call. = FALSE)
  }

  # Use GDAL virtual file system for efficient streaming
  urls <- ifelse(grepl("^/vsicurl/", urls), urls, paste0("/vsicurl/", urls))
  message("Streaming data using GDAL virtual file system (/vsicurl/)...")

  message(sprintf("Found %d files. Processing...", length(urls)))
  t0_ts <- proc.time()

  # Extract temporal resolution from variable name
  parts <- strsplit(variable, "-")[[1]]
  tres <- tail(parts, 1)

  # Gather metadata for all layers
  meta_list <- lapply(urls, function(u) get_date_info(u, tres))
  meta_df <- do.call(rbind, lapply(meta_list, as.data.frame))
  meta_df$layer_index <- seq_len(nrow(meta_df))

  # Determine region type

  vect <- if (reg_info$type == "vector") reg_info$value else NULL

  # Extract polygon identifiers once
  ids <- NULL
  if (!is.null(vect)) {
    ids <- if (!is.null(identifier) && identifier %in% names(vect)) {
      vect[[identifier]]
    } else {
      seq_len(nrow(vect))
    }
  }

  # Split URLs into batches for memory-efficient processing
  n_urls <- length(urls)
  url_idx_chunks <- get_url_chunks(seq_len(n_urls), batching = batching, batch_size = batch_size)
  n_chunks <- length(url_idx_chunks)

  if (n_chunks > 1) {
    message(sprintf("  Splitting %d files into %d batch(es) of ~%d for memory efficiency.",
                    n_urls, n_chunks, batch_size))
  }

  # Helper function to process a single batch
  process_batch <- function(ci) {
    idx <- url_idx_chunks[[ci]]
    chunk_urls <- urls[idx]
    chunk_meta <- meta_df[idx, , drop = FALSE]

    if (n_chunks > 1 && !parallel) {
      message(sprintf("  Batch %d/%d (%d layers)...", ci, n_chunks, length(idx)))
    }

    # Load raster batch with retry logic
    r <- NULL
    max_retries <- 3
    for (attempt in seq_len(max_retries)) {
      r <- tryCatch({
        suppressWarnings(terra::rast(chunk_urls))
      }, error = function(e) {
        if (attempt < max_retries) {
          if (!parallel) {
            message(sprintf("Attempt %d to load raster failed. Retrying in %d seconds... (%s)",
                          attempt, attempt * 2, e$message))
          }
          Sys.sleep(attempt * 2)
          return(NULL)
        } else {
          stop(sprintf("Failed to load raster data after %d attempts: %s", max_retries, e$message), call. = FALSE)
        }
      })
      if (!is.null(r)) break
    }

    # Crop to region
    r <- crop_to_region(r, reg_info, do_mask = FALSE)

    if (!is.null(vect)) {
      # Zonal statistics for polygons using exactextractr
      names(r) <- paste0("L", seq_len(terra::nlyr(r)))
      n_lyr <- terra::nlyr(r)

      ex <- suppressWarnings(exactextractr::exact_extract(
        r,
        vect,
        c("mean", "min", "max"),
        progress = FALSE
      ))

      ex$ID <- seq_len(nrow(ex))

      # Reshape extracted stats into long format
      # If processing batches in parallel, we don't further parallelize within a batch
      # to avoid nested parallelism overhead.
      inner_apply_fn <- if (parallel) lapply else (if (isTRUE(getOption("wapor.parallel_inner", FALSE))) future.apply::future_lapply else lapply)
      
      out_list <- inner_apply_fn(seq_len(n_lyr), function(i) {
        lyr_name <- paste0("L", i)

        col_mean <- paste0("mean.", lyr_name)
        col_min <- paste0("min.", lyr_name)
        col_max <- paste0("max.", lyr_name)

        if (!col_mean %in% names(ex)) {
          if (paste0(lyr_name, ".mean") %in% names(ex)) {
            col_mean <- paste0(lyr_name, ".mean")
            col_min <- paste0(lyr_name, ".min")
            col_max <- paste0(lyr_name, ".max")
          } else if (n_lyr == 1 && "mean" %in% names(ex)) {
            col_mean <- "mean"
            col_min <- "min"
            col_max <- "max"
          } else {
            stop(sprintf("Could not find expected columns for layer %d. Available: %s",
                         i, paste(names(ex), collapse = ", ")), call. = FALSE)
          }
        }

        cols <- c(col_mean, col_min, col_max)
        sub_df <- ex[, cols, drop = FALSE]
        colnames(sub_df) <- c("mean", "min", "max")

        sub_df$ID <- ids[ex$ID]
        
        # Add custom identifier column if specified
        if (!is.null(identifier) && identifier %in% names(vect)) {
          sub_df[[identifier]] <- ids[ex$ID]
        }

        m <- chunk_meta[i, ]
        m_rep <- m[rep(1, nrow(sub_df)), ]
        cbind(sub_df, m_rep)
      })

      return(do.call(rbind, out_list))
    } else {
      # Global statistics for bbox or L3 code regions
      ex <- terra::global(r, fun = c("mean", "min", "max"), na.rm = TRUE)
      ex$ID <- 1
      df_res <- cbind(chunk_meta, ex)
      df_res$region_id <- 1
      return(df_res)
    }
  }

  # Process all batches: load, crop, extract stats, release memory
  if (parallel && n_chunks > 1) {
    message(sprintf("  Processing %d batches in parallel...", n_chunks))
    all_batch_results <- future.apply::future_lapply(seq_len(n_chunks), process_batch, future.seed = TRUE)
  } else {
    all_batch_results <- lapply(seq_len(n_chunks), process_batch)
  }

  message(sprintf("Raster processing completed in %.1f seconds", (proc.time() - t0_ts)[["elapsed"]]))

  final_df <- do.call(rbind, all_batch_results)

  # Get variable metadata for units
  source_var_meta <- get_variable_metadata(variable)

  if (!is.null(source_var_meta)) {
    attr(final_df, "units") <- source_var_meta$units
    attr(final_df, "long_name") <- source_var_meta$long_name
  } else {
    attr(final_df, "units") <- "unknown"
  }

  # Apply unit conversion
  final_df <- df_unit_convertor(final_df, unit_conversion)

  message(sprintf("Time series extraction completed in %.1f seconds", (proc.time() - t0_ts)[["elapsed"]]))
  return(final_df)
}
