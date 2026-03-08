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
#' @param parallel Logical. If `TRUE`, attempts to use `future.apply` for parallel processing.
#'   Default is `FALSE`.
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
wapor_map <- function(region, variable, period, folder, filename = NULL, separate_files = FALSE, unit_conversion = NULL, seasonal = FALSE, parallel = FALSE) {
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
    total_layers <- sum(vapply(groups, function(g) terra::nlyr(g$raster), integer(1)))
    weighted_layers <- vector("list", total_layers)
    layer_idx <- 0L
    ref_raster <- NULL

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
    
    var_folder <- file.path(folder, variable[1]) 
    if (!dir.exists(var_folder)) {
      dir.create(var_folder, recursive = TRUE, showWarnings = FALSE)
    }
    out_path <- file.path(var_folder, filename)
    seasonal_out <- terra::classify(seasonal_sum, cbind(NA, -9999))
    suppressWarnings(terra::writeRaster(seasonal_out, out_path, overwrite = TRUE, NAflag = -9999))
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
    
    # Load as SpatRaster with retry logic for intermittent /vsicurl/ errors
    r <- NULL
    max_retries <- 3
    for (attempt in seq_len(max_retries)) {
      r <- tryCatch({
        suppressWarnings(terra::rast(urls))
      }, error = function(e) {
        if (attempt < max_retries) {
          message(sprintf("Attempt %d to load raster failed. Retrying in %d seconds... (%s)", 
                          attempt, attempt * 2, e$message))
          Sys.sleep(attempt * 2)
          return(NULL)
        } else {
          warning(sprintf("Failed to load raster data for %s after %d attempts: %s", 
                          var, max_retries, e$message), call. = FALSE)
          return(NULL)
        }
      })
      if (!is.null(r)) break
    }
    
    if (is.null(r)) return(NULL)
    message(sprintf("  Raster loaded in %.1f seconds (%d layers)", (proc.time() - t0_var)[["elapsed"]], terra::nlyr(r)))

    # Crop/Mask
    r <- crop_to_region(r, reg_info, do_mask = TRUE)

    # Unit Conversion
    if (current_unit_conv != "none") {
      message(sprintf("Converting units to '%s'...", current_unit_conv))
      r <- raster_unit_convertor(r, var, urls, current_unit_conv)
    }

    # Standardize layer names to "YYYY-MM-DD" (terra uses raw filenames by default).
    # Compute the temporal resolution code once outside the loop.
    tres_code <- strsplit(var, "-")[[1]][3]
    layer_names <- vapply(urls, function(u) {
      get_date_info(sub("^/vsicurl/", "", u), tres = tres_code)$start_date
    }, character(1))
    names(r) <- layer_names

    if (separate_files) {
      # Pre-allocate output_paths via vapply (avoids O(n²) vector growth from
      # repeated c() calls in a loop).
      output_paths <- vapply(seq_len(terra::nlyr(r)), function(i) {
        out_path <- file.path(var_folder,
                              paste0(prefix, product_base, ".", names(r)[i], ".tif"))
        terra::writeRaster(r[[i]], out_path, overwrite = TRUE)
        out_path
      }, character(1))
      if (parallel) {
        w_r <- terra::wrap(r)
        output_paths <- future.apply::future_lapply(seq_len(terra::nlyr(r)), function(i) {
          # use the standardized name we just created
          r_worker <- terra::unwrap(w_r)
          date_str <- names(r_worker)[i] 
          
          fname <- paste0(prefix, product_base, ".", date_str, ".tif")
          out_path <- file.path(var_folder, fname)
          
          r_out <- terra::classify(r_worker[[i]], cbind(NA, -9999))
          suppressWarnings(terra::writeRaster(r_out, out_path, overwrite = TRUE, NAflag = -9999))
          return(out_path)
        }, future.seed = TRUE)
      } else {
        output_paths <- lapply(seq_len(terra::nlyr(r)), function(i) {
          date_str <- names(r)[i] 
          
          fname <- paste0(prefix, product_base, ".", date_str, ".tif")
          out_path <- file.path(var_folder, fname)
          
          r_out <- terra::classify(r[[i]], cbind(NA, -9999))
          suppressWarnings(terra::writeRaster(r_out, out_path, overwrite = TRUE, NAflag = -9999))
          return(out_path)
        })
      }
      
      output_paths <- unlist(output_paths)
    } else {
      # Single stack
      current_filename <- filename
      if (is.null(current_filename)) {
        start_date <- names(r)[1]
        end_date <- names(r)[terra::nlyr(r)]
        
        if (terra::nlyr(r) == 1) {
          date_part <- start_date
        } else {
          date_part <- paste0(start_date, "_", end_date)
        }
        
        current_filename <- paste0(prefix, product_base, ".", date_part, ".tif")
      }
      
      out_path <- file.path(var_folder, current_filename)
      r_out <- terra::classify(r, cbind(NA, -9999))
      suppressWarnings(terra::writeRaster(r_out, out_path, overwrite = TRUE, NAflag = -9999))
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
