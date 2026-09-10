# =============================================================================
# Multi-Season Comparison Functions
# =============================================================================

#' Compare Multiple Season Analysis Results
#'
#' Creates a comparative table and visualizations for multiple seasons.
#'
#' @param season_results Named list. Each element is an analysis result from
#'   wapor_analysis_pipeline() or mod_analysis. Names are season labels.
#' @param indicators Character vector. Indicators to compare 
#'   (e.g., c("AETI", "ETc", "Adequacy", "Yield")).
#' @param by Character. "overall" (mean across all classes) or "class" (per-class comparison).
#' @return A data.frame with comparative statistics.
#' @export
#' @examples
#' \dontrun{
#' results_list <- list(
#'   "Winter 2023" = winter_2023_results,
#'   "Winter 2024" = winter_2024_results
#' )
#' comparison <- wapor_compare_seasons(results_list, 
#'                                     indicators = c("AETI", "ETc", "Yield"))
#' print(comparison)
#' }
wapor_compare_seasons <- function(season_results, 
                                  indicators = c("AETI", "ETc", "Adequacy"),
                                  by = "overall") {
  
  if (!is.list(season_results) || length(season_results) < 2) {
    stop("season_results must be a named list with at least 2 elements", call. = FALSE)
  }
  
  if (is.null(names(season_results))) {
    names(season_results) <- sprintf("Season_%d", seq_along(season_results))
  }
  
  if (by == "overall") {
    .compare_seasons_overall(season_results, indicators)
  } else if (by == "class") {
    .compare_seasons_by_class(season_results, indicators)
  } else {
    stop("by must be 'overall' or 'class'", call. = FALSE)
  }
}

.compare_seasons_overall <- function(season_results, indicators) {
  rows <- list()
  
  for (season_name in names(season_results)) {
    res <- season_results[[season_name]]
    
    row <- data.frame(
      Season = season_name,
      stringsAsFactors = FALSE
    )
    
    # Extract period if available
    if (!is.null(res$config)) {
      row$Start_Date <- res$config$period[1]
      row$End_Date <- res$config$period[2]
    }
    
    # AETI
    if ("AETI" %in% indicators && !is.null(res$seasonal_aeti)) {
      row$AETI_mm <- .extract_overall_mean(res$seasonal_aeti, res$valid_crop_mask)
    }
    
    # RET
    if ("RET" %in% indicators && !is.null(res$seasonal_ret)) {
      row$RET_mm <- .extract_overall_mean(res$seasonal_ret, res$valid_crop_mask)
    }
    
    # ETc
    if ("ETc" %in% indicators && !is.null(res$etc_by_class)) {
      etc_values <- vapply(res$etc_by_class, function(x) {
        .masked_global_mean(x$etc_seasonal, NULL)
      }, numeric(1))
      row$ETc_mm <- mean(etc_values, na.rm = TRUE)
    }
    
    # Adequacy
    if ("Adequacy" %in% indicators) {
      if (!is.null(res$adequacy_etc)) {
        row$Adequacy_pct <- .masked_global_mean(res$adequacy_etc, res$valid_crop_mask) * 100
      } else if (!is.null(res$adequacy_p95)) {
        row$Adequacy_pct <- .masked_global_mean(res$adequacy_p95, res$valid_crop_mask) * 100
      }
    }
    
    # Biomass
    if ("Biomass" %in% indicators && !is.null(res$seasonal_biomass_t)) {
      row$Biomass_t_ha <- .masked_global_mean(res$seasonal_biomass_t, res$valid_crop_mask)
    }
    
    # Yield
    if ("Yield" %in% indicators && !is.null(res$yield_by_class)) {
      yield_values <- vapply(res$yield_by_class, function(x) {
        terra::global(x, "mean", na.rm = TRUE)$mean
      }, numeric(1))
      row$Yield_t_ha <- mean(yield_values, na.rm = TRUE)
    }
    
    # CWP/BWP
    if ("CWP" %in% indicators && !is.null(res$cwp)) {
      row$CWP_kg_m3 <- res$cwp
    }
    
    if ("BWP" %in% indicators && !is.null(res$bwp)) {
      row$BWP_kg_m3 <- res$bwp
    }
    
    rows[[season_name]] <- row
  }
  
  comparison_table <- do.call(rbind, rows)
  rownames(comparison_table) <- NULL
  
  # Add change columns if 2 seasons
  if (nrow(comparison_table) == 2) {
    comparison_table <- .add_change_columns(comparison_table)
  }
  
  comparison_table
}

