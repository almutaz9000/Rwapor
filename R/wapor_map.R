#' Download and Save a Raster Map
#'
#' Downloads WaPOR or AgERA5 raster data for a specified region and time period,
#' optionally crops/masks to the region boundary, and saves as a GeoTIFF file.
#'
#' @param region Region definition. One of:
#'   * Path to a vector file (shapefile, GeoJSON, GeoPackage)
#'   * L3 region code (3 uppercase letters, e.g., "AWA")
#'   * Numeric bounding box: `c(xmin, ymin, xmax, ymax)` in WGS84
#' @param variable Character. Variable name following WaPOR/AgERA5 naming
#'   convention (e.g., "L1-AETI-D", "L2-NPP-M", "AGERA5-ET0-E").
#' @param period Character vector of length 2. Date range as
#'   `c(start_date, end_date)` in "YYYY-MM-DD" format.
#' @param folder Character. Output directory path. Will be created if needed.
#' @param filename Character. Optional output filename. If NULL, a default
#'   name is generated based on region and variable.
#' @param unit_conversion Character. Target temporal unit for conversion.
#'   One of: "none", "day", "dekad", "month", "year".
#'   Default is NULL, which dynamically sets the default based on variable type:
#'   * "dekad" for Dekadal variables (files end in "D" but contain daily rates)
#'   * "none" for others
#' @param seasonal Logical. If `TRUE`, downloads and aggregates data for the
#'   entire period into a single seasonal raster (sum/mean).
#'   Default is `FALSE`.
#' @param separate_files Logical. If `TRUE`, writes each time step as a separate
#'   GeoTIFF file instead of a multi-band stack. In seasonal mode, this saves
#'   seasonal-plan component rasters into
#'   `<folder>/<variable>_seasonal/components/`. Default is `FALSE`.
#' @param parallel Logical. If `TRUE`, attempts to use `future.apply` for parallel processing.
#'   Default is `FALSE`.
#' @param mask Logical. If `TRUE` and `region` is a vector file or polygon,
#'   the output raster is masked to the polygon boundary (pixels outside set to NA).
#'   If `FALSE` (default), only a rectangular crop to the bounding box is applied.
#'   Ignored for bounding box and L3 code regions.
#' @param batching Logical. If `TRUE` (default), processes data in chunks of `batch_size`.
#'   If `FALSE`, loads all layers at once.
#' @param batch_size Integer. Number of remote files loaded per chunk in non-seasonal mode.
#'   Lower values reduce memory pressure for long periods. Default is `12L`.
#'
#' @return Character path to the output GeoTIFF file, or in seasonal mode with
#'   `separate_files = TRUE`, a list with `seasonal_aggregate` and
#'   `seasonal_components`.
#'
#' @details
#' The function performs the following steps:
#' 1. Generates download URLs for the specified variable and period
#' 2. Streams raster data using GDAL virtual file system (/vsicurl/)
#' 3. Crops to bounding box or masks to vector geometry
#' 4. Converts units if requested (e.g., mm/day -> mm/dekad)
#' 5. Writes output as a multi-band GeoTIFF (one band per time step) or separate files
#'
#' @export
#'
#' @importFrom terra rast crop mask writeRaster vect ext nlyr subst app
#' @importFrom sf st_transform st_bbox st_crs
#' @importFrom future.apply future_lapply
#'
#' @examples
#' \dontrun{
#' # Download dekadal ET for a bounding box (defaults to mm/dekad)
#' output_file <- wapor_map(
#'   region = c(35.0, 33.0, 36.0, 34.0),
#'   variable = "L1-AETI-D",
#'   period = c("2023-01-01", "2023-01-31"),
#'   folder = "output"
#' )
#'
#' # Download daily rates (mm/day)
#' output_file <- wapor_map(
#'   region = c(35.0, 33.0, 36.0, 34.0),
#'   variable = "L1-AETI-D",
#'   period = c("2023-01-01", "2023-01-31"),
#'   folder = "output",
#'   unit_conversion = "day"
#' )
#'
#' # Download with parallel batching for long periods
#' library(future)
#' plan(multisession)
#' output_file <- wapor_map(
#'   region = c(35.0, 33.0, 36.0, 34.0),
#'   variable = "L1-AETI-D",
#'   period = c("2020-01-01", "2023-12-31"),
#'   folder = "output",
#'   parallel = TRUE,
#'   batch_size = 12
#' )
#' }
wapor_map <- function(
  region,
  variable,
  period,
  folder,
  filename = NULL,
  separate_files = FALSE,
  unit_conversion = NULL,
  seasonal = FALSE,
  mask = FALSE,
  parallel = FALSE,
  batching = TRUE,
  batch_size = 12L
) {
  # Input validation
  if (!is.character(variable) || length(variable) == 0) {
    stop("'variable' must be a character vector", call. = FALSE)
  }
  if (!is.character(period) || length(period) != 2) {
    stop("'period' must be a character vector of length 2: c(start_date, end_date)", call. = FALSE)
  }
  if (!is.character(folder) || length(folder) != 1) {
    stop("'folder' must be a single character string", call. = FALSE)
  }
  if (!is.logical(batching) || length(batching) != 1) {
    stop("'batching' must be a single logical value", call. = FALSE)
  }
  if (!is.numeric(batch_size) || length(batch_size) != 1 || is.na(batch_size) || batch_size < 1) {
    stop("'batch_size' must be a positive integer", call. = FALSE)
  }
  batch_size <- as.integer(batch_size)

  if (as.Date(period[1]) > as.Date(period[2])) {
    stop("'period' start date must be <= end date", call. = FALSE)
  }

  # Create base output directory
  if (!dir.exists(folder)) {
    dir.create(folder, recursive = TRUE)
  }

  # Parse region once
  reg_info <- wapor_parse_region(region)
  l3_code <- if (reg_info$type == "l3_code") reg_info$value else NULL

  get_current_unit_conv <- function(var, u_conv) {
    resolve_output_unit_conversion(var, u_conv)
  }

  # --- Seasonal mode ---
  if (seasonal) {
    if (length(variable) > 1) {
      stop("Seasonal mode only supports a single variable at a time.", call. = FALSE)
    }
    process_seasonal_var <- function(var) {
      log_msg(sprintf("Processing seasonal variable: %s", var))
      
      current_l3_code <- l3_code
      if (is.null(current_l3_code) && grepl("^L3-", var)) {
         guessed_codes <- wapor_guess_region(var, reg_info, period)
         if (is.null(guessed_codes)) {
            warning(sprintf("Region does not intersect with any available WaPOR L3 data for %s. Skipping.", var), call. = FALSE)
            return(NULL)
         }
         current_l3_code <- guessed_codes[1]
      }

      t0_seasonal <- proc.time()
      aggregation_rule <- get_seasonal_aggregation_rule(var)
      seasonal_output_units <- get_seasonal_output_units(var, aggregation_rule)
      
      seasonal_data <- tryCatch({
        download_seasonal_rasters(var, period, current_l3_code, reg_info, folder, do_mask = mask)
      }, error = function(e) {
        warning(sprintf("Failed to download seasonal data for %s: %s", var, e$message), call. = FALSE)
        return(NULL)
      })
      
      if (is.null(seasonal_data)) return(NULL)
      
      groups <- seasonal_data$groups
      aggregation_rule <- seasonal_data$aggregation_rule %||% aggregation_rule
      seasonal_output_units <- get_seasonal_output_units(var, aggregation_rule)
      if (length(groups) == 0) return(NULL)

      ref_raster <- NULL
      running_value <- NULL
      running_weight <- NULL
      valid_count <- NULL
      layer_idx <- 0L
      component_paths <- character(0)
      var_folder <- file.path(folder, paste0(var, "_seasonal"))
      component_folder <- file.path(var_folder, "components")

      if (!dir.exists(var_folder)) {
        dir.create(var_folder, recursive = TRUE, showWarnings = FALSE)
      }
      if (separate_files && !dir.exists(component_folder)) {
        dir.create(component_folder, recursive = TRUE, showWarnings = FALSE)
      }

      for (g_name in names(groups)) {
        g <- groups[[g_name]]
        r_group <- g$raster
        multipliers <- g$multipliers

        # Optimization: Move subst and temperature conversion out of inner loop
        r_group <- terra::subst(r_group, NaN, NA)
        r_group <- wapor_convert_temperature(r_group, g$variable)

        if (is.null(ref_raster)) {
          ref_raster <- r_group[[1]]
        }

        # Check if all layers match the reference geometry; resample the whole stack if not.
        if (!terra::compareGeom(r_group, ref_raster, stopOnError = FALSE)) {
          r_group <- terra::resample(r_group, ref_raster, method = "bilinear")
        }

        # Vectorized multiplication of multipliers across the stack
        weighted_stack <- r_group * multipliers

        # Accumulate sums and weights/counts using specialized terra functions (C++ backend)
        # This is significantly faster than per-layer R loops with ifel()
        if (identical(aggregation_rule, "weighted_mean")) {
          # Weight raster for each layer: multiplier where data is present, 0 otherwise
          # Vectorized across the stack
          weight_stack <- terra::ifel(is.na(r_group), 0, multipliers)

          group_sum <- terra::sum(weighted_stack, na.rm = TRUE)
          group_weight <- terra::sum(weight_stack, na.rm = TRUE)

          if (is.null(running_value)) {
            running_value <- group_sum
            running_weight <- group_weight
          } else {
            running_value <- running_value + group_sum
            running_weight <- running_weight + group_weight
          }
        } else {
          group_sum <- terra::sum(weighted_stack, na.rm = TRUE)
          # count of non-NA layers for masking at the end
          group_valid <- terra::sum(!is.na(r_group))

          if (is.null(running_value)) {
            running_value <- group_sum
            valid_count <- group_valid
          } else {
            running_value <- running_value + group_sum
            valid_count <- valid_count + group_valid
          }
        }

        # Handle separate files if requested (still requires a loop, but on a pre-processed stack)
        if (separate_files) {
          for (i in seq_len(terra::nlyr(r_group))) {
            layer_idx <- layer_idx + 1L
            src_name <- gsub("[^A-Za-z0-9_-]", "_", g$layer_ids[i] %||% names(r_group)[i] %||% sprintf("%03d", i))
            source_var <- gsub("[^A-Za-z0-9_-]", "_", g$variable %||% paste0(var, "_", g$code))
            component_file <- file.path(
              component_folder,
              sprintf("%s.seasonal_component_%03d.from_%s.%s.tif", var, layer_idx, source_var, src_name)
            )
            # Use the already computed weighted layer
            component_raster <- terra::classify(weighted_stack[[i]], cbind(NA, -9999))
            component_raster <- assign_raster_metadata(
              component_raster,
              var,
              units_override = seasonal_output_units
            )
            suppressWarnings(terra::writeRaster(component_raster, component_file, overwrite = TRUE, NAflag = -9999))
            component_paths <- c(component_paths, component_file)
          }
        } else {
          layer_idx <- layer_idx + terra::nlyr(r_group)
        }
      }

      seasonal_sum <- if (identical(aggregation_rule, "weighted_mean")) {
        # running_weight is the sum of multipliers for non-NA pixels
        terra::ifel(running_weight > 0, running_value / running_weight, NA)
      } else {
        # If all contributing layers were NA, mask the resulting 0 back to NA
        terra::mask(running_value, valid_count, maskvalue = 0)
      }
      names(seasonal_sum) <- paste0(if (identical(aggregation_rule, "weighted_mean")) "seasonal_mean_" else "seasonal_", period[1], "_", period[2])
      
      out_fname <- if (!is.null(filename) && length(variable) == 1) filename else {
        prefix_bb <- if (reg_info$type == "bbox") "bb_" else ""
        sprintf("%sWAPOR-3.%s.seasonal.%s_%s.tif", prefix_bb, var, period[1], period[2])
      }
      
      out_path <- file.path(var_folder, out_fname)
      # Finalize raster with metadata AFTER all transformations (like classify)
      r_out <- terra::classify(seasonal_sum, cbind(NA, -9999))
      r_out <- assign_raster_metadata(r_out, var, units_override = seasonal_output_units)
      
      suppressWarnings(terra::writeRaster(r_out, out_path, overwrite = TRUE, NAflag = -9999))
      
      log_msg(sprintf("Seasonal %s for %s saved to: %s", if (identical(aggregation_rule, "weighted_mean")) "mean" else "aggregate", var, out_path))
      if (separate_files) {
        return(list(
          seasonal_aggregate = out_path,
          seasonal_components = component_paths
        ))
      }
      return(out_path)
    }

    results <- lapply(variable, process_seasonal_var)
    names(results) <- variable
    if (length(variable) == 1) return(results[[1]])
    return(results)
  }

  # Helper function to process a single variable
  process_single_var <- function(var) {
    t0_var <- proc.time()
    log_msg(sprintf("Processing variable: %s", var))
    
    # Create variable-specific subdirectory
    var_folder <- file.path(folder, var)
    if (!dir.exists(var_folder)) {
      dir.create(var_folder, recursive = TRUE)
    }

    current_unit_conv <- get_current_unit_conv(var, unit_conversion)
    if (is.null(unit_conversion) && identical(current_unit_conv, "dekad")) {
       log_msg(sprintf("Variable %s is Dekadal. Defaulting unit_conversion to 'dekad'.", var))
    }
    
    # Inform user about automatic temperature conversion
    if (grepl("^AGERA5-(TMIN|TMAX)-", var, ignore.case = FALSE)) {
      log_msg(sprintf("Variable %s is temperature. Automatically converting from Kelvin to Celsius.", var))
    }

    current_l3_code <- l3_code
    if (is.null(current_l3_code) && grepl("^L3-", var)) {
        guessed_codes <- wapor_guess_region(var, reg_info, period)
        if (is.null(guessed_codes)) {
            warning(sprintf("Region does not intersect with any available WaPOR L3 data for %s. Skipping.", var), call. = FALSE)
            return(NULL)
        }
        current_l3_code <- guessed_codes[1]
        if (length(guessed_codes) > 1) {
            warning(sprintf("Region intersects multiple L3 areas (%s). Only downloading data from %s for %s.", 
                            paste(guessed_codes, collapse=", "), current_l3_code, var), call. = FALSE)
        }
    }

    # Get URLs
    urls <- wapor_generate_urls(var, l3_region = current_l3_code, period = period)
    log_msg(sprintf("Found %d files for %s.", length(urls), var))

    if (length(urls) == 0) {
      warning(sprintf("No data found for %s in this period/region. Skipping.", var), call. = FALSE)
      return(NULL)
    }

    # Determine naming components
    base_fname <- basename(urls[1])
    parts <- strsplit(base_fname, "\\.")[[1]]
    if (length(parts) >= 3) {
      product_base <- paste(parts[1:(length(parts)-2)], collapse = ".")
    } else {
      product_base <- var 
    }
    
    prefix <- if (reg_info$type == "bbox") "bb_" else ""

    # Use GDAL virtual file system
    urls <- ifelse(grepl("^/vsicurl/", urls), urls, paste0("/vsicurl/", urls))
    log_msg(sprintf("Streaming data using GDAL virtual file system (/vsicurl/) for %s...", var))
    
    tres_code <- strsplit(var, "-")[[1]][3]
    
    # Split URLs into chunks based on batch_size
    n_urls <- length(urls)
    url_chunks <- get_url_chunks(urls, batching = batching, batch_size = batch_size)
    
    log_msg(sprintf("  Splitting %d files into %d chunk(s) for memory efficiency.", n_urls, length(url_chunks)))
    
    # Define a helper function to process a single chunk of URLs
    process_chunk <- function(chunk_urls, chunk_idx) {
      r <- NULL
      max_retries <- 3
      for (attempt in seq_len(max_retries)) {
        r <- tryCatch({
          suppressWarnings(terra::rast(chunk_urls))
        }, error = function(e) {
          if (attempt < max_retries) {
            Sys.sleep(attempt * 2)
            return(NULL)
          } else {
            warning(sprintf("Failed to load chunk %d raster data after %d attempts: %s", 
                            chunk_idx, max_retries, e$message), call. = FALSE)
            return(NULL)
          }
        })
        if (!is.null(r)) break
      }
      
      if (is.null(r)) return(NULL)

      # Crop to region; optionally mask to polygon boundary
      r <- wapor_crop_to_region(r, reg_info, do_mask = mask)

      # Unit Conversion
      if (current_unit_conv != "none") {
        r <- wapor_convert_raster(r, var, chunk_urls, current_unit_conv)
      }

      # Temperature Conversion (Kelvin to Celsius for AgERA5 temperature variables)
      r <- wapor_convert_temperature(r, var)

      # Standardize layer names to "YYYY-MM-DD" (vectorized)
      chunk_meta <- wapor_parse_dates(sub("^/vsicurl/", "", chunk_urls), tres = tres_code)
      layer_names <- chunk_meta$start_date
      names(r) <- layer_names

      if (separate_files) {
        # Save individual files directly
        chunk_paths <- vapply(seq_len(terra::nlyr(r)), function(i) {
          out_path <- file.path(var_folder, paste0(prefix, product_base, ".", names(r)[i], ".tif"))
          # Finalize raster with metadata AFTER all transformations (like classify)
          r_out <- terra::classify(r[[i]], cbind(NA, -9999))
          r_out <- assign_raster_metadata(r_out, var, current_unit_conv)
          
          suppressWarnings(terra::writeRaster(r_out, out_path, overwrite = TRUE, NAflag = -9999))
          out_path
        }, character(1))
        return(list(type = "separate", paths = chunk_paths))
      } else {
        # Save chunk to tempfile for later stacking
        tmp_path <- tempfile(fileext = ".tif")
        r_out <- terra::classify(r, cbind(NA, -9999))
        suppressWarnings(terra::writeRaster(r_out, tmp_path, overwrite = TRUE, NAflag = -9999))
        return(list(type = "stack", filepath = tmp_path, layer_names = layer_names))
      }
    }
    
    # Process all chunks, using future_lapply if parallel is TRUE
    if (parallel) {
      log_msg("  Processing chunks in parallel...")
      chunk_results <- future.apply::future_lapply(seq_along(url_chunks), function(i) {
        process_chunk(url_chunks[[i]], i)
      }, future.seed = TRUE)
    } else {
      chunk_results <- lapply(seq_along(url_chunks), function(i) {
        process_chunk(url_chunks[[i]], i)
      })
    }
    
    # Filter out any failed chunks
    chunk_results <- Filter(Negate(is.null), chunk_results)
    
    if (length(chunk_results) == 0) {
      warning("All chunks failed to process.", call. = FALSE)
      return(NULL)
    }

    if (separate_files) {
      # Combine paths from all chunks
      output_paths <- unlist(lapply(chunk_results, function(res) res$paths))
    } else {
      # Combine temporary files into a single stack
      temp_files <- vapply(chunk_results, function(res) res$filepath, character(1))
      all_names <- unlist(lapply(chunk_results, function(res) res$layer_names))
      
      log_msg("  Merging chunks into final multi-band stack...")
      # Load all temp files logically
      r_all <- suppressWarnings(terra::rast(temp_files))
      names(r_all) <- all_names
      
      current_filename <- filename
      if (is.null(current_filename)) {
        start_date <- names(r_all)[1]
        end_date <- names(r_all)[terra::nlyr(r_all)]
        date_part <- if (terra::nlyr(r_all) == 1) start_date else paste0(start_date, "_", end_date)
        current_filename <- paste0(prefix, product_base, ".", date_part, ".tif")
      }
      
      out_path <- file.path(var_folder, current_filename)
      # Finalize raster with metadata AFTER all transformations (like classify)
      r_out <- terra::classify(r_all, cbind(NA, -9999))
      r_out <- assign_raster_metadata(r_out, var, current_unit_conv)
      
      suppressWarnings(terra::writeRaster(r_out, out_path, overwrite = TRUE, NAflag = -9999))
      
      # Clean up temp files
      unlink(temp_files)
      
      output_paths <- out_path
    }
    
    log_msg(sprintf("  Variable %s completed in %.1f seconds", var, (proc.time() - t0_var)[["elapsed"]]))
    return(output_paths)
  }

  # Process all variables
  results <- lapply(variable, process_single_var)
  names(results) <- variable
  
  # Return just the path if it's a single variable (backward compatibility/simplicity)
  # But structured list is better if >1 variable.
  # User requested "processing list of variables", so list return is safer.
  if (length(variable) == 1) {
    return(results[[1]])
  } else {
    return(results)
  }
}
