# analysis_utils.R
# Internal helper functions for the Shiny analysis module (mod_analysis.R).
# These functions are non-reactive and handle raster/table manipulations.

#' Lazy raster guard for Shiny
#'
#' Checks that a SpatRaster stored in a reactiveVal still has valid layers
#' (temp-file pointers can go stale between upload and use).
#'
#' @param rv A reactiveVal containing a SpatRaster.
#' @param label Character. Label for the notification.
#' @param session Shiny session object for notifications.
#' @return The SpatRaster if valid, otherwise NULL.
#' @keywords internal
wapor_shiny_safe_rast <- function(rv, label = "raster", session = shiny::getDefaultReactiveDomain()) {
  r <- rv()
  if (is.null(r)) return(NULL)
  ok <- tryCatch({ terra::nlyr(r) > 0 }, error = function(e) FALSE)
  if (!ok) {
    if (!is.null(session)) {
      shiny::showNotification(
        sprintf("%s reference expired -- please re-upload the file.", label),
        type = "warning", duration = 8
      )
    }
    rv(NULL)
    return(NULL)
  }
  r
}

#' Build a binary mask for specific crop class values
#'
#' @param mask_rast SpatRaster. The crop mask.
#' @param class_values Integer vector. Values to include in the mask.
#' @return A SpatRaster with 1 for matched classes and NA otherwise.
#' @keywords internal
wapor_build_class_mask <- function(mask_rast, class_values) {
  if (is.null(mask_rast) || length(class_values) == 0) return(NULL)

  match_rast <- mask_rast == as.integer(class_values[1])
  if (length(class_values) > 1) {
    for (cls in class_values[-1]) {
      match_rast <- match_rast | (mask_rast == as.integer(cls))
    }
  }

  terra::ifel(match_rast, 1L, NA)
}

#' Filter class stats to match active crop parameters
#'
#' @param res Analysis results list.
#' @return data.frame of filtered stats.
#' @keywords internal
wapor_filter_class_stats <- function(res) {
  if (is.null(res) || is.null(res$mask_class_stats) || is.null(res$crop_params)) {
    return(NULL)
  }

  stats <- res$mask_class_stats
  stats[stats$class_value %in% res$crop_params$class_value, , drop = FALSE]
}

#' Compute weighted mean over specific classes
#'
#' @param summary_tbl data.frame with class_value and the value to average.
#' @param class_stats data.frame with class_value and pixel_count.
#' @param value_col Character. Column name in summary_tbl to average.
#' @return Numeric weighted mean.
#' @keywords internal
wapor_weighted_class_mean <- function(summary_tbl, class_stats, value_col) {
  if (is.null(summary_tbl) || is.null(class_stats) || nrow(summary_tbl) == 0 || nrow(class_stats) == 0) {
    return(NA_real_)
  }

  merged <- merge(
    summary_tbl,
    class_stats[, c("class_value", "pixel_count"), drop = FALSE],
    by = "class_value",
    all = FALSE
  )
  merged <- merged[
    !is.na(merged[[value_col]]) & !is.na(merged$pixel_count) & merged$pixel_count > 0,
    ,
    drop = FALSE
  ]
  if (nrow(merged) == 0) {
    return(NA_real_)
  }

  stats::weighted.mean(merged[[value_col]], w = merged$pixel_count)
}

#' Compute masked global mean
#'
#' @param r SpatRaster.
#' @param mask_rast SpatRaster. Optional mask.
#' @return Numeric mean.
#' @keywords internal
wapor_masked_global_mean <- function(r, mask_rast = NULL) {
  if (is.null(r)) return(NA_real_)
  target <- if (is.null(mask_rast)) {
    r
  } else {
    r * terra::ifel(is.na(mask_rast), NA, 1L)
  }
  terra::global(target, "mean", na.rm = TRUE)$mean
}