.compare_seasons_by_class <- function(season_results, indicators) {
  # Get all unique classes across seasons
  all_classes <- unique(unlist(lapply(season_results, function(res) {
    if (!is.null(res$crop_params)) res$crop_params$class_value else NULL
  })))
  
  if (length(all_classes) == 0) {
    stop("No crop classes found in any season results", call. = FALSE)
  }

  # Optimization: Pre-compute per-class zonal adequacy statistics once per season using terra::zonal.
  # This replaces per-class terra::ifel conditional raster masking and multiplication inside nested loops
  # with O(1) zonal mean lookups, avoiding high memory and SpatRaster allocation overhead.
  adeq_by_season <- list()
  if ("Adequacy" %in% indicators) {
    for (season_name in names(season_results)) {
      res <- season_results[[season_name]]
      if (!is.null(res$adequacy_etc) && !is.null(res$h_mask)) {
        z_df <- terra::zonal(res$adequacy_etc, res$h_mask, fun = "mean", na.rm = TRUE)
        if (nrow(z_df) > 0) {
          adeq_by_season[[season_name]] <- stats::setNames(
            as.numeric(z_df[[2]]),
            as.character(as.integer(z_df[[1]]))
          )
        }
      }
    }
  }
  
  rows <- list()
  
  for (cls in all_classes) {
    cls_str <- as.character(cls)
    for (season_name in names(season_results)) {
      res <- season_results[[season_name]]
      
      # Check if this class exists in this season
      if (is.null(res$crop_params) || !cls %in% res$crop_params$class_value) {
        next
      }
      
      # Get crop label
      crop_label <- res$crop_params$crop_label[res$crop_params$class_value == cls][1]
      
      row <- data.frame(
        Class = cls,
        Crop = crop_label,
        Season = season_name,
        stringsAsFactors = FALSE
      )
      
      # AETI
      if ("AETI" %in% indicators && !is.null(res$seasonal_aeti$by_class)) {
        aeti_row <- res$seasonal_aeti$by_class[res$seasonal_aeti$by_class$class_value == cls, ]
        if (nrow(aeti_row) > 0) {
          row$AETI_mm <- aeti_row$mean_seasonal_aeti[1]
        }
      }
      
      # ETc
      if ("ETc" %in% indicators && !is.null(res$etc_by_class)) {
        if (cls_str %in% names(res$etc_by_class)) {
          row$ETc_mm <- .masked_global_mean(res$etc_by_class[[cls_str]]$etc_seasonal, NULL)
        }
      }
      
      # Adequacy
      if ("Adequacy" %in% indicators && !is.null(adeq_by_season[[season_name]])) {
        if (cls_str %in% names(adeq_by_season[[season_name]])) {
          row$Adequacy_pct <- adeq_by_season[[season_name]][[cls_str]] * 100
        }
      }
      
      # Biomass
      if ("Biomass" %in% indicators && !is.null(res$seasonal_biomass_by_class)) {
        bio_row <- res$seasonal_biomass_by_class[
          res$seasonal_biomass_by_class$class_value == cls, 
        ]
        if (nrow(bio_row) > 0) {
          row$Biomass_t_ha <- bio_row$mean_seasonal_biomass_t[1]
        }
      }
      
      # Yield
      if ("Yield" %in% indicators && !is.null(res$yield_by_class)) {
        cls_str <- as.character(cls)
        if (cls_str %in% names(res$yield_by_class)) {
          row$Yield_t_ha <- terra::global(res$yield_by_class[[cls_str]], 
                                          "mean", na.rm = TRUE)$mean
        }
      }
      
      rows[[paste(cls, season_name, sep = "_")]] <- row
    }
  }
  
  comparison_table <- do.call(rbind, rows)
  rownames(comparison_table) <- NULL
  
  comparison_table
}

.extract_overall_mean <- function(seasonal_result, crop_mask) {
  if (is.list(seasonal_result) && "raster" %in% names(seasonal_result)) {
    .masked_global_mean(seasonal_result$raster, crop_mask)
  } else if (inherits(seasonal_result, "SpatRaster")) {
    .masked_global_mean(seasonal_result, crop_mask)
  } else {
    NA_real_
  }
}

.masked_global_mean <- function(r, mask_rast = NULL) {
  if (is.null(r)) return(NA_real_)
  target <- if (is.null(mask_rast)) r else r * mask_rast
  terra::global(target, "mean", na.rm = TRUE)$mean
}

.add_change_columns <- function(comparison_table) {
  if (nrow(comparison_table) != 2) return(comparison_table)
  
  numeric_cols <- names(comparison_table)[sapply(comparison_table, is.numeric)]
  numeric_cols <- setdiff(numeric_cols, c("Start_Date", "End_Date"))
  
  for (col in numeric_cols) {
    val1 <- comparison_table[[col]][1]
    val2 <- comparison_table[[col]][2]
    
    if (!is.na(val1) && !is.na(val2) && val1 != 0) {
      change_col_name <- paste0(col, "_Change_pct")
      comparison_table[[change_col_name]] <- c(NA, ((val2 - val1) / val1) * 100)
    }
  }
  
  comparison_table
}

