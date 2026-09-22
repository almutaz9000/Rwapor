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
#' @param period Character vector or list. Date range as
#'   `c(start_date, end_date)` in "YYYY-MM-DD" format. Can also be a
#'   named or unnamed list of such vectors for multiple seasons.
#' @param folder Character. Output directory path. Will be created if needed.
#' @param filename Character. Optional output filename. If NULL, a default
#'   name is generated based on region and variable.
#' @param unit_conversion Character. Public unit-conversion mode.
#'   One of: `"unit_conversion"` or `"none"`.
#'   Default is `NULL`, which dynamically matches the variable behavior:
#'   * Dekadal daily-rate products are saved as dekadal totals
#'   * Monthly products remain monthly totals
#'   * `"none"` preserves raw API values without temporal conversion
#' @param seasonal Logical. If `TRUE`, downloads and aggregates data for the
#'   entire period into a single seasonal raster (sum/mean).
#'   Default is `FALSE`.
#' @param fun Optional seasonal summary function. `NULL` (default) preserves
#'   variable-aware weighted aggregation. Explicit `"sum"` remains weighted;
#'   `"mean"`, `"std"`, `"min"`, `"max"`, and `"median"` use each
#'   overlapping source layer once without scaling partial layers.
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
#' @param l3_region Optional L3 code to use for an L3 variable and spatial AOI.
#' @param l3_mode L3 coverage policy: `"select"` requires one selected L3 code
#'   when several regions intersect; `"mosaic_all"` writes source assets and a
#'   coverage-bearing mosaic for every intersecting L3 region.
#' @param partial Logical. If `TRUE`, incomplete temporal coverage is allowed
#'   and recorded. Default `FALSE` fails the request.
#' @param cog Logical. Write GeoTIFF outputs with [wapor_write_cog()]. Default `FALSE`.
#' @param on_batch_done Optional function called after each processed batch with
#'   `(batch_index, batch_count)`. Callback errors are ignored.
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
#' 4. Applies temporal-resolution conversion when requested
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
#' # Preserve raw API values without temporal conversion
#' output_file <- wapor_map(
#'   region = c(35.0, 33.0, 36.0, 34.0),
#'   variable = "L1-AETI-D",
#'   period = c("2023-01-01", "2023-01-31"),
#'   folder = "output",
#'   unit_conversion = "none"
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
  batch_size = 12L,
  l3_region = NULL,
  l3_mode = c("select", "mosaic_all"),
  partial = FALSE,
  cog = FALSE,
  on_batch_done = NULL,
  fun = NULL
) {
  l3_mode <- match.arg(l3_mode)
  # Input validation
  if (!is.character(variable) || length(variable) == 0) {
    stop("'variable' must be a character vector", call. = FALSE)
  }
  if (!is.list(period) && (!is.character(period) || length(period) != 2)) {
    stop("'period' must be a character vector of length 2 or a list of such vectors", call. = FALSE)
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

  seasonal_summary <- NULL
  if (isTRUE(seasonal)) {
    if (length(variable) != 1L) {
      stop(sprintf(
        "seasonal mode requires a single variable; got %d. Call wapor_map() separately for each variable.",
        length(variable)
      ), call. = FALSE)
    }
    seasonal_summary <- resolve_seasonal_summary_function(variable, fun)
  }

  if (!is.list(period)) {
    if (as.Date(period[1]) > as.Date(period[2])) {
      stop("'period' start date must be <= end date", call. = FALSE)
    }
  }

  # Create base output directory
  if (!dir.exists(folder)) {
    dir.create(folder, recursive = TRUE)
  }

  # Parse region once
  reg_info <- wapor_parse_region(region)
  l3_code <- if (reg_info$type == "l3_code") reg_info$value else NULL

  resolve_l3_code <- function(var, current_period) {
    if (!grepl("^L3-", var)) return(NULL)
    if (!is.null(l3_code)) return(l3_code)
    detected <- wapor_guess_region(var, reg_info, current_period)
    selected <- wapor_resolve_l3_selection(detected, l3_region, l3_mode)
    selected[[1]]
  }

  get_current_unit_conv <- function(var, u_conv) {
    resolve_output_unit_conversion(var, u_conv)
  }

  if (identical(l3_mode, "mosaic_all") && any(grepl("^L3-", variable))) {
    if (!is.null(l3_code)) {
      stop("'mosaic_all' requires a spatial AOI, not a single L3 code region.", call. = FALSE)
    }
    return(wapor_map_mosaic_all(
      region = region, variable = variable, period = period, folder = folder,
      filename = filename, separate_files = separate_files,
      unit_conversion = unit_conversion, seasonal = seasonal, mask = mask,
      parallel = parallel, batching = batching, batch_size = batch_size,
      partial = partial, cog = cog, fun = fun
    ))
  }

  # --- Seasonal mode ---
  if (seasonal) {
    process_seasonal_var <- function(var, current_period, current_filename, s_name = "seasonal") {
      log_msg(sprintf("Processing seasonal variable: %s", var))
      
      current_l3_code <- resolve_l3_code(var, current_period)

      t0_seasonal <- proc.time()
      aggregation_rule <- seasonal_summary$aggregation_rule
      seasonal_output_units <- get_seasonal_output_units(var, aggregation_rule)
      
      # Smart-Linking for Timing Rasters:
      # If specific masks for this season exist (e.g., Winter2018_start.tif), use them.
      p_start_raster <- NULL
      p_end_raster   <- NULL
      
      if (!is.null(folder)) {
        # Check both the folder itself and the 'seasonal_masks' subfolder
        mask_dirs <- c(folder, file.path(folder, "seasonal_masks"))
        for (m_dir in mask_dirs) {
          s_start_path <- file.path(m_dir, paste0(s_name, "_start.tif"))
          s_end_path   <- file.path(m_dir, paste0(s_name, "_end.tif"))
          if (file.exists(s_start_path)) p_start_raster <- terra::rast(s_start_path)
          if (file.exists(s_end_path))   p_end_raster   <- terra::rast(s_end_path)
        }
      }

      seasonal_data <- tryCatch({
        download_seasonal_rasters(var, current_period, current_l3_code, reg_info, folder,
                                  do_mask = mask, start_raster = p_start_raster, end_raster = p_end_raster,
                                  partial = partial)
      }, error = function(e) {
        warning(sprintf("Failed to download seasonal data for %s: %s", var, e$message), call. = FALSE)
        return(NULL)
      })
      
      if (is.null(seasonal_data)) return(NULL)
      
      groups <- seasonal_data$groups
      if (!isTRUE(seasonal_summary$explicit)) {
        aggregation_rule <- seasonal_data$aggregation_rule %||% aggregation_rule
      }
      seasonal_output_units <- get_seasonal_output_units(
        var,
        if (isTRUE(seasonal_summary$weighted)) aggregation_rule else "weighted_mean"
      )
      if (length(groups) == 0) return(NULL)

      running_value <- NULL
      running_weight <- NULL
      valid_count <- NULL
      component_paths <- character(0)
      equal_step_layers <- list()
      included_layer_ids <- if (is.data.frame(seasonal_data$plan) &&
                                all(c("period_id", "overlap_days") %in% names(seasonal_data$plan))) {
        as.character(seasonal_data$plan$period_id[seasonal_data$plan$overlap_days > 0])
      } else {
        NULL
      }

      var_folder <- file.path(folder, paste0(var, "_seasonal"))
      if (!dir.exists(var_folder)) {
        dir.create(var_folder, recursive = TRUE, showWarnings = FALSE)
      }

      for (g_name in names(groups)) {
        g <- groups[[g_name]]
        r_group <- g$raster
        multipliers <- g$multipliers

        # Clean NaNs and apply temperature conversion
        r_group <- terra::subst(r_group, NaN, NA)
        r_group <- wapor_convert_temperature(r_group, g$variable)

        if (!is.null(included_layer_ids) && !is.null(g$layer_ids)) {
          selected_layers <- which(as.character(g$layer_ids) %in% included_layer_ids)
          if (length(selected_layers) == 0) next
          r_group <- r_group[[selected_layers]]
          multipliers <- multipliers[selected_layers]
        }

        if (!isTRUE(seasonal_summary$weighted)) {
          equal_step_layers[[length(equal_step_layers) + 1L]] <- r_group

          if (isTRUE(separate_files)) {
            comp_dir <- file.path(var_folder, "components")
            if (!dir.exists(comp_dir)) dir.create(comp_dir, recursive = TRUE, showWarnings = FALSE)
            comp_fname <- file.path(comp_dir, paste0("seasonal_component_", g_name, ".tif"))
            reducer <- if (identical(seasonal_summary$fun, "std")) "sd" else seasonal_summary$fun
            r_comp <- terra::app(r_group, fun = reducer, na.rm = TRUE)
            r_comp <- terra::classify(r_comp, cbind(NA, -9999))
            r_comp <- assign_raster_metadata(r_comp, var, units_override = seasonal_output_units)
            suppressWarnings(terra::writeRaster(r_comp, comp_fname, overwrite = TRUE, NAflag = -9999))
            component_paths <- c(component_paths, comp_fname)
          }
          next
        }

        # Handle weighted sum/mean using terra::sum for performance and tree depth stability
        weighted_stack <- r_group * multipliers

        group_sum <- sum(weighted_stack, na.rm = TRUE)

        if (isTRUE(separate_files)) {
          comp_dir <- file.path(var_folder, "components")
          if (!dir.exists(comp_dir)) dir.create(comp_dir, recursive = TRUE, showWarnings = FALSE)
          comp_fname <- file.path(comp_dir, paste0("seasonal_component_", g_name, ".tif"))
          r_comp <- terra::classify(group_sum, cbind(NA, -9999))
          r_comp <- assign_raster_metadata(r_comp, var, units_override = seasonal_output_units)
          suppressWarnings(terra::writeRaster(r_comp, comp_fname, overwrite = TRUE, NAflag = -9999))
          component_paths <- c(component_paths, comp_fname)
        }
        
        if (identical(aggregation_rule, "weighted_mean")) {
          # Sum of weights where data is not NA
          group_weight <- sum(terra::ifel(is.na(r_group), 0, multipliers), na.rm = TRUE)
          
          if (is.null(running_value)) {
            running_value <- group_sum
            running_weight <- group_weight
          } else {
            # Align if needed (should be same ext/res from download_seasonal_rasters)
            running_value <- running_value + group_sum
            running_weight <- running_weight + group_weight
          }
        } else {
          # Number of valid observations (used for masking the final sum)
          group_valid <- sum(!is.na(r_group), na.rm = TRUE)
          
          if (is.null(running_value)) {
            running_value <- group_sum
            valid_count <- group_valid
          } else {
            running_value <- running_value + group_sum
            valid_count <- valid_count + group_valid
          }
        }
      }

      seasonal_result <- if (!isTRUE(seasonal_summary$weighted)) {
        if (length(equal_step_layers) == 0) return(NULL)
        reducer <- if (identical(seasonal_summary$fun, "std")) "sd" else seasonal_summary$fun
        terra::app(do.call(c, equal_step_layers), fun = reducer, na.rm = TRUE)
      } else if (identical(aggregation_rule, "weighted_mean")) {
        terra::ifel(running_weight > 0, running_value / running_weight, NA)
      } else {
        terra::mask(running_value, valid_count, maskvalue = 0)
      }
      
      names(seasonal_result) <- paste0(
        if (isTRUE(seasonal_summary$explicit)) {
          paste0("seasonal_", seasonal_summary$fun, "_")
        } else if (identical(aggregation_rule, "weighted_mean")) {
          "seasonal_mean_"
        } else {
          "seasonal_"
        },
        current_period[1], "_", current_period[2]
      )
      
      out_path <- file.path(var_folder, current_filename)
      # Finalize raster with metadata and proper NA flag
      r_out <- terra::classify(seasonal_result, cbind(NA, -9999))
      r_out <- assign_raster_metadata(r_out, var, units_override = seasonal_output_units)
      
      suppressWarnings(terra::writeRaster(r_out, out_path, overwrite = TRUE, NAflag = -9999))

      log_msg(sprintf("Seasonal %s for %s saved to: %s",
                      if (isTRUE(seasonal_summary$explicit)) seasonal_summary$fun else if (identical(aggregation_rule, "weighted_mean")) "mean" else "aggregate",
                      var, out_path))

      if (isTRUE(separate_files) && length(component_paths) > 0) {
        return(list(seasonal_aggregate = out_path, seasonal_components = component_paths))
      }
      return(out_path)
    }

    # Iterate over variables and periods
    all_results <- list()
    for (v in variable) {
      if (is.list(period)) {
        v_results <- list()
        for (i in seq_along(period)) {
          p <- period[[i]]
          s_name <- names(period)[i] %||% paste0(p[1], "_", p[2])
          
          window_filename <- if (!is.null(filename)) {
            if (length(variable) > 1) {
              sub("\\.tif$", paste0(".", v, ".", s_name, ".", p[1], "_", p[2], ".tif"), filename)
            } else {
              sub("\\.tif$", paste0(".", s_name, ".", p[1], "_", p[2], ".tif"), filename)
            }
          } else {
            prefix_bb <- if (reg_info$type == "bbox") "bb_" else ""
            if (isTRUE(seasonal_summary$explicit)) {
              sprintf("%sWAPOR-3.%s.seasonal.%s.%s.%s_%s.tif", prefix_bb, v, seasonal_summary$fun, s_name, p[1], p[2])
            } else {
              sprintf("%sWAPOR-3.%s.seasonal.%s.%s_%s.tif", prefix_bb, v, s_name, p[1], p[2])
            }
          }
          
          log_msg(sprintf("Processing variable %s, season %s", v, s_name))
          v_results[[s_name]] <- process_seasonal_var(v, p, window_filename, s_name)
        }
        all_results[[v]] <- v_results
      } else {
        s_name <- if (!is.null(names(period))) names(period)[1] else "seasonal"
        def_fname <- if (!is.null(filename)) {
           if (length(variable) > 1) sub("\\.tif$", paste0(".", v, ".tif"), filename) else filename
        } else {
          prefix_bb <- if (reg_info$type == "bbox") "bb_" else ""
          if (isTRUE(seasonal_summary$explicit)) {
            sprintf("%sWAPOR-3.%s.seasonal.%s.%s_%s.tif", prefix_bb, v, seasonal_summary$fun, period[1], period[2])
          } else {
            sprintf("%sWAPOR-3.%s.seasonal.%s_%s.tif", prefix_bb, v, period[1], period[2])
          }
        }
        all_results[[v]] <- process_seasonal_var(v, period, def_fname, s_name)
      }
    }
    
    if (length(variable) == 1) return(all_results[[1]])
    return(all_results)
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
    if ((is.null(unit_conversion) || identical(unit_conversion, "unit_conversion")) &&
        identical(current_unit_conv, "dekad")) {
       log_msg(sprintf(
         "Variable %s is Dekadal (stored as mm/day). Saving with temporal conversion as mm/dekad.",
         var
       ))
    }
    
    # Inform user about automatic temperature conversion
    if (grepl("^AGERA5-(TMIN|TMAX)-", var, ignore.case = FALSE)) {
      log_msg(sprintf("Variable %s is temperature. Automatically converting from Kelvin to Celsius.", var))
    }

    current_l3_code <- resolve_l3_code(var, period)

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
    urls <- .wapor_prefix_vsicurl(urls)
    log_msg(sprintf("Streaming data using GDAL virtual file system (/vsicurl/) for %s...", var))
    
    tres_code <- strsplit(var, "-")[[1]][3]
    
    # Split URLs into chunks based on batch_size
    n_urls <- length(urls)
    url_chunks <- get_url_chunks(urls, batching = batching, batch_size = batch_size)
    
    log_msg(sprintf("  Splitting %d files into %d chunk(s) for memory efficiency.", n_urls, length(url_chunks)))
    
    # Define a helper function to process a single chunk of URLs
    process_chunk <- function(chunk_urls, chunk_idx) {
      r <- NULL
      err <- NULL
      max_retries <- 3
      for (attempt in seq_len(max_retries)) {
        r <- tryCatch({
          suppressWarnings(terra::rast(chunk_urls))
        }, error = function(e) {
          if (attempt < max_retries) {
            Sys.sleep(attempt * 2)
            return(NULL)
          } else {
            return(e)
          }
        })
        if (inherits(r, "error")) {
          err <- r
          r <- NULL
        }
        if (!is.null(r)) break
      }

      if (is.null(r)) {
        return(list(
          status = "failed",
          chunk_idx = chunk_idx,
          urls = chunk_urls,
          error = if (is.null(err)) "unknown" else conditionMessage(err),
          paths = character(0),
          layer_names = character(0)
        ))
      }

      # Crop to region; optionally mask to polygon boundary. Crop can force
      # remote pixel I/O, so keep it inside the retry boundary.
      r <- .wapor_retry_remote_operation(
        function() wapor_crop_to_region(r, reg_info, do_mask = mask),
        label = sprintf("%s crop", var)
      )

      # Unit Conversion
      if (current_unit_conv != "none") {
        r <- wapor_convert_raster(r, var, chunk_urls, current_unit_conv)
      }

      # Temperature Conversion (Kelvin to Celsius for AgERA5 variables)
      r <- wapor_convert_temperature(r, var)

      # Standardize layer names to "YYYY-MM-DD"
      layer_names <- vapply(chunk_urls, function(u) {
        wapor_date_info(sub("^/vsicurl/", "", u), tres = tres_code)$start_date
      }, character(1))
      names(r) <- layer_names

      if (separate_files) {
        chunk_paths <- vapply(seq_len(terra::nlyr(r)), function(i) {
          out_path <- file.path(var_folder, paste0(prefix, product_base, ".", names(r)[i], ".tif"))
          r_out <- terra::classify(r[[i]], cbind(NA, -9999))
          r_out <- assign_raster_metadata(r_out, var, current_unit_conv)
          .wapor_retry_remote_operation(
            function() terra::writeRaster(r_out, out_path, overwrite = TRUE, NAflag = -9999),
            label = sprintf("%s output", var)
          )
          out_path
        }, character(1))
        return(list(status = "ok", chunk_idx = chunk_idx, urls = chunk_urls,
                    paths = chunk_paths, layer_names = layer_names))
      } else {
        tmp_path <- tempfile(fileext = ".tif")
        r_out <- terra::classify(r, cbind(NA, -9999))
        .wapor_retry_remote_operation(
          function() terra::writeRaster(r_out, tmp_path, overwrite = TRUE, NAflag = -9999),
          label = sprintf("%s temporary output", var)
        )
        return(list(status = "ok", chunk_idx = chunk_idx, urls = chunk_urls,
                    filepath = tmp_path, layer_names = layer_names))
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
        result <- process_chunk(url_chunks[[i]], i)
        if (is.function(on_batch_done)) {
          tryCatch(on_batch_done(i, length(url_chunks)), error = function(e) NULL)
        }
        result
      })
    }

    # Classify results: ok chunks and failed chunks
    ok_chunks <- chunk_results[vapply(chunk_results, function(r) identical(r$status, "ok"), logical(1))]
    failed_chunks <- chunk_results[vapply(chunk_results, function(r) identical(r$status, "failed"), logical(1))]

    if (length(ok_chunks) == 0) {
      failed_urls <- unique(unlist(lapply(failed_chunks, function(r) r$urls)))
      warning(sprintf("All chunks failed to process for %s (%d layer(s) affected).",
                      var, length(failed_urls)), call. = FALSE)
      return(list(
        status = "failed",
        variable = var,
        output_paths = character(0),
        failed_layers = failed_urls,
        n_ok_chunks = 0L,
        n_failed_chunks = length(chunk_results)
      ))
    }

    failed_urls <- unique(unlist(lapply(failed_chunks, function(r) r$urls)))
    if (length(failed_urls) > 0 && !isTRUE(partial)) {
      stop(sprintf(
        "%d raster batch(es) failed for %s; refusing incomplete output. Set partial = TRUE to allow it.",
        length(failed_chunks), var
      ), call. = FALSE)
    }
    if (length(failed_urls) > 0 && isTRUE(partial)) {
      warning(sprintf("Returning partial output for %s: %d raster layer(s) failed.",
                      var, length(failed_urls)), call. = FALSE)
    }

    if (separate_files) {
      output_paths <- unlist(lapply(ok_chunks, function(res) res$paths))
    } else {
      temp_files <- vapply(ok_chunks, function(res) res$filepath, character(1))
      on.exit(unlink(temp_files), add = TRUE)
      all_names <- unlist(lapply(ok_chunks, function(res) res$layer_names))

      log_msg("  Merging chunks into final multi-band stack...")
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
      r_out <- terra::classify(r_all, cbind(NA, -9999))
      r_out <- assign_raster_metadata(r_out, var, current_unit_conv)

      suppressWarnings(terra::writeRaster(r_out, out_path, overwrite = TRUE, NAflag = -9999))
      output_paths <- out_path
    }

    if (length(failed_urls) > 0) {
      failed_csv <- file.path(var_folder, paste0(var, "_failed_layers.csv"))
      utils::write.csv(
        data.frame(
          variable = var,
          failed_url = failed_urls,
          stringsAsFactors = FALSE
        ),
        failed_csv, row.names = FALSE, quote = TRUE
      )
      log_msg(sprintf("  %d layer(s) failed for %s; logged to %s",
                      length(failed_urls), var, failed_csv))
    }

    log_msg(sprintf("  Variable %s completed in %.1f seconds",
                    var, (proc.time() - t0_var)[["elapsed"]]))
    return(list(
      status = "ok",
      variable = var,
      output_paths = output_paths,
      failed_layers = failed_urls,
      n_ok_chunks = length(ok_chunks),
      n_failed_chunks = length(failed_chunks)
    ))
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