#' Build a table of unique season profiles (start/end combinations)
#'
#' @param crop_mask SpatRaster.
#' @param start_raster SpatRaster.
#' @param end_raster SpatRaster.
#' @param class_values Integer vector.
#' @return data.frame of profiles.
#' @keywords internal
wapor_build_season_profile_table <- function(crop_mask, start_raster, end_raster, class_values) {
  if (is.null(crop_mask) || is.null(start_raster) || is.null(end_raster)) {
    return(data.frame(
      class_value = integer(0),
      start_jd = integer(0),
      end_jd = integer(0),
      total_days = integer(0),
      pixel_count = integer(0)
    ))
  }

  # Combine rasters into a stack to find unique combinations efficiently
  s <- c(crop_mask, start_raster, end_raster)
  names(s) <- c("class_value", "start_jd", "end_jd")

  # terra::unique() is implemented in C++ and handles large rasters via block processing,
  # avoiding the memory crash associated with terra::values().
  profile_df <- terra::unique(s)

  if (is.null(profile_df) || nrow(profile_df) == 0) {
    return(data.frame(
      class_value = integer(0),
      start_jd = integer(0),
      end_jd = integer(0),
      total_days = integer(0),
      pixel_count = integer(0)
    ))
  }

  # Filter by requested classes and handle NAs
  profile_df <- profile_df[!is.na(profile_df$class_value) &
                           !is.na(profile_df$start_jd) &
                           !is.na(profile_df$end_jd), , drop = FALSE]
  
  profile_df <- profile_df[profile_df$class_value %in% class_values, , drop = FALSE]

  if (nrow(profile_df) == 0) {
    return(profile_df)
  }

  # Convert JD values to integers
  profile_df$class_value <- as.integer(profile_df$class_value)
  profile_df$start_jd    <- as.integer(round(profile_df$start_jd))
  profile_df$end_jd      <- as.integer(round(profile_df$end_jd))
  profile_df$total_days  <- profile_df$end_jd - profile_df$start_jd + 1L
  
  # Filter out invalid seasons (end before start)
  profile_df <- profile_df[profile_df$total_days > 0L, , drop = FALSE]

  if (nrow(profile_df) == 0) {
    return(profile_df)
  }

  # For the calculation, we don't strictly need accurate pixel counts per profile
  # as long as we have the unique triples. However, to maintain backward compatibility 
  # with the return schema, we set a placeholder.
  profile_df$pixel_count <- 1L

  return(profile_df)
}