#' Trend Analysis Across Multiple Seasons
#'
#' Computes linear trends for indicators across multiple seasons (3+).
#'
#' @param season_results Named list. Analysis results, names should be sortable chronologically.
#' @param indicator Character. Single indicator to analyze trend 
#'   (e.g., "AETI", "ETc", "Yield").
#' @param by Character. "overall" or "class".
#' @return A list with trend statistics and optionally a plot.
#' @export
wapor_trend_analysis <- function(season_results, indicator = "AETI", by = "overall") {
  
  if (length(season_results) < 3) {
    stop("Trend analysis requires at least 3 seasons", call. = FALSE)
  }
  
  # Extract values
  comparison <- wapor_compare_seasons(season_results, indicators = indicator, by = by)
  
  if (by == "overall") {
    .trend_overall(comparison, indicator)
  } else {
    .trend_by_class(comparison, indicator)
  }
}

.trend_overall <- function(comparison, indicator) {
  # Map indicator to column name
  col_map <- c(
    "AETI" = "AETI_mm",
    "RET" = "RET_mm",
    "ETc" = "ETc_mm",
    "Adequacy" = "Adequacy_pct",
    "Biomass" = "Biomass_t_ha",
    "Yield" = "Yield_t_ha",
    "CWP" = "CWP_kg_m3",
    "BWP" = "BWP_kg_m3"
  )
  
  col_name <- col_map[indicator]
  if (is.na(col_name) || !col_name %in% names(comparison)) {
    stop(sprintf("Indicator '%s' not found in comparison data", indicator), call. = FALSE)
  }
  
  values <- comparison[[col_name]]
  x <- seq_along(values)
  
  # Linear model
  fit <- lm(values ~ x)
  
  list(
    indicator = indicator,
    seasons = comparison$Season,
    values = values,
    trend = "overall",
    slope = coef(fit)[2],
    intercept = coef(fit)[1],
    r_squared = summary(fit)$r.squared,
    p_value = summary(fit)$coefficients[2, 4],
    model = fit
  )
}

.trend_by_class <- function(comparison, indicator) {
  col_map <- c(
    "AETI" = "AETI_mm",
    "ETc" = "ETc_mm",
    "Adequacy" = "Adequacy_pct",
    "Biomass" = "Biomass_t_ha",
    "Yield" = "Yield_t_ha"
  )
  
  col_name <- col_map[indicator]
  if (is.na(col_name) || !col_name %in% names(comparison)) {
    stop(sprintf("Indicator '%s' not found in comparison data", indicator), call. = FALSE)
  }
  
  # Analyze each class separately
  classes <- unique(comparison$Class)
  trends <- list()
  
  for (cls in classes) {
    class_data <- comparison[comparison$Class == cls, ]
    values <- class_data[[col_name]]
    x <- seq_along(values)
    
    if (length(values) < 3) next
    
    fit <- lm(values ~ x)
    
    trends[[as.character(cls)]] <- list(
      class = cls,
      crop = class_data$Crop[1],
      seasons = class_data$Season,
      values = values,
      slope = coef(fit)[2],
      intercept = coef(fit)[1],
      r_squared = summary(fit)$r.squared,
      p_value = summary(fit)$coefficients[2, 4]
    )
  }
  
  list(
    indicator = indicator,
    trend = "by_class",
    class_trends = trends
  )
}

#' Export Season Comparison Report
#'
#' Generates a formatted comparison report with tables and summary statistics.
#'
#' @param season_results Named list. Analysis results.
#' @param output_file Character. Path to output CSV file.
#' @param indicators Character vector. Indicators to include.
#' @return Invisibly returns the comparison table.
#' @export
wapor_export_comparison_report <- function(season_results, output_file,
                                           indicators = c("AETI", "ETc", "Adequacy", "Yield")) {
  
  # Overall comparison
  overall <- wapor_compare_seasons(season_results, indicators = indicators, by = "overall")
  
  # Per-class comparison
  by_class <- wapor_compare_seasons(season_results, indicators = indicators, by = "class")
  
  # Write to CSV (with sections)
  cat("=== Overall Season Comparison ===\n", file = output_file)
  suppressWarnings(utils::write.table(overall, file = output_file, append = TRUE,
                                     sep = ",", row.names = FALSE, col.names = TRUE))
  
  cat("\n\n=== Per-Class Comparison ===\n", file = output_file, append = TRUE)
  suppressWarnings(utils::write.table(by_class, file = output_file, append = TRUE,
                                     sep = ",", row.names = FALSE, col.names = TRUE))
  
  message(sprintf("Comparison report saved to: %s", output_file))
  
  invisible(list(overall = overall, by_class = by_class))
}
