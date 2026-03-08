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
#'   intermediate component rasters into `<folder>/<variable>/`. Default is `FALSE`.
#' @param parallel Logical. If `TRUE`, attempts to use `future.apply` for parallel processing.
#'   Default is `FALSE`.
#' @param batch_size Integer. Number of remote files loaded per chunk in non-seasonal mode.
#'   Lower values reduce memory pressure for long periods.
#'
#' @return Character. Path to the output GeoTIFF file.
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
  parallel = FALSE,
  batch_size = 24L
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
  reg_info <- parse_region(region)
  l3_code <- if (reg_info$type == "l3_code") reg_info$value else NULL

  # --- Seasonal mode ---
  if (seasonal) {
    if (length(variable) != 1) {
      stop("'seasonal' mode supports only a single variable", call. = FALSE)
    }
    if (!is.null(unit_conversion) && unit_conversion != "none") {
      message("Note: 'unit_conversion' is ignored when seasonal = TRUE. The output is in base physical units (e.g., mm).")
    }

    current_l3_code <- l3_code
    if (is.null(current_l3_code) && grepl("^L3-", variable[1])) {
       guessed_codes <- guess_l3_region(variable[1], reg_info, period)
       if (is.null(guessed_codes)) stop(sprintf("Region does not intersect with any available WaPOR L3 data for %s.", variable[1]), call. = FALSE)
       current_l3_code <- guessed_codes[1]
       if (length(guessed_codes) > 1) {
           warning(sprintf("Region intersects multiple L3 areas (%s). Only downloading data from %s.", paste(guessed_codes, collapse=", "), current_l3_code), call. = FALSE)
       }
    }

    # Call internal helper to download and organize rasters
    t0_seasonal <- proc.time()
    seasonal_data <- download_seasonal_rasters(variable, period, current_l3_code, reg_info, folder)
    
    groups <- seasonal_data$groups
    message(sprintf("Seasonal rasters downloaded in %.1f seconds", (proc.time() - t0_seasonal)[["elapsed"]]))

    if (length(groups) == 0) {
      stop("No rasters could be loaded for the seasonal sum.", call. = FALSE)
    }
    
    # Pre-allocate layer list
    total_layers <- as.integer(sum(vapply(groups, function(g) terra::nlyr(g$raster), numeric(1))))
    weighted_layers <- vector("list", total_layers)
    layer_idx <- 0L
    ref_raster <- NULL
    component_paths <- character(0)
    component_folder <- file.path(folder, variable[1])
    if (separate_files && !dir.exists(component_folder)) {
      dir.create(component_folder, recursive = TRUE, showWarnings = FALSE)
    }

    # Process each group (Apply multipliers and mask if needed)
    for (g_name in names(groups)) {
      g <- groups[[g_name]]
      r_group <- g$raster
      multipliers <- g$multipliers

      # wapor_map specific: Apply MASK if vector
      if (reg_info$type == "vector") {
        v <- suppressWarnings(terra::vect(reg_info$value))
        r_group <- suppressWarnings(terra::mask(r_group, v))
      }

      for (i in seq_len(terra::nlyr(r_group))) {
        layer_clean <- terra::subst(r_group[[i]], NaN, NA)
        layer <- layer_clean * multipliers[i]

        if (is.null(ref_raster)) {
          ref_raster <- layer
        } else if (!terra::compareGeom(layer, ref_raster, stopOnError = FALSE)) {
          message("Resampling raster to align grids across temporal resolutions...")
          layer <- terra::resample(layer, ref_raster, method = "bilinear")
        }

        layer_idx <- layer_idx + 1L
        weighted_layers[[layer_idx]] <- layer

        if (separate_files) {
          src_name <- names(r_group)[i]
          if (is.null(src_name) || !nzchar(src_name)) {
            src_name <- sprintf("%03d", i)
          } else {
            src_name <- gsub("[^A-Za-z0-9_-]", "_", src_name)
          }
          component_file <- file.path(
            component_folder,
            sprintf("%s.component_%03d.%s.%s.tif", variable[1], layer_idx, g$code, src_name)
          )
          layer_out <- terra::classify(layer, cbind(NA, -9999))
          suppressWarnings(terra::writeRaster(layer_out, component_file, overwrite = TRUE, NAflag = -9999))
          component_paths <- c(component_paths, component_file)
        }
      }
    }
    
    # Stack all weighted layers and sum
    full_stack <- terra::rast(weighted_layers)
    seasonal_sum <- terra::app(full_stack, sum, na.rm = TRUE)

    # Mask out cells where ALL layers were NA (sum with na.rm=TRUE returns 0 for these)
    all_na_mask <- terra::app(full_stack, function(x) all(is.na(x)))
    seasonal_sum <- terra::mask(seasonal_sum, all_na_mask, maskvalue = 1)
    
    names(seasonal_sum) <- paste0("seasonal_", period[1], "_", period[2])
    
    # Build output filename
    if (is.null(filename)) {
      prefix <- if (reg_info$type == "bbox") "bb_" else ""
      filename <- sprintf("%sWAPOR-3.%s.seasonal.%s_%s.tif",
                          prefix, variable, period[1], period[2])
    }
    
    var_folder <- file.path(folder, paste0(variable[1], "_seasonal")) 
    if (!dir.exists(var_folder)) {
      dir.create(var_folder, recursive = TRUE, showWarnings = FALSE)
    }
    out_path <- file.path(var_folder, filename)
    seasonal_out <- terra::classify(seasonal_sum, cbind(NA, -9999))
    suppressWarnings(terra::writeRaster(seasonal_out, out_path, overwrite = TRUE, NAflag = -9999))
    if (!file.exists(out_path)) {
      stop(sprintf("Seasonal output was not written to disk: %s", out_path), call. = FALSE)
    }
    if (separate_files && length(component_paths) > 0) {
      message(sprintf("Saved %d seasonal component raster(s) to: %s", length(component_paths), component_folder))
    }
    message(sprintf("Seasonal sum saved to: %s", out_path))
    message(sprintf("Seasonal aggregation completed in %.1f seconds", (proc.time() - t0_seasonal)[["elapsed"]]))

    return(out_path)
  }

  # Helper function to process a single variable
  process_single_var <- function(var) {
    t0_var <- proc.time()
    message(sprintf("Processing variable: %s", var))
    
    # Create variable-specific subdirectory
    var_folder <- file.path(folder, var)
    if (!dir.exists(var_folder)) {
      dir.create(var_folder, recursive = TRUE)
    }

    # Determine unit_conversion for this variable if NULL
    current_unit_conv <- unit_conversion
    if (is.null(current_unit_conv)) {
      if (grepl("-D$", var)) {
        current_unit_conv <- "dekad"
        message(sprintf("Variable %s is Dekadal. Defaulting unit_conversion to 'dekad'.", var))
      } else {
        current_unit_conv <- "none"
      }
    }

    current_l3_code <- l3_code
    if (is.null(current_l3_code) && grepl("^L3-", var)) {
        guessed_codes <- guess_l3_region(var, reg_info, period)
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
    message(sprintf("Found %d files for %s.", length(urls), var))

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
    
    tres_code <- strsplit(var, "-")[[1]][3]
    
    # Split URLs into chunks based on batch_size
    n_urls <- length(urls)
    url_chunks <- split(urls, ceiling(seq_along(urls) / batch_size))
    
    message(sprintf("  Splitting %d files into %d chunk(s) formemory efficiency.", n_urls, length(url_chunks)))
    
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

      # Crop/Mask
      r <- crop_to_region(r, reg_info, do_mask = TRUE)

      # Unit Conversion
      if (current_unit_conv != "none") {
        r <- raster_unit_convertor(r, var, chunk_urls, current_unit_conv)
      }

      # Standardize layer names to "YYYY-MM-DD"
      layer_names <- vapply(chunk_urls, function(u) {
        get_date_info(sub("^/vsicurl/", "", u), tres = tres_code)$start_date
      }, character(1))
      names(r) <- layer_names

      if (separate_files) {
        # Save individual files directly
        chunk_paths <- vapply(seq_len(terra::nlyr(r)), function(i) {
          out_path <- file.path(var_folder, paste0(prefix, product_base, ".", names(r)[i], ".tif"))
          r_out <- terra::classify(r[[i]], cbind(NA, -9999))
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
      message("  Processing chunks in parallel...")
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
      
      message("  Merging chunks into final multi-band stack...")
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
      suppressWarnings(terra::writeRaster(r_all, out_path, overwrite = TRUE, NAflag = -9999))
      
      # Clean up temp files
      unlink(temp_files)
      
      output_paths <- out_path
    }
    
    message(sprintf("  Variable %s completed in %.1f seconds", var, (proc.time() - t0_var)[["elapsed"]]))
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