#' Parse Shiny batch input into named season periods
#'
#' @param batch_text Character scalar with one `Label, Start, End` entry per line.
#' @return List with `periods` and `season_table`.
#' @keywords internal
wapor_parse_batch_periods <- function(batch_text) {
  lines <- strsplit(batch_text %||% "", "\\r?\\n", perl = TRUE)[[1]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  if (length(lines) == 0) {
    stop("Batch list is empty. Enter seasons or use Detect Seasons.", call. = FALSE)
  }

  rows <- vector("list", length(lines))
  for (i in seq_along(lines)) {
    parts <- trimws(strsplit(lines[[i]], ",", fixed = TRUE)[[1]])
    if (length(parts) != 3L || any(!nzchar(parts))) {
      stop(
        sprintf("Invalid batch line %d. Use: Label, YYYY-MM-DD, YYYY-MM-DD", i),
        call. = FALSE
      )
    }

    start_date <- tryCatch(as.Date(parts[2]), error = function(e) NA)
    end_date <- tryCatch(as.Date(parts[3]), error = function(e) NA)
    if (is.na(start_date) || is.na(end_date)) {
      stop(sprintf("Invalid date on batch line %d.", i), call. = FALSE)
    }
    if (end_date < start_date) {
      stop(sprintf("End date must be on or after start date on batch line %d.", i), call. = FALSE)
    }

    rows[[i]] <- data.frame(
      label = parts[1],
      start = as.character(start_date),
      end = as.character(end_date),
      stringsAsFactors = FALSE
    )
  }

  season_table <- do.call(rbind, rows)
  if (anyDuplicated(season_table$label)) {
    stop("Batch labels must be unique.", call. = FALSE)
  }

  periods <- stats::setNames(
    lapply(seq_len(nrow(season_table)), function(i) c(season_table$start[i], season_table$end[i])),
    season_table$label
  )

  list(periods = periods, season_table = season_table)
}

#' Detect season windows from local seasonal raster folders
#'
#' @param folder Character path to the project folder.
#' @return List with `seasonal_dirs` and `windows`.
#' @keywords internal
wapor_detect_folder_seasons <- function(folder) {
  if (!is.character(folder) || length(folder) != 1 || !nzchar(folder) || !dir.exists(folder)) {
    stop("Project folder not found.", call. = FALSE)
  }

  subdirs <- list.dirs(folder, full.names = FALSE, recursive = FALSE)
  seasonal_dirs <- subdirs[grepl("_seasonal$", subdirs)]
  if (length(seasonal_dirs) == 0) {
    return(list(seasonal_dirs = character(0), windows = character(0)))
  }

  win_pattern <- "\\.seasonal\\.(?:(.*?)\\.)?(\\d{4}-\\d{2}-\\d{2})_(\\d{4}-\\d{2}-\\d{2})\\.tif$"
  all_windows <- character(0)

  for (sd in seasonal_dirs) {
    tif_files <- tryCatch(
      list.files(file.path(folder, sd), pattern = "\\.tif$", full.names = FALSE, ignore.case = TRUE),
      error = function(e) character(0)
    )
    for (f in tif_files) {
      m <- regmatches(f, regexec(win_pattern, f, perl = TRUE))[[1]]
      if (length(m) < 4) next
      label <- trimws(m[2] %||% "")
      if (!nzchar(label)) {
        label <- sprintf("Season_%s_%s", m[3], m[4])
      }
      label <- gsub(",", "_", label, fixed = TRUE)
      all_windows <- c(all_windows, sprintf("%s, %s, %s", label, m[3], m[4]))
    }
  }

  list(
    seasonal_dirs = seasonal_dirs,
    windows = unique(all_windows)
  )
}

#' Generate an R script for standalone analysis
#'
#' Converts Shiny analysis parameters into a reproducible R script string.
#'
#' @keywords internal
wapor_normalize_analysis_indicators <- function(indicators) {
  if (is.null(indicators) || !length(indicators)) {
    return(character(0))
  }

  indicators <- as.character(indicators)
  indicators[indicators == "peff"] <- "agg_peff"
  unique(indicators[!is.na(indicators) & nzchar(indicators)])
}

#' Generate an R script for standalone analysis
#'
#' Converts Shiny analysis parameters into a reproducible R script string.
#'
#' @param config List of configuration parameters.
#' @param crop_params data.frame of crop parameters.
#' @return Character string (the script).
#' @keywords internal
wapor_generate_shiny_script <- function(config, crop_params) {
  format_r_string <- function(x) {
    paste(deparse(as.character(x)), collapse = "")
  }

  format_character_vector <- function(x) {
    encoded <- vapply(x, format_r_string, character(1))
    paste0("c(", paste(encoded, collapse = ", "), ")")
  }

  format_numeric_vector <- function(x) {
    paste0("c(", paste(format(x, trim = TRUE, scientific = FALSE), collapse = ", "), ")")
  }

  format_logical <- function(x) {
    if (isTRUE(x)) "TRUE" else "FALSE"
  }

  format_scalar <- function(x) {
    if (is.null(x) || (length(x) == 1L && is.na(x)) || !length(x)) {
      "NULL"
    } else if (is.character(x)) {
      format_r_string(x)
    } else if (is.numeric(x)) {
      format(x, trim = TRUE, scientific = FALSE)
    } else if (is.logical(x)) {
      if (isTRUE(x)) "TRUE" else "FALSE"
    } else {
      deparse(x)[1]
    }
  }

  format_period_object <- function(period) {
    if (is.list(period) && length(period) > 0) {
      rows <- vapply(names(period), function(label) {
        dates <- period[[label]]
        safe_label <- gsub("`", "\\\\`", label, fixed = TRUE)
        sprintf("  `%s` = c(%s, %s)", safe_label, format_r_string(dates[1]), format_r_string(dates[2]))
      }, character(1))
      paste(c("list(", paste(rows, collapse = ",\n"), ")"), collapse = "\n")
    } else {
      sprintf("c(%s, %s)", format_r_string(period[1]), format_r_string(period[2]))
    }
  }

  format_aoi_region <- function(region) {
    if (is.null(region) || !length(region)) {
      return("NULL")
    }
    if (is.character(region)) {
      return(format_r_string(region))
    }
    if (is.numeric(region)) {
      return(format_numeric_vector(region))
    }
    "NULL"
  }

  period <- config$period %||% as.character(c(Sys.Date(), Sys.Date()))
  batch_mode <- is.list(period)
  first_period <- if (is.list(period) && length(period) > 0) period[[1]] else period

  ref_year <- config$ref_year
  if (is.null(ref_year) && !batch_mode) {
    ref_year <- as.integer(format(as.Date(first_period[1]), "%Y"))
  }

  aeti_var <- config$aeti_var %||% "L1-AETI-D"
  ret_var <- config$ret_var %||% "L1-RET-D"
  precip_var <- config$precip_var %||% "L1-PCP-D"
  npp_var <- config$npp_var %||% "L1-NPP-D"
  t_var <- config$t_var %||% ""
  folder <- config$folder %||% "analysis_output"
  output_folder <- config$output_folder %||% folder
  data_source <- config$data_source %||% "api"
  l3_code <- config$l3_code %||% config$l3_region
  indicators <- wapor_normalize_analysis_indicators(unique(c(
    config$indicators,
    config$agg_vars,
    config$derived_vars
  )))
  season_label <- config$season_label %||% "Season"
  aoi_region <- config$aoi_region %||% NULL

  params_code <- "data.frame(class_value = integer(0))"
  if (!is.null(crop_params) && nrow(crop_params) > 0) {
    cols <- character()
    for (col in names(crop_params)) {
      val <- if (is.character(crop_params[[col]])) {
        paste0("c(", paste(vapply(crop_params[[col]], format_r_string, character(1)), collapse = ", "), ")")
      } else if (is.integer(crop_params[[col]])) {
        paste0("c(", paste(crop_params[[col]], collapse = "L, "), "L)")
      } else {
        paste0("c(", paste(crop_params[[col]], collapse = ", "), ")")
      }
      cols <- c(cols, sprintf("  %s = %s", col, val))
    }
    params_code <- paste0("data.frame(\n", paste(cols, collapse = ",\n"), "\n)")
  }

  script <- c(
    "library(Rwapor)",
    "library(terra)",
    "",
    "# [1] Paths and area of interest",
    sprintf("project_folder <- %s", format_r_string(folder)),
    sprintf("output_folder  <- %s", format_r_string(output_folder)),
    "if (!dir.exists(output_folder)) dir.create(output_folder, recursive = TRUE)",
    sprintf("aoi_region <- %s", format_aoi_region(aoi_region)),
    "",
    "# [2] Period configuration",
    if (batch_mode) {
      seasons_json <- file.path(folder, "seasons.json")
      json_exists  <- file.exists(seasons_json)
      c(
        if (json_exists) {
          c(
            "# Seasons loaded from project folder seasons.json",
            sprintf("seasons_json <- file.path(project_folder, \"seasons.json\")"),
            "season_list  <- jsonlite::read_json(seasons_json)",
            "periods <- stats::setNames(",
            "  lapply(season_list, function(s) c(s$start, s$end)),",
            "  vapply(season_list, function(s) s$label, character(1))",
            ")",
            "# Alternatively, define seasons manually:",
            paste0("# periods <- ", gsub("\n", "\n# ", format_period_object(period), fixed = TRUE))
          )
        } else {
          c(
            "# Define seasons manually (Label = c(start, end)):",
            paste0("periods <- ", format_period_object(period)),
            "# Tip: save to project folder with:",
            "# season_list <- lapply(names(periods), function(nm) list(label=nm, start=periods[[nm]][1], end=periods[[nm]][2]))",
            "# jsonlite::write_json(season_list, file.path(project_folder, \"seasons.json\"), pretty=TRUE, auto_unbox=TRUE)"
          )
        }
      )
    } else NULL,
    if (!batch_mode) sprintf("period <- %s", format_period_object(period)) else NULL,
    if (!batch_mode) sprintf("ref_year <- %s", format_scalar(ref_year)) else "ref_year <- NULL",
    sprintf("batch_mode <- %s", format_logical(batch_mode)),
    "",
    "# [3] Variables selection",
    sprintf("aeti_var <- %s", format_r_string(aeti_var)),
    sprintf("ret_var  <- %s", format_r_string(ret_var)),
    sprintf("precip_var <- %s", format_r_string(precip_var)),
    sprintf("npp_var    <- %s", format_r_string(npp_var)),
    if (nzchar(t_var)) sprintf("t_var      <- %s", format_r_string(t_var)) else NULL,
    sprintf("l3_code    <- %s", format_scalar(l3_code)),
    sprintf("data_source <- %s", format_r_string(data_source)),
    sprintf("indicators <- %s", format_character_vector(indicators)),
    "",
    "# [4] Crop parameters",
    paste0("crop_params <- ", params_code),
    "",
    "# [5] Input rasters",
    if (isTRUE(config$use_crop_mask)) "crop_mask <- wapor_load_crop_mask(\"path/to/your/crop_mask.tif\")" else "crop_mask <- NULL",
    if (isTRUE(config$use_season_rasters)) "season_start <- wapor_load_season_raster(\"path/to/season_start.tif\")" else "season_start <- NULL",
    if (isTRUE(config$use_season_rasters)) "season_end   <- wapor_load_season_raster(\"path/to/season_end.tif\")" else "season_end <- NULL",
    "",
    "# [6] Analysis configuration",
    "config <- list(",
    if (batch_mode) "  period = periods," else "  period = period,",
    sprintf("  ref_year = %s,", if (batch_mode) "NULL" else format_scalar(ref_year)),
    sprintf("  aeti_var = %s,", format_r_string(aeti_var)),
    sprintf("  ret_var = %s,", format_r_string(ret_var)),
    sprintf("  precip_var = %s,", format_r_string(precip_var)),
    sprintf("  npp_var = %s,", format_r_string(npp_var)),
    sprintf("  t_var = %s,", format_r_string(t_var)),
    sprintf("  data_source = %s,", format_r_string(data_source)),
    sprintf("  l3_code = %s,", format_scalar(l3_code)),
    "  indicators = indicators,",
    "  folder = project_folder,",
    sprintf("  incremental = %s,", format_logical(config$incremental)),
    sprintf("  use_crop_mask = %s,", format_logical(config$use_crop_mask)),
    sprintf("  use_season_rasters = %s", format_logical(config$use_season_rasters)),
    ")",
    "",
    "rasters <- list(",
    "  crop_mask = crop_mask,",
    "  season_start = season_start,",
    "  season_end = season_end",
    ")",
    "",
    "# [7] Run analysis",
    if (identical(data_source, "local")) "# Local mode expects downloaded WaPOR folders under project_folder" else "# API mode streams rasters directly from WaPOR services",
    "results <- wapor_run_seasonal_analysis(",
    "  config = config,",
    "  crop_params = crop_params,",
    "  rasters = rasters,",
    "  aoi_region = aoi_region",
    ")",
    "",
    "# [8] Save outputs",
    sprintf("season_label <- %s", if (batch_mode) "NULL" else format_r_string(season_label)),
    "wapor_export_analysis_outputs(results, output_folder, indicators = indicators, season_label = season_label)",
    "",
    "print(\"Analysis complete!\")"
  )

  return(paste(unlist(script[!vapply(script, is.null, logical(1))]), collapse = "\n"))
}

#' Save Analysis Rasters (Shiny Helper)
#'
#' @param results List of analysis results.
#' @param folder Path to output folder.
#' @param season_label Character label for the season.
#' @param indicators Character vector of indicators to save.
#' @param include_monthly Logical. Include monthly rasters and summaries.
#' @export
wapor_shiny_save_analysis_rasters <- function(results, folder, season_label, indicators,
                                              include_monthly = FALSE) {
  wapor_export_analysis_outputs(
    results = results,
    folder = folder,
    indicators = indicators,
    season_label = season_label,
    include_dekadal = FALSE,
    include_monthly = isTRUE(include_monthly),
    include_seasonal_tables = FALSE
  )
}

#' Export Analysis Outputs to Structured Folders
#'
#' @param results List of analysis results from `wapor_run_seasonal_analysis()`.
#' @param folder Path to the base output folder.
#' @param indicators Character vector of indicators that were requested.
#' @param season_label Optional season label for single-season exports.
#' @param include_dekadal Logical. Write aligned dekadal stacks.
#' @param include_monthly Logical. Write monthly PCP/Peff summary CSV files.
#' @param include_seasonal_tables Logical. Write seasonal summary tables as CSV.
#' @export
wapor_export_analysis_outputs <- function(results, folder, indicators = character(0), season_label = NULL,
                                          include_dekadal = TRUE,
                                          include_monthly = TRUE,
                                          include_seasonal_tables = TRUE) {
  indicators <- wapor_normalize_analysis_indicators(indicators)
  if (!dir.exists(folder)) dir.create(folder, recursive = TRUE)

  sanitize_label <- function(x) {
    gsub("[^a-zA-Z0-9_-]", "_", x)
  }

  write_raster <- function(r, out_dir, prefix, suffix) {
    if (!is.null(r)) {
      terra::writeRaster(r, file.path(out_dir, paste0(prefix, "_", suffix, ".tif")), overwrite = TRUE)
    }
  }

  write_table <- function(x, out_dir, prefix, suffix) {
    if (!is.null(x) && is.data.frame(x) && nrow(x) > 0) {
      utils::write.csv(x, file.path(out_dir, paste0(prefix, "_", suffix, ".csv")), row.names = FALSE)
    }
  }

    write_monthly_series <- function(series, out_dir, prefix, suffix) {
      if (is.null(series) || is.null(series$rasters) || length(series$rasters) == 0) return()
      series_dir <- file.path(out_dir, suffix)
      dir.create(series_dir, recursive = TRUE, showWarnings = FALSE)
      for (month_key in names(series$rasters)) {
        month_suffix <- paste0(suffix, "_", gsub("-", "_", month_key))
        write_raster(series$rasters[[month_key]], series_dir, prefix, month_suffix)
      }
    }

  summarize_yield_by_class <- function(results) {
    if (is.null(results$yield_by_class) || length(results$yield_by_class) == 0) {
      return(NULL)
    }

    data.frame(
      class_value = names(results$yield_by_class),
      mean_yield_t_ha = vapply(
        results$yield_by_class,
        function(r) wapor_masked_global_mean(r),
        numeric(1)
      ),
      stringsAsFactors = FALSE
    )
  }

  build_summary_metrics <- function(results) {
    metrics <- list(
      cwp = results$cwp %||% NA_real_,
      bwp = results$bwp %||% NA_real_
    )
    data.frame(
      metric = names(metrics),
      value = as.numeric(unlist(metrics, use.names = FALSE)),
      stringsAsFactors = FALSE
    )
  }

  export_single <- function(results, folder, season_label) {
    prefix <- if (!is.null(season_label) && nzchar(season_label)) {
      sanitize_label(season_label)
    } else "analysis"

    season_dir <- if (!is.null(season_label) && nzchar(season_label)) {
      file.path(folder, prefix)
    } else {
      folder
    }
    if (!dir.exists(season_dir)) dir.create(season_dir, recursive = TRUE)

    seasonal_raster_dir <- file.path(season_dir, "seasonal_rasters")
    seasonal_table_dir <- file.path(season_dir, "seasonal_tables")
    dekadal_dir <- file.path(season_dir, "dekadal_stacks")
    monthly_dir <- file.path(season_dir, "monthly_summaries")
    monthly_raster_dir <- file.path(season_dir, "monthly_rasters")

    dir.create(seasonal_raster_dir, recursive = TRUE, showWarnings = FALSE)
    if (include_seasonal_tables) dir.create(seasonal_table_dir, recursive = TRUE, showWarnings = FALSE)
    if (include_dekadal) dir.create(dekadal_dir, recursive = TRUE, showWarnings = FALSE)
    if (include_monthly) dir.create(monthly_dir, recursive = TRUE, showWarnings = FALSE)
    if (include_monthly) dir.create(monthly_raster_dir, recursive = TRUE, showWarnings = FALSE)

    write_raster(results$seasonal_aeti$raster, seasonal_raster_dir, prefix, "seasonal_aeti")
    write_raster(results$seasonal_ret$raster, seasonal_raster_dir, prefix, "seasonal_ret")
    write_raster(results$seasonal_pcp, seasonal_raster_dir, prefix, "seasonal_pcp")
    write_raster(results$seasonal_peff, seasonal_raster_dir, prefix, "seasonal_peff")
    write_raster(results$seasonal_t$raster, seasonal_raster_dir, prefix, "seasonal_transpiration")
    write_raster(results$beneficial_fraction, seasonal_raster_dir, prefix, "beneficial_fraction")
    write_raster(results$green_water, seasonal_raster_dir, prefix, "green_water")
    write_raster(results$blue_water, seasonal_raster_dir, prefix, "blue_water")
    write_raster(results$yield_raster, seasonal_raster_dir, prefix, "yield_raster_t_ha")

    if (any(c("agg_biomass_kg", "yield_npp") %in% indicators)) {
      write_raster(results$seasonal_biomass_kg, seasonal_raster_dir, prefix, "seasonal_biomass_kg_ha")
    }
    if (any(c("agg_biomass_t", "yield_npp") %in% indicators)) {
      write_raster(results$seasonal_biomass_t, seasonal_raster_dir, prefix, "seasonal_biomass_t_ha")
    }

    write_raster(results$adequacy_etc, seasonal_raster_dir, prefix, "adequacy_etc")
    write_raster(results$adequacy_p95, seasonal_raster_dir, prefix, "adequacy_p95")

    if (!is.null(results$etc_by_class)) {
      for (cls in names(results$etc_by_class)) {
        write_raster(results$etc_by_class[[cls]]$etc_seasonal, seasonal_raster_dir, prefix, paste0("etc_class_", cls))
      }
    }

    if (include_seasonal_tables) {
      write_table(results$seasonal_aeti$by_class, seasonal_table_dir, prefix, "seasonal_aeti_by_class")
      write_table(results$seasonal_ret$by_class, seasonal_table_dir, prefix, "seasonal_ret_by_class")
      write_table(results$seasonal_biomass_by_class, seasonal_table_dir, prefix, "seasonal_biomass_by_class")
      write_table(results$p95_table, seasonal_table_dir, prefix, "p95_table")
      write_table(results$mask_class_stats, seasonal_table_dir, prefix, "mask_class_stats")
      write_table(summarize_yield_by_class(results), seasonal_table_dir, prefix, "yield_by_class")
      write_table(build_summary_metrics(results), seasonal_table_dir, prefix, "summary_metrics")
    }

    if (include_dekadal && !is.null(results$dekadal_stacks)) {
      for (nm in names(results$dekadal_stacks)) {
        stack <- results$dekadal_stacks[[nm]]
        if (!is.null(stack)) {
          stack_copy <- stack
          if (!is.null(results$dekad_table) && nrow(results$dekad_table) == terra::nlyr(stack_copy)) {
            names(stack_copy) <- as.character(results$dekad_table$dekad_key)
          }
          write_raster(stack_copy, dekadal_dir, prefix, paste0("dekadal_", nm))
        }
      }
    }

    if (include_monthly) {
      write_monthly_series(results$monthly_aeti, monthly_raster_dir, prefix, "monthly_aeti")
      write_monthly_series(results$monthly_ret, monthly_raster_dir, prefix, "monthly_ret")
      write_monthly_series(results$monthly_t, monthly_raster_dir, prefix, "monthly_t")
      write_monthly_series(results$monthly_etc, monthly_raster_dir, prefix, "monthly_etc")
      write_monthly_series(results$monthly_green_water, monthly_raster_dir, prefix, "monthly_green_water")
      write_monthly_series(results$monthly_blue_water, monthly_raster_dir, prefix, "monthly_blue_water")

      if (!is.null(results$monthly_precip_peff)) {
        write_monthly_series(list(rasters = results$monthly_precip_peff$monthly_pcp), monthly_raster_dir, prefix, "monthly_pcp")
        write_monthly_series(list(rasters = results$monthly_precip_peff$monthly_peff), monthly_raster_dir, prefix, "monthly_peff")
      }

      write_table(results$monthly_precip_peff$summary, monthly_dir, prefix, "monthly_pcp_peff")
      write_table(results$monthly_aeti$summary, monthly_dir, prefix, "monthly_aeti")
      write_table(results$monthly_ret$summary, monthly_dir, prefix, "monthly_ret")
      write_table(results$monthly_t$summary, monthly_dir, prefix, "monthly_t")
      write_table(results$monthly_etc$summary, monthly_dir, prefix, "monthly_etc")
      write_table(results$monthly_green_water$summary, monthly_dir, prefix, "monthly_green_water")
      write_table(results$monthly_blue_water$summary, monthly_dir, prefix, "monthly_blue_water")
    }
  }

  # Handle list of results (multi-period)
  if (is.list(results) && !is.null(results[[1]]) && !is.null(results[[1]]$h_mask)) {
    for (s_name in names(results)) {
      export_single(results[[s_name]], folder, s_name)
    }
    return(invisible(TRUE))
  }

  export_single(results, folder, season_label)
  invisible(TRUE)
}
