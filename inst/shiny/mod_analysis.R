# mod_analysis.R
# Seasonal analysis workflow.

# Source sub-UI components (assuming they are in the same directory)
# In a package context, these are usually sourced by the main app or the package loader.
# For local development/testing, we source them here.
.wapor_source_shiny_module <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Missing Shiny module file: %s", path), call. = FALSE)
  }

  tryCatch(
    source(path, local = TRUE),
    error = function(e) {
      stop(sprintf("Failed to source '%s': %s", path, e$message), call. = FALSE)
    }
  )
}

.wapor_source_shiny_module("mod_analysis_ui_sidebar.R")
.wapor_source_shiny_module("mod_analysis_ui_body.R")

mod_analysis_ui <- function(id, all_vars, l3_region_choices) {
  ns <- shiny::NS(id)

  bslib::layout_sidebar(
    sidebar = mod_analysis_ui_sidebar(ns, all_vars, l3_region_choices),
    mod_analysis_ui_body(ns)
  )
}

mod_analysis_server <- function(id, global_folder, aoi_region, download_seasons = shiny::reactive(list())) {
  shiny::moduleServer(id, function(input, output, session) {
    # Phase 2: Missing data state
    temp_missing_info <- shiny::reactiveVal(NULL)
    
    # Favorites logic
    favs <- shiny::reactiveVal(Rwapor::wapor_get_favorites())
    
    output$an_favorite_btn_ui <- shiny::renderUI({
      path <- input$an_folder %||% ""
      is_fav <- Rwapor::wapor_is_favorite(path)
      
      shiny::actionLink(
        session$ns("an_favorite_btn"),
        NULL,
        icon = if (is_fav) shiny::icon("star", style = "color: #ffc107;") else shiny::icon("star"),
        style = "margin-bottom: 11px; font-size: 1.1rem;"
      )
    })
    
    shiny::observeEvent(input$an_favorite_btn, {
      path <- input$an_folder %||% ""
      if (!nzchar(path)) return()
      
      if (Rwapor::wapor_is_favorite(path)) {
        Rwapor::wapor_remove_favorite(path)
      } else {
        Rwapor::wapor_add_favorite(path, type = "directory")
      }
      favs(Rwapor::wapor_get_favorites())
    })
    
    output$an_favorites_ui <- shiny::renderUI({
      f <- favs()
      f_dirs <- f[f$type == "directory", "path"]
      if (length(f_dirs) == 0) return(NULL)

      display_names <- stats::setNames(f_dirs, paste("\U0001F4C2", basename(f_dirs)))
      shiny::tagList(
        shiny::tags$span("Saved folders", class = "fav-section-label"),
        shiny::selectizeInput(
          session$ns("an_quick_fav"),
          NULL,
          choices = c("Select a saved folder..." = "", display_names),
          options = list(placeholder = "Select a saved folder...")
        )
      )
    })

    shiny::observeEvent(input$an_quick_fav, {
      path <- input$an_quick_fav
      if (nzchar(path)) {
        shiny::updateTextInput(session, "an_folder", value = path)
        shiny::updateSelectizeInput(session, "an_quick_fav", selected = "")
      }
    })

    # ── Analysis folder status badge + create-on-demand button ───────────
    an_folder_exists_status <- shiny::reactive({
      path <- trimws(input$an_folder %||% "")
      if (!nzchar(path)) return("empty")
      if (dir.exists(path)) "exists" else "missing"
    })

    output$an_folder_status_ui <- shiny::renderUI({
      switch(an_folder_exists_status(),
        "exists"  = shiny::span(
          class = "folder-status-badge exists",
          shiny::icon("circle-check"), " Folder exists"
        ),
        "missing" = shiny::span(
          class = "folder-status-badge missing",
          shiny::icon("circle-plus"), " Will be created on run"
        ),
        NULL
      )
    })

    shiny::observe({
      if (an_folder_exists_status() == "missing") {
        shinyjs::show("an_create_folder_btn")
      } else {
        shinyjs::hide("an_create_folder_btn")
      }
    })

    shiny::observeEvent(input$an_create_folder_btn, {
      path <- trimws(input$an_folder %||% "")
      if (!nzchar(path)) return()
      tryCatch({
        dir.create(path, recursive = TRUE, showWarnings = FALSE)
        if (dir.exists(path)) {
          shiny::showNotification(
            sprintf("Folder created: %s", path),
            type = "message", duration = 5
          )
        }
      }, error = function(e) {
        shiny::showNotification(paste("Could not create folder:", e$message), type = "error")
      })
    })
    
    # --- NEW: Observer for Missing Data Download Button ---
    shiny::observeEvent(input$an_download_missing_btn, {
      missing_info <- temp_missing_info()
      folder <- project_folder()
      shiny::removeModal()
      
      if (is.null(missing_info) || length(missing_info) == 0) return()
      
      # Determine if we should mask based on analysis setting
      do_mask <- isTRUE(input$an_use_crop_mask)
      
      shiny::withProgress(message = "Downloading Missing Data", value = 0, {
        tryCatch({
          # Resolve extent: AOI > Crop Mask
          reg <- aoi_region()
          if (is.null(reg)) {
            cm <- an_crop_mask_rast()
            if (!is.null(cm)) {
              shiny::incProgress(0.05, detail = "Resolving extent from crop mask...")
              cm_ext <- terra::ext(cm)
              cm_poly <- terra::as.polygons(cm_ext, crs = terra::crs(cm))
              terra::values(cm_poly) <- NULL  # Clear NA attributes
              cm_poly_4326 <- Rwapor::wapor_safe_project(cm_poly, "EPSG:4326")
              e <- terra::ext(cm_poly_4326)
              reg <- c(e$xmin, e$ymin, e$xmax, e$ymax)
            }
          }
          
          if (is.null(reg)) {
            stop("Could not resolve an AOI or Crop Mask extent for the download.")
          }
          
          season_names <- names(missing_info)
          total_downloads <- sum(vapply(missing_info, length, integer(1)))
          completed <- 0L

          for (season_name in season_names) {
            vars <- names(missing_info[[season_name]])
            for (v in vars) {
              dates <- missing_info[[season_name]][[v]]
              period_v <- c(as.character(dates[1]), as.character(dates[length(dates)]))
              completed <- completed + 1L

              shiny::incProgress(
                0.1 + (0.8 * completed / max(total_downloads, 1L)),
                detail = sprintf("Downloading %s for %s...", v, season_name)
              )

              Rwapor::wapor_map(
                variable = v,
                period = period_v,
                region = reg,
                mask = do_mask,
                folder = folder,
                separate_files = TRUE
              )
            }
          }
          
          # Refresh local variables list automatically
          shiny::incProgress(0.95, detail = "Refreshing local database...")
          new_vars <- Rwapor::wapor_scan_local(folder)
          an_local_vars(new_vars)
          
          shiny::showNotification(
            sprintf("Download complete! Files saved in their respective subfolders within: %s. Project folder re-scanned.", folder), 
            type = "message", 
            duration = 20
          )
        }, error = function(e) {
          shiny::showNotification(paste("Download failed:", e$message), type = "error", duration = 15)
        })
      })
    })

    ns <- session$ns
    roots <- get_shinyfiles_roots()

    shinyFiles::shinyDirChoose(input, "an_browse_folder", roots = roots, session = session)
    shinyFiles::shinyDirChoose(input, "an_browse_project_folder", roots = roots, session = session)
    shinyFiles::shinyFileChoose(input, "an_browse_template", roots = roots, session = session, filetypes = c("tif", "tiff"))
    
    shiny::observeEvent(input$an_browse_folder, {
      dir_path <- shinyFiles::parseDirPath(roots, input$an_browse_folder)
      if (length(dir_path) == 1 && nzchar(dir_path)) {
        shiny::updateTextInput(session, "an_folder", value = dir_path)
      }
    })

    shiny::observeEvent(input$an_browse_project_folder, {
      dir_path <- shinyFiles::parseDirPath(roots, input$an_browse_project_folder)
      if (length(dir_path) == 1 && nzchar(dir_path)) {
        shiny::updateTextInput(session, "an_project_folder", value = dir_path)
      }
    })

    shiny::observeEvent(input$an_browse_template, {
      file_info <- shinyFiles::parseFilePaths(roots, input$an_browse_template)
      if (nrow(file_info) > 0) {
        path <- file_info$datapath[1]
        # Update dropdown with this file as the selection
        current_choices <- isolate(input$an_mask_template_file)
        new_choices <- unique(c(path, current_choices))
        shiny::updateSelectizeInput(session, "an_mask_template_file", 
                                   choices = c("Auto-detect" = "", new_choices),
                                   selected = path,
                                   server = TRUE)
      }
    })

    # Keep the project-folder field aligned with the Download tab when shared mode is active.
    shiny::observe({
      folder <- trimws(global_folder() %||% "")
      current <- trimws(input$an_project_folder %||% "")
      if ((input$an_project_folder_mode %||% "download") == "download" &&
          nzchar(folder) && !identical(current, folder)) {
        shiny::updateTextInput(session, "an_project_folder", value = folder)
      }
    })

    output_folder_touched <- shiny::reactiveVal(FALSE)
    shiny::observeEvent(input$an_folder, {
      output_folder_touched(TRUE)
    }, ignoreInit = TRUE)

    shiny::observe({
      folder <- trimws(global_folder() %||% "")
      current <- trimws(input$an_folder %||% "")
      if (isTRUE(output_folder_touched())) return()
      if (nzchar(folder) && !identical(current, folder)) {
        shiny::updateTextInput(session, "an_folder", value = folder)
      }
    })

    project_folder <- shiny::reactive({
      mode <- input$an_project_folder_mode %||% "download"
      path <- if (identical(mode, "manual")) {
        trimws(input$an_project_folder %||% "")
      } else {
        trimws(global_folder() %||% "")
      }
      if (nzchar(path)) path else NULL
    })

    analysis_output_folder <- shiny::reactive({
      path <- trimws(input$an_folder %||% "")
      if (nzchar(path)) path else project_folder()
    })

    # Proactively update template dropdown when project folder changes
    shiny::observe({
      folder <- project_folder()
      shiny::req(folder)
      if (dir.exists(folder)) {
        all_tifs <- list.files(folder, pattern = "\\.tif$", recursive = TRUE, full.names = FALSE)
        shiny::updateSelectizeInput(session, "an_mask_template_file", 
                                    choices = c("Auto-detect" = "", all_tifs),
                                    server = TRUE)
      }
    })
    an_crop_mask_rast <- shiny::reactiveVal(NULL)
    an_start_rast     <- shiny::reactiveVal(NULL)
    an_end_rast       <- shiny::reactiveVal(NULL)
    an_crop_classes   <- shiny::reactiveVal(NULL)
    an_crop_params    <- shiny::reactiveVal(NULL)
    an_results        <- shiny::reactiveVal(NULL)
    an_peff_monthly   <- shiny::reactiveVal(NULL)
    an_local_vars     <- shiny::reactiveVal(NULL)
    an_script_text    <- shiny::reactiveVal("# Validate inputs to generate a reusable R script.\n")

    # ── Harmonized-raster cache ──────────────────────────────────────────────
    # Stores list(key, h_mask, h_start, h_end, template_r) so that re-runs
    # with the same period/variable/region skip expensive wapor_harmonize_*
    # calls.  Invalidated when a source raster is re-uploaded.
    .h_cache     <- shiny::reactiveVal(NULL)

    # ── Analysis running flag ────────────────────────────────────────────────
    .an_running  <- shiny::reactiveVal(FALSE)

    analysis_layer_multipliers <- getFromNamespace("get_analysis_layer_multipliers", "Rwapor")

    # (Internal helpers moved to R/analysis_utils.R)

    # --- File Upload Observers ---
    shiny::observeEvent(input$an_season_start, {
      f <- input$an_season_start
      shiny::req(f)
      tryCatch({
        r <- terra::rast(f$datapath)
        an_start_rast(r)
        .h_cache(NULL)  # invalidate harmonization cache
      }, error = function(e) shiny::showNotification(paste("Error loading season start:", e$message), type = "error"))
    })

    shiny::observeEvent(input$an_season_end, {
      f <- input$an_season_end
      shiny::req(f)
      tryCatch({
        r <- terra::rast(f$datapath)
        an_end_rast(r)
        .h_cache(NULL)  # invalidate harmonization cache
      }, error = function(e) shiny::showNotification(paste("Error loading season end:", e$message), type = "error"))
    })

    # --- Local Data Source Logic ---
    
    # Auto-scan only when the user switches to local mode, not on every folder keystroke
    shiny::observeEvent(input$an_data_source, {
      if (input$an_data_source == "local") {
        folder <- project_folder()
        if (!is.null(folder) && nzchar(folder) && dir.exists(folder)) {
          tryCatch({
            vars_df <- Rwapor::wapor_scan_local(folder)
            an_local_vars(vars_df)
          }, error = function(e) {
            an_local_vars(NULL)
          })
        }
      }
    }, ignoreInit = TRUE)
    
    # Manual scan button
    shiny::observeEvent(input$an_scan_local, {
      folder <- project_folder()
      if (is.null(folder) || !nzchar(folder)) {
        shiny::showNotification(
          "No project folder set. Use the Download tab folder or choose one directly in the Analysis tab.",
          type = "error"
        )
        return()
      }

      if (!dir.exists(folder)) {
        shiny::showNotification(
          sprintf("Folder does not exist: %s", folder),
          type = "error"
        )
        return()
      }

      tryCatch({
        local_vars <- Rwapor::wapor_scan_local(folder)
        an_local_vars(local_vars)

        if (nrow(local_vars) == 0) {
          shiny::showNotification(
            "No WaPOR variable folders found. Download data first using the Download tab.",
            type = "warning"
          )
        } else {
          shiny::showNotification(
            sprintf("Found %d variable(s) with local data.", nrow(local_vars)),
            type = "message"
          )

          # Update variable dropdowns with available local variables
          aeti_vars <- local_vars$variable[grepl("AETI", local_vars$variable)]
          ret_vars <- local_vars$variable[grepl("RET|ET0", local_vars$variable)]
          precip_vars <- local_vars$variable[grepl("PCP|PF", local_vars$variable)]
          npp_vars <- local_vars$variable[grepl("NPP|TBP", local_vars$variable)]

          if (length(aeti_vars) > 0) {
            shiny::updateSelectInput(session, "an_aeti_var",
              choices = aeti_vars,
              selected = aeti_vars[1]
            )
          }
          if (length(ret_vars) > 0) {
            shiny::updateSelectInput(session, "an_ret_var",
              choices = ret_vars,
              selected = ret_vars[1]
            )
          }
          if (length(precip_vars) > 0) {
            shiny::updateSelectInput(session, "an_precip_var",
              choices = precip_vars,
              selected = precip_vars[1]
            )
          }
          if (length(npp_vars) > 0) {
            shiny::updateSelectInput(session, "an_npp_var",
              choices = npp_vars,
              selected = npp_vars[1]
            )
          }

          # Update template dropdown with all .tif files
          all_tifs <- list.files(folder, pattern = "\\.tif$", recursive = TRUE, full.names = FALSE)
          shiny::updateSelectizeInput(session, "an_mask_template_file", 
                                     choices = c("Auto-detect" = "", all_tifs),
                                     server = TRUE)
          
          # Show date range info but DON'T auto-change user's selected period
          # (Users complained that their selected period gets overwritten on rescan)
          if (nrow(local_vars) > 0) {
            all_min <- min(as.Date(local_vars$min_date[!is.na(local_vars$min_date)]), na.rm = TRUE)
            all_max <- max(as.Date(local_vars$max_date[!is.na(local_vars$max_date)]), na.rm = TRUE)
            if (!is.na(all_min) && !is.na(all_max)) {
              shiny::showNotification(
                sprintf("Local data available from %s to %s. Adjust Analysis Period if needed.", 
                        all_min, all_max),
                type = "message",
                duration = 8
              )
            }
          }
        }
      }, error = function(e) {
        shiny::showNotification(
          paste("Error scanning folder:", e$message),
          type = "error"
        )
      })
    })

    output$an_local_vars_info <- shiny::renderPrint({
      local_vars <- an_local_vars()
      folder <- project_folder()
      mode <- input$an_project_folder_mode %||% "download"

      if (is.null(folder) || !nzchar(folder)) {
        cat("Project folder not set.\n")
        cat("Use the Download tab folder or choose one in this Analysis tab.\n")
        return()
      }

      cat("Source:", if (identical(mode, "manual")) "Analysis tab override" else "Download tab shared folder", "\n")
      cat("Folder:", folder, "\n\n")

      if (is.null(local_vars)) {
        cat("Not scanned yet.\n")
        cat("Folder is auto-scanned when switching to local mode.\n")
        cat("Click 'Re-scan Folder' to refresh.\n")
        return()
      }

      if (nrow(local_vars) == 0) {
        cat("No WaPOR variables found.\n")
        cat("Download data first using the Download tab.\n")
        return()
      }

      cat("=== Available Local Variables ===\n\n")
      for (i in seq_len(nrow(local_vars))) {
        v <- local_vars[i, ]
        cat(sprintf("%s:\n", v$variable))
        cat(sprintf("  Files: %d\n", v$file_count))
        if (!is.na(v$min_date) && !is.na(v$max_date)) {
          cat(sprintf("  Coverage: %s to %s\n", v$min_date, v$max_date))
        }
        cat("\n")
      }
      
      cat("Note: Analysis Period can extend beyond available data.\n")
      cat("Validation will warn if data is missing for your selected period.\n")
    })

    # --- Validation ---
    iv <- shinyvalidate::InputValidator$new()
    iv$add_rule("an_ref_year", shinyvalidate::sv_required())
    iv$add_rule("an_ref_year", shinyvalidate::sv_between(2000, 2030))
    iv$add_rule("an_period", function(value) {
      if (length(value) != 2 || any(is.na(value))) return("Select a valid date range.")
      if (value[2] < value[1]) return("End date must be after start date.")
    })
    iv$add_rule("an_aeti_var", shinyvalidate::sv_required())
    iv$add_rule("an_ret_var", shinyvalidate::sv_required())
    iv$add_rule("an_crop_mask", function(value) {
      if (isTRUE(input$an_use_crop_mask) && is.null(value)) "Crop mask is required when enabled."
    })
    iv$add_rule("an_season_start", function(value) {
      if (isTRUE(input$an_use_season_rasters) && is.null(value)) "Season start raster is required when enabled."
    })
    iv$add_rule("an_season_end", function(value) {
      if (isTRUE(input$an_use_season_rasters) && is.null(value)) "Season end raster is required when enabled."
    })
    iv$enable()

    # Control run button state
    shiny::observe({
      shinyjs::toggleState("an_run_btn", condition = iv$is_valid())
    })

    # --- Value Box Renderers ---
    output$vbox_aeti <- shiny::renderText({
      res <- an_results()
      if (is.null(res) || is.null(res$seasonal_aeti)) return("--")

      class_stats <- Rwapor:::wapor_filter_class_stats(res)
      val <- Rwapor:::wapor_weighted_class_mean(res$seasonal_aeti$by_class, class_stats, "mean_seasonal_aeti")
      if (is.na(val)) {
        val <- Rwapor:::wapor_masked_global_mean(res$seasonal_aeti$raster, res$valid_crop_mask)
      }
      sprintf("%.1f mm", val)
    })


    output$vbox_etc <- shiny::renderText({
      res <- an_results()
      if (is.null(res) || is.null(res$etc_by_class)) return("--")

      etc_tbl <- data.frame(
        class_value = as.integer(names(res$etc_by_class)),
        mean_seasonal_etc = vapply(names(res$etc_by_class), function(cls) {
          Rwapor:::wapor_masked_global_mean(res$etc_by_class[[cls]]$etc_seasonal)
        }, numeric(1)),
        stringsAsFactors = FALSE
      )
      val <- Rwapor:::wapor_weighted_class_mean(etc_tbl, Rwapor:::wapor_filter_class_stats(res), "mean_seasonal_etc")
      if (is.na(val)) {
        val <- mean(etc_tbl$mean_seasonal_etc, na.rm = TRUE)
      }

      sprintf("%.1f mm", val)
    })

    output$vbox_adequacy <- shiny::renderText({
      res <- an_results()
      if (is.null(res) || (is.null(res$adequacy_etc) && is.null(res$adequacy_p95))) return("--")
      adq_rast <- res$adequacy_etc %||% res$adequacy_p95
      val <- Rwapor:::wapor_masked_global_mean(adq_rast, res$valid_crop_mask)

      sprintf("%.0f%%", val * 100)
    })

    output$vbox_biomass <- shiny::renderText({
      res <- an_results()
      if (is.null(res) || (is.null(res$seasonal_biomass_by_class) && is.null(res$seasonal_biomass) && is.null(res$biomass))) return("--")

      selected_agg <- input$an_agg_vars %||% character(0)
      unit <- if ("agg_biomass_kg" %in% selected_agg && !"agg_biomass_t" %in% selected_agg) {
        "kg/ha"
      } else if ("agg_biomass_t" %in% selected_agg) {
        "t/ha"
      } else {
        input$an_biomass_unit %||% "kg/ha"
      }

      stats_col <- if (identical(unit, "t/ha")) "mean_seasonal_biomass_t" else "mean_seasonal_biomass_kg"
      bio_rast <- if (identical(unit, "t/ha")) {
        res$seasonal_biomass_t %||% if (!is.null(res$seasonal_biomass)) res$seasonal_biomass / 1000 else NULL
      } else {
        res$seasonal_biomass_kg %||% res$seasonal_biomass %||% res$biomass
      }
      val <- Rwapor:::wapor_weighted_class_mean(res$seasonal_biomass_by_class, Rwapor:::wapor_filter_class_stats(res), stats_col)
      if (is.na(val)) {
        val <- Rwapor:::wapor_masked_global_mean(bio_rast, res$valid_crop_mask)
      }

      sprintf("%.1f %s", val, unit)
    })

    output$vbox_beneficial <- shiny::renderText({
      res <- an_results()
      if (is.null(res) || is.null(res$beneficial_fraction)) return("--")
      val <- Rwapor:::wapor_masked_global_mean(res$beneficial_fraction, res$valid_crop_mask)
      sprintf("%.2f", val)
    })

    current_region <- shiny::reactive(aoi_region())

    build_analysis_state <- function(require_crop_params = TRUE) {
      indicators <- unique(c(input$an_agg_vars, input$an_derived_vars))
      indicators <- indicators[!is.na(indicators) & nzchar(indicators)]
      if (length(indicators) == 0) {
        stop("Select at least one indicator.", call. = FALSE)
      }

      crop_params <- collect_crop_params()
      if (require_crop_params && (is.null(crop_params) || nrow(crop_params) == 0)) {
        stop("No crop class parameters defined.", call. = FALSE)
      }

      batch_mode <- isTRUE(input$an_batch_mode)
      if (batch_mode) {
        period_info <- Rwapor:::wapor_parse_batch_periods(input$an_batch_list)
        periods <- period_info$periods
        season_table <- period_info$season_table
        ref_year <- NULL
      } else {
        period <- as.character(input$an_period)
        if (length(period) != 2 || any(is.na(period))) {
          stop("Select a valid date range.", call. = FALSE)
        }
        season_label <- trimws(input$an_season_label %||% "")
        if (!nzchar(season_label)) season_label <- "Season"
        periods <- period
        season_table <- data.frame(
          label = season_label,
          start = period[1],
          end = period[2],
          stringsAsFactors = FALSE
        )
        ref_year <- input$an_ref_year
      }

      folder <- project_folder()
      output_folder <- analysis_output_folder()
      reg <- current_region()
      period_context <- if (is.list(periods)) periods[[1]] else periods
      vars_to_check <- c(
        input$an_aeti_var %||% "",
        input$an_ret_var %||% "",
        input$an_precip_var %||% "",
        input$an_npp_var %||% "",
        input$an_t_var %||% ""
      )
      any_l3 <- any(grepl("^L3-", vars_to_check[nzchar(vars_to_check)]))
      l3_code <- if (any_l3 && nzchar(input$an_l3_region %||% "")) input$an_l3_region else NULL

      if (is.null(l3_code) && any_l3) {
        cand_reg <- reg
        if (is.null(cand_reg) && isTRUE(input$an_use_crop_mask) && !is.null(an_crop_mask_rast())) {
          cm_rast <- an_crop_mask_rast()
          tryCatch({
            cm_ext <- terra::ext(cm_rast)
            cm_poly <- terra::as.polygons(cm_ext, crs = terra::crs(cm_rast))
            terra::values(cm_poly) <- NULL
            cm_poly_4326 <- Rwapor::wapor_safe_project(cm_poly, "EPSG:4326")
            e_4326 <- terra::ext(cm_poly_4326)
            cand_reg <- c(e_4326$xmin, e_4326$ymin, e_4326$xmax, e_4326$ymax)
          }, error = function(e) NULL)
        }

        if (!is.null(cand_reg)) {
          guess <- tryCatch({
            reg_info_guess <- Rwapor::wapor_parse_region(cand_reg)
            Rwapor::wapor_guess_region(input$an_aeti_var, reg_info_guess, period_context)
          }, error = function(e) NULL)
          if (length(guess) > 0) l3_code <- guess[1]
        }
      }

        config <- list(
        period = periods,
        ref_year = ref_year,
        aeti_var = input$an_aeti_var,
        ret_var = input$an_ret_var,
        precip_var = input$an_precip_var,
        npp_var = input$an_npp_var,
        t_var = input$an_t_var,
          data_source = input$an_data_source,
          l3_code = l3_code,
          folder = folder,
          output_folder = output_folder,
          indicators = indicators,
        agg_vars = input$an_agg_vars,
        derived_vars = input$an_derived_vars,
        incremental = isTRUE(input$an_incremental),
        use_crop_mask = isTRUE(input$an_use_crop_mask),
        use_season_rasters = isTRUE(input$an_use_season_rasters),
        season_label = trimws(input$an_season_label %||% ""),
        aoi_region = reg
      )

      list(
        config = config,
        crop_params = crop_params,
        indicators = indicators,
        batch_mode = batch_mode,
        season_table = season_table,
        periods = periods,
        folder = folder,
        output_folder = output_folder,
        region = reg
      )
    }

    run_analysis_validation <- function(state) {
      validations <- vector("list", nrow(state$season_table))

      for (i in seq_len(nrow(state$season_table))) {
        season_row <- state$season_table[i, ]
        season_config <- state$config
        season_config$period <- c(season_row$start, season_row$end)
        season_config$ref_year <- as.integer(format(as.Date(season_row$start), "%Y"))
        season_config$crop_params <- state$crop_params

        validations[[i]] <- Rwapor::wapor_preflight_check(
          config = season_config,
          data_source = season_config$data_source,
          folder = season_config$folder,
          crop_mask = an_crop_mask_rast(),
          season_start = an_start_rast(),
          season_end = an_end_rast()
        )
      }

      if (!state$batch_mode) {
        return(validations[[1]])
      }

      errors <- character()
      warnings <- character()
      recommendations <- character()
      for (i in seq_along(validations)) {
        season_label <- state$season_table$label[i]
        validation <- validations[[i]]
        if (length(validation$errors) > 0) {
          errors <- c(errors, paste0("[", season_label, "] ", validation$errors))
        }
        if (length(validation$warnings) > 0) {
          warnings <- c(warnings, paste0("[", season_label, "] ", validation$warnings))
        }
        if (length(validation$recommendations) > 0) {
          recommendations <- c(recommendations, paste0("[", season_label, "] ", validation$recommendations))
        }
      }

      list(
        overall = if (length(errors) > 0) "failed" else if (length(warnings) > 0) "warning" else "passed",
        errors = errors,
        warnings = warnings,
        recommendations = unique(recommendations)
      )
    }

    collect_missing_local_data <- function(state) {
      required_vars <- state$config$aeti_var
      if (any(c("agg_ret", "etc", "adequacy_etc") %in% state$indicators)) {
        required_vars <- c(required_vars, state$config$ret_var)
      }
      if (any(c("agg_pcp", "agg_peff", "green_water", "blue_water") %in% state$indicators)) {
        required_vars <- c(required_vars, state$config$precip_var)
      }
      if (
        any(c("agg_biomass_kg", "agg_biomass_t", "yield_npp") %in% state$indicators) ||
        ("cwp_bwp" %in% state$indicators && is.null(input$an_biomass_file))
      ) {
        required_vars <- c(required_vars, state$config$npp_var)
      }
      if (any(c("agg_t", "beneficial_fraction") %in% state$indicators)) {
        required_vars <- c(required_vars, state$config$t_var)
      }

      required_vars <- unique(required_vars[nzchar(required_vars)])
      local_vars <- an_local_vars()
      missing_vars <- required_vars[!required_vars %in% local_vars$variable]
      if (length(missing_vars) > 0) {
        stop(
          sprintf(
            "Required variable(s) not found locally: %s. Download them first or switch to API streaming.",
            paste(missing_vars, collapse = ", ")
          ),
          call. = FALSE
        )
      }

      missing_info <- list()
      for (i in seq_len(nrow(state$season_table))) {
        season_row <- state$season_table[i, ]
        season_missing <- list()
        period_i <- c(season_row$start, season_row$end)
        for (v in required_vars) {
          urls <- Rwapor::wapor_generate_urls(v, l3_region = state$config$l3_code, period = period_i)
          check <- Rwapor::wapor_check_local(urls, v, state$folder)
          if (length(check$missing_dates) > 0) {
            season_missing[[v]] <- check$missing_dates
          }
        }
        if (length(season_missing) > 0) {
          missing_info[[season_row$label]] <- season_missing
        }
      }

      missing_info
    }

    show_missing_local_data_modal <- function(missing_info, folder, local_vars) {
      temp_missing_info(missing_info)

      season_blocks <- vapply(names(missing_info), function(season_label) {
        var_lines <- vapply(names(missing_info[[season_label]]), function(v) {
          dates <- missing_info[[season_label]][[v]]
          sprintf(
            "<li><b>%s</b>: %d dekads missing (%s...%s)</li>",
            v, length(dates), dates[1], dates[length(dates)]
          )
        }, character(1))
        paste0(
          "<li><b>", season_label, "</b><ul>",
          paste(var_lines, collapse = ""),
          "</ul></li>"
        )
      }, character(1))

      diag_lines <- vapply(unique(unlist(lapply(missing_info, names))), function(v) {
        var_row <- local_vars[local_vars$variable == v, ]
        if (nrow(var_row) > 0) {
          sprintf("%s: local data found from %s to %s (%d files)", v, var_row$min_date, var_row$max_date, var_row$file_count)
        } else {
          sprintf("%s: variable folder not found", v)
        }
      }, character(1))

      shiny::showModal(shiny::modalDialog(
        title = "Missing Data Detected",
        shiny::HTML(paste0(
          sprintf("<p>Required rasters were not found in the configured project folder (<b>%s</b>) for one or more seasons:</p>", folder),
          "<ul>", paste(season_blocks, collapse = ""), "</ul>",
          "<p><b>Tip:</b> This can happen if:</p>",
          "<ul>",
          "<li>The analysis periods extend beyond the downloaded data range</li>",
          "<li>Different variables were downloaded for different date ranges</li>",
          "<li>Files were downloaded with a different AOI or region</li>",
          "</ul>",
          "<p><small><b>Local data available:</b><br/>",
          paste(diag_lines, collapse = "<br/>"),
          "</small></p>",
          "<p>Would you like to download the missing dekadal rasters now?</p>",
          sprintf("<p><small><i>Note: The download will use your selected AOI or the crop mask bounding box. Files will be saved in subfolders within <b>%s</b>.</i></small></p>", folder)
        )),
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton(ns("an_download_missing_btn"), "Download Missing Data", class = "btn-success")
        ),
        easyClose = FALSE,
        size = "l"
      ))
    }

    set_script_preview <- function(script_text) {
      an_script_text(script_text)
      shinyAce::updateAceEditor(session, "an_code_preview", value = script_text)
    }

    generate_rwapor_script <- function() {
      state <- build_analysis_state()
      Rwapor:::wapor_generate_shiny_script(config = state$config, crop_params = state$crop_params)
    }

    shiny::observeEvent(input$an_crop_mask, {
      shiny::req(input$an_crop_mask)
      file_path <- input$an_crop_mask$datapath
      file_name <- input$an_crop_mask$name

      # Validate file exists
      if (!file.exists(file_path)) {
        shiny::showNotification(
          sprintf("Uploaded file not found: %s", file_name),
          type = "error"
        )
        an_crop_mask_rast(NULL)
        an_crop_classes(NULL)
        return()
      }

      tryCatch({
        r <- Rwapor::wapor_load_crop_mask(file_path)

        # Validate raster is not empty
        if (is.null(r) || terra::ncell(r) == 0) {
          shiny::showNotification("Crop mask raster is empty or invalid.", type = "error")
          an_crop_mask_rast(NULL)
          an_crop_classes(NULL)
          return()
        }

        an_crop_mask_rast(r)
        .h_cache(NULL)

        # Auto-detect L3 region when an L3 variable is selected
        aeti_v <- shiny::isolate(input$an_aeti_var)
        if (!is.null(aeti_v) && startsWith(aeti_v, "L3-")) {
          tryCatch({
            reg_info      <- Rwapor::wapor_parse_region(file_path)
            period_str    <- as.character(shiny::isolate(input$an_period))
            intersecting  <- Rwapor::wapor_guess_region(aeti_v, reg_info, period_str)
            if (length(intersecting) > 0) {
              shiny::updateSelectInput(session, "an_l3_region", selected = intersecting[1])
              shiny::showNotification(
                sprintf("Auto-matched crop mask to L3 region: %s", intersecting[1]),
                type = "message"
              )
            }
          }, error = function(e) NULL)
        }

        classes <- Rwapor::wapor_extract_crop_classes(r)

        # Check if any valid classes were found
        if (is.null(classes) || nrow(classes) == 0) {
          shiny::showNotification(
            "No valid crop classes found in mask. Check if your raster contains valid class values (not just 0, 255, or nodata).",
            type = "warning",
            duration = 10
          )
          # Create a default single class
          classes <- data.frame(class_value = 1L, pixel_count = NA_integer_, area_ha = NA_real_)
        }

        an_crop_classes(classes)
        an_crop_params(Rwapor::wapor_build_crop_assignments(classes$class_value))
        shiny::showNotification(
          sprintf("Crop mask loaded: %d class(es) found. File: %s", nrow(classes), file_name),
          type = "message"
        )
      }, error = function(e) {
        shiny::showNotification(paste("Error loading crop mask:", e$message), type = "error")
        an_crop_mask_rast(NULL)
        an_crop_classes(NULL)
      })
    })

    shiny::observeEvent(input$an_season_start, {
      shiny::req(input$an_season_start)
      file_path <- input$an_season_start$datapath
      file_name <- input$an_season_start$name

      if (!file.exists(file_path)) {
        shiny::showNotification(
          sprintf("Season start file not found: %s", file_name),
          type = "error"
        )
        an_start_rast(NULL)
        return()
      }

      tryCatch({
        r <- Rwapor::wapor_load_season_raster(file_path)

        if (is.null(r) || terra::ncell(r) == 0) {
          shiny::showNotification("Season start raster is empty or invalid.", type = "error")
          an_start_rast(NULL)
          return()
        }

        # Validate DOY values are reasonable
        vals <- terra::values(r, na.rm = TRUE)
        if (length(vals) == 0) {
          shiny::showNotification("Season start raster contains no valid data.", type = "error")
          an_start_rast(NULL)
          return()
        }

        min_val <- min(vals)
        max_val <- max(vals)

        if (min_val < 1 || max_val > 730) {
          shiny::showNotification(
            sprintf("Season start DOY values (%d-%d) seem unusual. Expected 1-366 (or up to 730 for cross-year).",
                    as.integer(min_val), as.integer(max_val)),
            type = "warning",
            duration = 8
          )
        }

        an_start_rast(r)
        shiny::showNotification(
          sprintf("Season start loaded: DOY range %d-%d. File: %s",
                  as.integer(min_val), as.integer(max_val), file_name),
          type = "message"
        )
      }, error = function(e) {
        shiny::showNotification(paste("Error loading season start:", e$message), type = "error")
        an_start_rast(NULL)
      })
    })

    shiny::observeEvent(input$an_season_end, {
      shiny::req(input$an_season_end)
      file_path <- input$an_season_end$datapath
      file_name <- input$an_season_end$name

      if (!file.exists(file_path)) {
        shiny::showNotification(
          sprintf("Season end file not found: %s", file_name),
          type = "error"
        )
        an_end_rast(NULL)
        return()
      }

      tryCatch({
        r <- Rwapor::wapor_load_season_raster(file_path)

        if (is.null(r) || terra::ncell(r) == 0) {
          shiny::showNotification("Season end raster is empty or invalid.", type = "error")
          an_end_rast(NULL)
          return()
        }

        # Validate DOY values are reasonable
        vals <- terra::values(r, na.rm = TRUE)
        if (length(vals) == 0) {
          shiny::showNotification("Season end raster contains no valid data.", type = "error")
          an_end_rast(NULL)
          return()
        }

        min_val <- min(vals)
        max_val <- max(vals)

        if (min_val < 1 || max_val > 730) {
          shiny::showNotification(
            sprintf("Season end DOY values (%d-%d) seem unusual. Expected 1-366 (or up to 730 for cross-year).",
                    as.integer(min_val), as.integer(max_val)),
            type = "warning",
            duration = 8
          )
        }

        an_end_rast(r)
        shiny::showNotification(
          sprintf("Season end loaded: DOY range %d-%d. File: %s",
                  as.integer(min_val), as.integer(max_val), file_name),
          type = "message"
        )
      }, error = function(e) {
        shiny::showNotification(paste("Error loading season end:", e$message), type = "error")
        an_end_rast(NULL)
      })
    })

    # Load seasons.json from the project folder
    shiny::observeEvent(input$an_load_seasons_json, {
      folder <- project_folder()
      if (is.null(folder) || !nzchar(folder)) {
        shiny::showNotification("Set a project folder first.", type = "warning")
        return()
      }
      path <- file.path(folder, "seasons.json")
      if (!file.exists(path)) {
        shiny::showNotification(
          paste0("seasons.json not found in: ", folder,
                 ". Save seasons from the Download tab first."),
          type = "warning", duration = 10
        )
        return()
      }
      tryCatch({
        season_list <- jsonlite::read_json(path)
        lines <- vapply(season_list, function(s) {
          sprintf("%s, %s, %s", s$label, s$start, s$end)
        }, character(1))
        shiny::updateTextAreaInput(session, "an_batch_list", value = paste(lines, collapse = "\n"))
        shiny::updateCheckboxInput(session, "an_batch_mode", value = TRUE)
        shiny::showNotification(
          sprintf("Loaded %d season(s) from seasons.json.", length(lines)),
          type = "message", duration = 6
        )
      }, error = function(e) {
        shiny::showNotification(paste("Failed to load seasons.json:", e$message), type = "error")
      })
    })

    # Copy seasons from the Download tab into the batch list
    shiny::observeEvent(input$an_copy_from_download, {
      seasons <- download_seasons()
      if (length(seasons) == 0) {
        shiny::showNotification(
          "No multi-season data in the Download tab. Enable Multi-season there and enter seasons first.",
          type = "warning"
        )
        return()
      }
      text <- paste(
        vapply(seq_along(seasons), function(i) {
          nm    <- names(seasons)[i]
          dates <- seasons[[i]]
          sprintf("%s, %s, %s", nm, dates[1], dates[2])
        }, character(1)),
        collapse = "\n"
      )
      shiny::updateTextAreaInput(session, "an_batch_list", value = text)
      shiny::showNotification(
        sprintf("Copied %d season(s) from the Download tab.", length(seasons)),
        type = "message"
      )
    })

    # Batch Mode Season Detection
    shiny::observeEvent(input$an_detect_seasons, {
      folder <- project_folder()
      detection <- tryCatch(
        Rwapor:::wapor_detect_folder_seasons(folder),
        error = function(e) e
      )

      if (inherits(detection, "error")) {
        shiny::showNotification(
          paste("Detect from Folder failed:", detection$message),
          type = "error",
          duration = 12
        )
        return()
      }

      if (length(detection$seasonal_dirs) == 0) {
        shiny::showNotification(
          paste0(
            "No seasonal aggregate folders (*_seasonal) found. ",
            "Either re-download with 'Seasonal aggregate' checked, ",
            "or use 'Copy from Download Tab' if seasons are configured there."
          ),
          type = "message",
          duration = 12
        )
        return()
      }

      if (length(detection$windows) == 0) {
        shiny::showNotification(
          paste0(
            "Seasonal folders exist but filenames don't match the expected pattern ",
            "(WAPOR-3.VAR.seasonal[.Label].YYYY-MM-DD_YYYY-MM-DD.tif). ",
            "Try 'Copy from Download Tab' instead."
          ),
          type = "warning",
          duration = 12
        )
        return()
      }

      shiny::updateTextAreaInput(session, "an_batch_list", value = paste(detection$windows, collapse = "\n"))
      shiny::showNotification(
        sprintf("Detected %d season window(s) from folder.", length(detection$windows)),
        type = "message"
      )
    })

    # --- Custom Timing Column Detection ---
    shiny::observeEvent(input$an_mask_vector, {
      f <- input$an_mask_vector
      shiny::req(f)
      tryCatch({
        # Read names quickly using proxy
        v <- terra::vect(f$datapath, proxy = TRUE)
        cols <- names(v)
        current <- input$an_mask_vector_id_col
        sel <- if (!is.null(current) && current %in% cols) current else if ("id" %in% cols) "id" else if (length(cols) > 0) cols[1] else ""
        shiny::updateSelectInput(session, "an_mask_vector_id_col", choices = c("", cols), selected = sel)
      }, error = function(e) NULL)
    })

    shiny::observeEvent(input$an_mask_csv, {
      f <- input$an_mask_csv
      shiny::req(f)
      tryCatch({
        # Read only headers
        d <- utils::read.csv(f$datapath, nrows = 1, check.names = FALSE)
        cols <- names(d)
        
        upd_csv <- function(input_id, default_name) {
          current <- input[[input_id]]
          sel <- if (!is.null(current) && current %in% cols) current else if (default_name %in% cols) default_name else if (length(cols) > 0) cols[1] else ""
          shiny::updateSelectInput(session, input_id, choices = c("", cols), selected = sel)
        }
        
        upd_csv("an_mask_csv_id_col", "id")
        upd_csv("an_mask_season_col", "season_name")
        upd_csv("an_mask_start_col",  "start_date")
        upd_csv("an_mask_end_col",    "end_date")
        upd_csv("an_mask_crop_col",   "crop_type")
      }, error = function(e) NULL)
    })

    # Custom Timing Mask Generation
    shiny::observeEvent(input$an_generate_masks, {
      shiny::req(input$an_mask_vector, input$an_mask_csv)
      
      folder <- project_folder()
      if (is.null(folder) || !nzchar(folder) || !dir.exists(folder)) {
        shiny::showNotification("Project folder not found. Use the Download tab folder or choose one in Analysis first.", type = "warning")
        return()
      }
      
      shiny::withProgress(message = "Generating timing masks...", value = 0, {
        tryCatch({
          # 1. Get Template Raster
          template_r <- NULL
          local_vars <- an_local_vars()
          folder <- project_folder()
          
          # If not scanned yet, try a quick scan now
          if (is.null(local_vars) && !is.null(folder) && dir.exists(folder)) {
            try({
               local_vars <- Rwapor::wapor_scan_local(folder)
               an_local_vars(local_vars)
            }, silent = TRUE)
          }
          
          # Priority 0: User Selected Template
          selected_template <- input$an_mask_template_file
          if (!is.null(selected_template) && nzchar(selected_template)) {
            # Try as relative path first, then absolute
            template_path <- file.path(folder, selected_template)
            if (!file.exists(template_path)) {
              template_path <- selected_template
            }
            
            if (file.exists(template_path)) {
              template_r <- terra::rast(template_path)
            }
          }
          
          if (is.null(template_r)) {
            if (!is.null(local_vars) && nrow(local_vars) > 0) {
              # Try to find AETI or first available
              best_var <- if (input$an_aeti_var %in% local_vars$variable) input$an_aeti_var else local_vars$variable[1]
              var_folder <- local_vars$folder_path[local_vars$variable == best_var][1]
              files <- list.files(var_folder, pattern = "\\.tif$", full.names = TRUE)
              if (length(files) > 0) template_r <- terra::rast(files[1])
            }
          }
          
          if (is.null(template_r)) {
            # Fallback to API if AOI is set
            reg <- current_region()
            if (is.null(reg)) {
              stop("Could not find a Template Raster. \n\nTo fix this:\n1. Select a region in the AOI tab, OR\n2. Download at least one WaPOR variable to your project folder, OR\n3. Click 'Re-scan Folder' if you already have data.")
            }
            # ... rest of API fallback ...
            reg_info <- Rwapor::wapor_parse_region(reg)
            # Use a dummy recent date
            urls <- Rwapor::wapor_generate_urls(input$an_aeti_var, period = c("2023-01-01", "2023-01-01"))
            if (length(urls) == 0) stop("Could not find template raster via API.")
            template_r <- terra::rast(paste0("/vsicurl/", urls[1]))
            template_r <- Rwapor::wapor_crop_to_region(template_r, reg_info)
          }
          
          shiny::incProgress(0.4, detail = "Rasterizing polygons...")
          
          # 2. Call Generation Function
          # Note: input$an_mask_vector$datapath is the temp file path
          results <- Rwapor::wapor_vector_to_season_rasters(
            vector_path   = input$an_mask_vector$datapath,
            csv_path      = input$an_mask_csv$datapath,
            template_r    = template_r,
            vector_id_col = input$an_mask_vector_id_col,
            csv_id_col    = input$an_mask_csv_id_col,
            season_col    = input$an_mask_season_col,
            start_col     = input$an_mask_start_col,
            end_col       = input$an_mask_end_col,
            crop_col      = if (nzchar(input$an_mask_crop_col)) input$an_mask_crop_col else NULL,
            ref_year      = 1970, # Global historical anchor
            output_folder = file.path(folder, "seasonal_masks")
          )
          
          shiny::incProgress(0.5, detail = "Finalizing...")
          
          shiny::showNotification(
            sprintf("Successfully generated %d seasonal masks in 'seasonal_masks' folder.", nrow(results)),
            type = "message",
            duration = 10
          )
          
        }, error = function(e) {
          shiny::showNotification(paste("Mask generation failed:", e$message), type = "error")
        })
      })
    })

    # Auto-update analysis period from season rasters
    shiny::observe({
      shiny::req(isTRUE(input$an_use_season_rasters))
      s_start <- an_start_rast()
      s_end <- an_end_rast()
      shiny::req(s_start, s_end)
      shiny::req(input$an_ref_year)

      tryCatch({
        vals_start <- terra::values(s_start, na.rm = TRUE)
        vals_end <- terra::values(s_end, na.rm = TRUE)
        if (length(vals_start) > 0 && length(vals_end) > 0) {
          min_doy <- min(vals_start)
          max_doy <- max(vals_end)

          ref_year <- input$an_ref_year
          year_length <- ifelse(lubridate::leap_year(ref_year), 366L, 365L)

          # Handle cross-year seasons properly
          # If max_doy > year_length, it's already in continuous Julian format
          # If min_doy > max_doy, the season crosses the year boundary
          is_cross_year <- (min_doy > max_doy) && (max_doy <= year_length)

          if (is_cross_year) {
            # Season crosses year boundary (e.g., Oct-Jan: start=280, end=30)
            # Convert end DOY to continuous format
            max_doy <- max_doy + year_length
            shiny::showNotification(
              sprintf("Cross-year season detected: DOY %d (year %d) to DOY %d (year %d).",
                      as.integer(min_doy), ref_year, as.integer(max_doy - year_length), ref_year + 1),
              type = "message",
              duration = 6
            )
          }

          date_start <- as.Date(sprintf("%04d-01-01", ref_year)) + (min_doy - 1)
          date_end <- as.Date(sprintf("%04d-01-01", ref_year)) + (max_doy - 1)

          # Validate dates are reasonable
          if (date_end > as.Date(sprintf("%04d-12-31", ref_year + 1))) {
            shiny::showNotification(
              "Season end date exceeds reasonable range. Please check your season raster values.",
              type = "warning"
            )
          }

          # Only update if different to avoid circularity
          current_period <- as.character(input$an_period)
          new_period <- as.character(c(date_start, date_end))
          if (!identical(current_period, new_period)) {
            shiny::updateDateRangeInput(session, "an_period", start = date_start, end = date_end)
          }
        }
      }, error = function(e) {
        # Silently handle errors to avoid interrupting the user
        message("Auto-update of analysis period failed: ", e$message)
      })
    })

    # Validate spatial overlap between crop mask and season rasters
    shiny::observe({
      cm <- an_crop_mask_rast()
      ss <- an_start_rast()
      se <- an_end_rast()

      # Only validate when we have both crop mask and at least one season raster
      if (is.null(cm) || (is.null(ss) && is.null(se))) return()

      tryCatch({
        cm_ext <- terra::ext(cm)
        check_rast <- ss %||% se

        if (!is.null(check_rast)) {
          check_ext <- terra::ext(check_rast)

          # Check for overlap
          has_overlap <- !(cm_ext$xmax <= check_ext$xmin || cm_ext$xmin >= check_ext$xmax ||
                          cm_ext$ymax <= check_ext$ymin || cm_ext$ymin >= check_ext$ymax)

          if (!has_overlap) {
            shiny::showNotification(
              "Warning: Crop mask and season rasters don't appear to overlap spatially. Please ensure all input rasters cover the same geographic area.",
              type = "warning",
              duration = 10
            )
          }
        }
      }, error = function(e) {
        # Silently ignore validation errors
      })
    })

    # Handle optional crop mask defaults and state transitions
    shiny::observe({
      use_mask <- isTRUE(input$an_use_crop_mask)

      if (!use_mask) {
        # Create a dummy class if no mask is used - treat entire area as single class
        an_crop_classes(data.frame(class_value = 1L, pixel_count = NA_integer_, area_ha = NA_real_))
        an_crop_mask_rast(NULL)
        an_crop_params(Rwapor::wapor_build_crop_assignments(1L))
      } else if (is.null(an_crop_mask_rast())) {
        # Checkbox is checked but no mask uploaded yet - clear classes to force upload
        an_crop_classes(NULL)
        an_crop_params(NULL)
      }
    })

    # Handle optional season rasters defaults - clear when unchecked
    shiny::observe({
      if (!isTRUE(input$an_use_season_rasters)) {
        an_start_rast(NULL)
        an_end_rast(NULL)
      }
    })

    output$an_crop_class_ui <- shiny::renderUI({
      classes <- an_crop_classes()

      # Show different messages based on state
      if (is.null(classes)) {
        if (isTRUE(input$an_use_crop_mask)) {
          return(shiny::tagList(
            shiny::tags$div(
              class = "alert alert-info",
              shiny::icon("circle-info"),
              " Please upload a crop mask raster to define crop classes."
            )
          ))
        } else {
          # Single-crop mode: No mask, entire area as one crop
          crop_choices <- c("(Custom)" = "custom", Rwapor::wapor_list_crops())
          names(crop_choices) <- c("(Custom)", Rwapor::wapor_list_crops())
          
          return(shiny::tagList(
            shiny::tags$div(
              class = "alert alert-success",
              shiny::icon("circle-check"),
              " Single-crop mode: Select crop parameters for the entire analysis area."
            ),
            shiny::div(
              class = "card p-2 mb-2 bg-light",
              shiny::tags$div(
                style = "display: flex; justify-content: space-between; align-items: center; margin-bottom: 5px;",
                shiny::tags$strong("Default Crop (All Pixels)")
              ),
              shiny::fluidRow(
                shiny::column(
                  6,
                  shiny::selectInput(ns("an_single_crop_profile"), "Crop Profile", 
                                    choices = crop_choices, width = "100%")
                ),
                shiny::column(
                  6,
                  shiny::textInput(ns("an_single_crop_label"), "Crop Name", 
                                  value = "Default Crop", width = "100%")
                )
              ),
              shiny::tags$small(class = "text-primary d-block mb-1", "Kc & Stage Lengths"),
              shiny::fluidRow(
                shiny::column(4, shiny::numericInput(ns("an_single_kc_ini"), "Kc ini", value = 0.3, step = 0.05, width = "100%")),
                shiny::column(4, shiny::numericInput(ns("an_single_kc_mid"), "Kc mid", value = 1.15, step = 0.05, width = "100%")),
                shiny::column(4, shiny::numericInput(ns("an_single_kc_end"), "Kc end", value = 0.3, step = 0.05, width = "100%"))
              ),
              shiny::fluidRow(
                shiny::column(3, shiny::numericInput(ns("an_single_l_ini"), "Ini(d)", value = 30, min = 0, width = "100%")),
                shiny::column(3, shiny::numericInput(ns("an_single_l_mid"), "Mid(d)", value = 40, min = 0, width = "100%")),
                shiny::column(3, shiny::numericInput(ns("an_single_l_late"), "End(d)", value = 30, min = 0, width = "100%")),
                shiny::column(3, shiny::numericInput(ns("an_single_height"), "H(m)", value = 1.0, step = 0.1, width = "100%"))
              ),
              shiny::tags$small(class = "text-success d-block mb-1 mt-1", "Production Parameters"),
              shiny::fluidRow(
                shiny::column(3, shiny::numericInput(ns("an_single_hi"), "HI", value = 0.45, min = 0, max = 1, step = 0.05, width = "100%")),
                shiny::column(3, shiny::numericInput(ns("an_single_mc"), "MC", value = 0.12, min = 0, max = 1, step = 0.05, width = "100%")),
                shiny::column(3, shiny::numericInput(ns("an_single_fc"), "fc", value = 1.0, min = 0, step = 0.1, width = "100%")),
                shiny::column(3, shiny::numericInput(ns("an_single_aot"), "AOT", value = 0.8, min = 0, max = 1, step = 0.05, width = "100%"))
              )
            )
          ))
        }
      }

      if (nrow(classes) == 0) {
        return(shiny::tagList(
          shiny::tags$div(
            class = "alert alert-warning",
            shiny::icon("triangle-exclamation"),
            " No valid classes found in the crop mask. Check your raster values."
          )
        ))
      }

      crop_choices <- c("(Custom)" = "custom", Rwapor::wapor_list_crops())
      names(crop_choices) <- c("(Custom)", Rwapor::wapor_list_crops())

      shiny::tagList(lapply(seq_len(nrow(classes)), function(i) {
        cls <- classes$class_value[i]
        prefix <- paste0("an_cls_", cls, "_")
        shiny::tagList(
          shiny::div(
            class = "card p-2 mb-2 bg-light",
            shiny::tags$div(
              style = "display: flex; justify-content: space-between; align-items: center; margin-bottom: 5px;",
              shiny::tags$strong(
                if (is.na(classes$pixel_count[i])) {
                  sprintf("Class %d (Default)", cls)
                } else {
                  sprintf("Class %d (%d px, %.1f ha)", cls, classes$pixel_count[i], classes$area_ha[i])
                }
              ),
              shiny::checkboxInput(ns(paste0(prefix, "include")), NULL, value = TRUE)
            ),
            shiny::fluidRow(
              shiny::column(
                6,
                shiny::selectInput(ns(paste0(prefix, "profile")), "Profile", choices = crop_choices, width = "100%")
              ),
              shiny::column(
                6,
                shiny::textInput(ns(paste0(prefix, "label")), "Label", value = paste("Class", cls), width = "100%")
              )
            ),
            # FAO-56 Kc Parameters
            shiny::tags$small(class = "text-primary d-block mb-1", "Kc & Stage Lengths"),
            shiny::fluidRow(
              shiny::column(4, shiny::numericInput(ns(paste0(prefix, "kc_ini")), "Kc ini", value = 0.3, step = 0.05, width = "100%")),
              shiny::column(4, shiny::numericInput(ns(paste0(prefix, "kc_mid")), "Kc mid", value = 1.15, step = 0.05, width = "100%")),
              shiny::column(4, shiny::numericInput(ns(paste0(prefix, "kc_end")), "Kc end", value = 0.3, step = 0.05, width = "100%"))
            ),
            shiny::fluidRow(
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "l_ini")), "Ini(d)", value = 30, min = 0, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "l_mid")), "Mid(d)", value = 40, min = 0, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "l_late")), "End(d)", value = 30, min = 0, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "height")), "H(m)", value = 1.0, step = 0.1, width = "100%"))
            ),
            # Production Parameters (NEW)
            shiny::tags$small(class = "text-success d-block mb-1 mt-1", "Production Parameters (Yield/Biomass)"),
            shiny::fluidRow(
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "hi")), "HI", value = 0.45, min = 0, max = 1, step = 0.05, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "mc")), "MC", value = 0.12, min = 0, max = 1, step = 0.05, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "fc")), "fc", value = 1.0, min = 0, step = 0.1, width = "100%")),
              shiny::column(3, shiny::numericInput(ns(paste0(prefix, "aot")), "AOT", value = 0.8, min = 0, max = 1, step = 0.05, width = "100%"))
            )
          )
        )
      }))
    })

    # Auto-populate crop parameters when profile is selected (multi-class mode)
    shiny::observe({
      classes <- an_crop_classes()
      shiny::req(classes)

      for (i in seq_len(nrow(classes))) {
        local({
          cls <- classes$class_value[i]
          prefix <- paste0("an_cls_", cls, "_")
          profile_id <- paste0(prefix, "profile")

          shiny::observeEvent(input[[profile_id]], {
            profile_name <- input[[profile_id]]
            if (!is.null(profile_name) && profile_name != "custom") {
              defaults <- Rwapor::wapor_crop_defaults(profile_name)
              if (!is.null(defaults)) {
                shiny::updateTextInput(session, paste0(prefix, "label"), value = defaults$crop_name)
                shiny::updateNumericInput(session, paste0(prefix, "kc_ini"), value = defaults$kc_ini)
                shiny::updateNumericInput(session, paste0(prefix, "kc_mid"), value = defaults$kc_mid)
                shiny::updateNumericInput(session, paste0(prefix, "kc_end"), value = defaults$kc_end)
                shiny::updateNumericInput(session, paste0(prefix, "l_ini"), value = defaults$l_ini_days)
                shiny::updateNumericInput(session, paste0(prefix, "l_mid"), value = defaults$l_mid_days)
                shiny::updateNumericInput(session, paste0(prefix, "l_late"), value = defaults$l_late_days)
                shiny::updateNumericInput(session, paste0(prefix, "height"), value = defaults$max_height_m)
                shiny::updateNumericInput(session, paste0(prefix, "hi"), value = defaults$HI)
                shiny::updateNumericInput(session, paste0(prefix, "mc"), value = defaults$MC)
                shiny::updateNumericInput(session, paste0(prefix, "fc"), value = defaults$fc)
                shiny::updateNumericInput(session, paste0(prefix, "aot"), value = defaults$AOT)
              }
            }
          }, ignoreInit = TRUE)
        })
      }
    })
    
    # Auto-populate crop parameters when profile is selected (single-crop mode)
    shiny::observeEvent(input$an_single_crop_profile, {
      profile_name <- input$an_single_crop_profile
      if (!is.null(profile_name) && profile_name != "custom") {
        defaults <- Rwapor::wapor_crop_defaults(profile_name)
        if (!is.null(defaults)) {
          shiny::updateTextInput(session, "an_single_crop_label", value = defaults$crop_name)
          shiny::updateNumericInput(session, "an_single_kc_ini", value = defaults$kc_ini)
          shiny::updateNumericInput(session, "an_single_kc_mid", value = defaults$kc_mid)
          shiny::updateNumericInput(session, "an_single_kc_end", value = defaults$kc_end)
          shiny::updateNumericInput(session, "an_single_l_ini", value = defaults$l_ini_days)
          shiny::updateNumericInput(session, "an_single_l_mid", value = defaults$l_mid_days)
          shiny::updateNumericInput(session, "an_single_l_late", value = defaults$l_late_days)
          shiny::updateNumericInput(session, "an_single_height", value = defaults$max_height_m)
          shiny::updateNumericInput(session, "an_single_hi", value = defaults$HI)
          shiny::updateNumericInput(session, "an_single_mc", value = defaults$MC)
          shiny::updateNumericInput(session, "an_single_fc", value = defaults$fc)
          shiny::updateNumericInput(session, "an_single_aot", value = defaults$AOT)
        }
      }
    }, ignoreInit = TRUE)

    collect_crop_params <- function() {
      classes <- an_crop_classes()
      
      # Single-crop mode (no mask uploaded)
      if (is.null(classes)) {
        if (!isTRUE(input$an_use_crop_mask)) {
          # Use single-crop parameters
          return(data.frame(
            class_value = 1L,
            crop_label = null_default(input$an_single_crop_label, "Default Crop"),
            kc_ini = null_default(input$an_single_kc_ini, 0.3),
            kc_mid = null_default(input$an_single_kc_mid, 1.15),
            kc_end = null_default(input$an_single_kc_end, 0.3),
            l_ini_days = as.integer(null_default(input$an_single_l_ini, 30)),
            l_mid_days = as.integer(null_default(input$an_single_l_mid, 40)),
            l_late_days = as.integer(null_default(input$an_single_l_late, 30)),
            max_height_m = null_default(input$an_single_height, 1.0),
            HI = null_default(input$an_single_hi, 0.45),
            MC = null_default(input$an_single_mc, 0.12),
            fc = null_default(input$an_single_fc, 1.0),
            AOT = null_default(input$an_single_aot, 0.8),
            stringsAsFactors = FALSE
          ))
        }
        return(NULL)
      }

      # Multi-class mode (mask uploaded)
      rows <- lapply(seq_len(nrow(classes)), function(i) {
        cls <- classes$class_value[i]
        prefix <- paste0("an_cls_", cls, "_")
        
        # Check if user included this class
        if (!isTRUE(input[[paste0(prefix, "include")]])) return(NULL)
        
          data.frame(
            class_value = cls,
            crop_label = null_default(input[[paste0(prefix, "label")]], paste("Class", cls)),
            kc_ini = null_default(input[[paste0(prefix, "kc_ini")]], 0.3),
            kc_mid = null_default(input[[paste0(prefix, "kc_mid")]], 1.15),
            kc_end = null_default(input[[paste0(prefix, "kc_end")]], 0.3),
            l_ini_days = as.integer(null_default(input[[paste0(prefix, "l_ini")]], 30)),
            l_mid_days = as.integer(null_default(input[[paste0(prefix, "l_mid")]], 40)),
            l_late_days = as.integer(null_default(input[[paste0(prefix, "l_late")]], 30)),
            max_height_m = null_default(input[[paste0(prefix, "height")]], 1.0),
            HI = null_default(input[[paste0(prefix, "hi")]], 0.45),
            MC = null_default(input[[paste0(prefix, "mc")]], 0.12),
            fc = null_default(input[[paste0(prefix, "fc")]], 1.0),
            AOT = null_default(input[[paste0(prefix, "aot")]], 0.8),
            stringsAsFactors = FALSE
          )
      })

      do.call(rbind, rows)
    }

    active_kc_data <- shiny::reactive({
      params <- collect_crop_params()
      shiny::req(params)
      # Dynamic total days for preview to ensure L_dev is at least 30
      fixed_sums <- params$l_ini_days + params$l_mid_days + params$l_late_days
      total_days_vec <- stats::setNames(fixed_sums + 30, as.character(params$class_value))
      tryCatch(Rwapor::wapor_build_kc_by_class(params, total_days_vec), error = function(e) NULL)
    })

    output$an_season_summary <- shiny::renderPrint({
      cat("Season:", input$an_season_label, "\n")
      cat("Reference Year:", input$an_ref_year, "\n")
      cat("Analysis Period:", as.character(input$an_period[1]), "to", as.character(input$an_period[2]), "\n")

      # Data source mode
      data_source <- input$an_data_source
      if (data_source == "local") {
        cat("Data Source: LOCAL FILES (offline mode)\n")
      } else {
        cat("Data Source: API STREAMING (online mode)\n")
      }

      cat("\n--- Variables ---\n")
      cat("AETI:", input$an_aeti_var, "\n")
      cat("RET:", input$an_ret_var, "\n")
      cat("Precip:", input$an_precip_var, "\n")
      cat("Configured Project Folder:", project_folder() %||% "Not set", "\n")
      cat("Analysis Output Folder:", analysis_output_folder() %||% "Not set", "\n")

      cat("\n--- Raster Status ---\n")
      cat("Crop Mask:", if (!is.null(an_crop_mask_rast())) "Loaded" else "Not loaded", "\n")
      cat("Season Start:", if (!is.null(an_start_rast())) "Loaded" else "Not loaded", "\n")
      cat("Season End:", if (!is.null(an_end_rast())) "Loaded" else "Not loaded", "\n")

      # Show local data availability if in local mode
      if (data_source == "local") {
        local_vars <- an_local_vars()
        if (!is.null(local_vars) && nrow(local_vars) > 0) {
          cat("\n--- Local Data Available ---\n")
          for (i in seq_len(nrow(local_vars))) {
            v <- local_vars[i, ]
            status <- if (v$variable %in% c(input$an_aeti_var, input$an_ret_var, input$an_precip_var)) "[SELECTED]" else ""
            cat(sprintf("%s: %d files %s\n", v$variable, v$file_count, status))
          }
        } else {
          cat("\n[!] Click 'Re-scan Folder' to detect available data.\n")
        }
      }
    })

    output$an_crop_mask_plot <- shiny::renderPlot({
      r <- an_crop_mask_rast()
      shiny::req(r)
      old_mar <- graphics::par("mar")
      on.exit(graphics::par(mar = old_mar), add = TRUE)
      graphics::par(mar = c(1, 1, 2, 1))
      terra::plot(
        r,
        main = "Crop Mask Classes",
        col = grDevices::hcl.colors(20, "Set2"),
        axes = FALSE,
        legend = FALSE
      )
    })

    output$an_season_raster_info <- shiny::renderPrint({
      use_season <- isTRUE(input$an_use_season_rasters)
      s_start <- an_start_rast()
      s_end <- an_end_rast()

      if (!use_season) {
        cat("Season rasters disabled.\n")
        cat("Analysis will use the date range from the Analysis Period input.\n")
        return()
      }

      if (is.null(s_start) && is.null(s_end)) {
        cat("Waiting for season rasters to be uploaded...\n")
        cat("\nExpected format:\n")
        cat("  - Single-band GeoTIFF with Julian Day of Year (DOY) values\n")
        cat("  - Values should be 1-366 (or up to 730 for cross-year seasons)\n")
        return()
      }

      cat("=== Season Rasters Status ===\n\n")

      if (!is.null(s_start)) {
        cat("[OK] Season Start Raster:\n")
        vals <- terra::values(s_start, na.rm = TRUE)
        cat(sprintf("     Dimensions: %d x %d\n", nrow(s_start), ncol(s_start)))
        cat(sprintf("     DOY range: %d - %d\n", as.integer(min(vals)), as.integer(max(vals))))
        cat(sprintf("     Valid pixels: %d\n", length(vals)))
      } else {
        cat("[MISSING] Season Start Raster: Not uploaded\n")
      }

      cat("\n")

      if (!is.null(s_end)) {
        cat("[OK] Season End Raster:\n")
        vals <- terra::values(s_end, na.rm = TRUE)
        cat(sprintf("     Dimensions: %d x %d\n", nrow(s_end), ncol(s_end)))
        cat(sprintf("     DOY range: %d - %d\n", as.integer(min(vals)), as.integer(max(vals))))
        cat(sprintf("     Valid pixels: %d\n", length(vals)))
      } else {
        cat("[MISSING] Season End Raster: Not uploaded\n")
      }

      # Additional validation feedback
      if (!is.null(s_start) && !is.null(s_end)) {
        cat("\n=== Validation ===\n")
        vals_start <- terra::values(s_start, na.rm = TRUE)
        vals_end <- terra::values(s_end, na.rm = TRUE)
        mean_start <- mean(vals_start)
        mean_end <- mean(vals_end)
        mean_duration <- mean_end - mean_start + 1

        if (mean_start > mean_end && mean_end < 366) {
          cat("Cross-year season detected.\n")
          mean_duration <- (366 - mean_start) + mean_end + 1
        }
        cat(sprintf("Mean season duration: ~%.0f days\n", mean_duration))
      }
    })

    output$an_crop_class_table <- shiny::renderTable({
      classes <- an_crop_classes()
      shiny::req(classes)
      classes
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    shiny::observeEvent(input$an_validate_btn, {
      validation <- tryCatch({
        state <- build_analysis_state()
        run_analysis_validation(state)
      }, error = function(e) {
        list(overall = "failed", errors = e$message, warnings = character(), 
             recommendations = character())
      })
      
      # Display validation results
      if (validation$overall == "failed") {
        shiny::showNotification(
          shiny::HTML(paste(
            "<b>Validation Failed:</b><br>",
            paste("-", validation$errors, collapse = "<br>")
          )),
          type = "error",
          duration = 15
        )
      } else if (validation$overall == "warning") {
        msg_parts <- list("<b>⚠️ Validation Warnings (Analysis can still proceed):</b>")
        if (length(validation$warnings) > 0) {
          msg_parts <- c(msg_parts,
                        paste("•", validation$warnings, collapse = "<br>"))
        }
        if (length(validation$recommendations) > 0) {
          msg_parts <- c(msg_parts, "<br><b>💡 Recommendations:</b>",
                        paste("•", validation$recommendations, collapse = "<br>"))
        }
        shiny::showNotification(
          shiny::HTML(paste(msg_parts, collapse = "<br>")),
          type = "warning",
          duration = 15
        )
        shiny::showNotification("✓ Configuration is valid with warnings. You can proceed or address the warnings first.", 
                               type = "message", duration = 5)
        # Generate script preview on validation success
        set_script_preview(generate_rwapor_script())
      } else {
        shiny::showNotification("✓ All validation checks passed! Ready to run analysis.", 
                               type = "message", duration = 5)
        # Generate script preview on validation success
        set_script_preview(generate_rwapor_script())
      }
    })

    shiny::observeEvent(input$an_reset_btn, {
      an_crop_mask_rast(NULL)
      an_start_rast(NULL)
      an_end_rast(NULL)
      an_crop_classes(NULL)
      an_crop_params(NULL)
      an_results(NULL)
      an_peff_monthly(NULL)
      an_local_vars(NULL)
      .h_cache(NULL)

      # Remove terra temp files accumulated during analysis to free disk space
      tryCatch(terra::tmpFiles(remove = TRUE), error = function(e) NULL)

      set_script_preview("# Validate inputs to generate a reusable R script.\n")
      shiny::showNotification("Analysis state reset and temp files cleared.", type = "message")
    })

    shiny::observeEvent(input$an_run_btn, {
      # Prevent double-submission
      if (isTRUE(.an_running())) {
        shiny::showNotification("Analysis is already running. Please wait.", type = "warning")
        return()
      }

      # 1. Immediate validation and input resolution
      if (isTRUE(input$an_use_crop_mask) && is.null(an_crop_mask_rast())) {
        shiny::showNotification("Please upload a crop mask raster or uncheck the 'Use a crop mask raster?' option.", type = "error")
        return()
      }
      if (isTRUE(input$an_use_season_rasters) && (is.null(an_start_rast()) || is.null(an_end_rast()))) {
        shiny::showNotification("Please upload season start and end rasters or uncheck the 'Use pixel-wise season start/end rasters?' option.", type = "error")
        return()
      }

      # Validate raster references haven't gone stale
      if (isTRUE(input$an_use_crop_mask))
        if (is.null(Rwapor:::wapor_shiny_safe_rast(an_crop_mask_rast, "Crop mask"))) return()
      if (isTRUE(input$an_use_season_rasters)) {
        if (is.null(Rwapor:::wapor_shiny_safe_rast(an_start_rast, "Season start raster"))) return()
        if (is.null(Rwapor:::wapor_shiny_safe_rast(an_end_rast,   "Season end raster")))   return()
      }

      state <- tryCatch(build_analysis_state(), error = function(e) e)
      if (inherits(state, "error")) {
        shiny::showNotification(state$message, type = "error", duration = 10)
        return()
      }

      if (isTRUE(state$config$data_source == "local")) {
        if (is.null(state$folder) || !nzchar(state$folder) || !dir.exists(state$folder)) {
          shiny::showNotification("Local data mode selected but project folder is not set. Use the Download tab folder or choose one in Analysis.", type = "error")
          return()
        }

        local_vars <- an_local_vars()
        if (is.null(local_vars) || nrow(local_vars) == 0) {
          shiny::showNotification("Please click 'Re-scan Folder' first to detect available variables.", type = "error")
          return()
        }

        missing_info <- tryCatch(collect_missing_local_data(state), error = function(e) e)
        if (inherits(missing_info, "error")) {
          shiny::showNotification(missing_info$message, type = "error", duration = 10)
          return()
        }

        if (length(missing_info) > 0) {
          show_missing_local_data_modal(missing_info, state$folder, local_vars)
          return()
        }
      }

      an_peff_monthly(NULL)
      .an_running(TRUE)
      shinyjs::disable("an_run_btn")

      shiny::withProgress(message = "Running analysis...", value = 0, {
        tryCatch({
          rasters <- list(
            crop_mask    = an_crop_mask_rast(),
            season_start = an_start_rast(),
            season_end   = an_end_rast()
          )

          results <- Rwapor::wapor_run_seasonal_analysis(
            config            = state$config,
            crop_params       = state$crop_params,
            rasters           = rasters,
            aoi_region        = state$region,
            progress_callback = shiny::incProgress
          )

          an_results(results)
          an_crop_params(state$crop_params)

          if (isTRUE(input$an_save_rasters) && nzchar(state$output_folder %||% "")) {
            season_label <- if (state$batch_mode) NULL else state$config$season_label
            wapor_shiny_save_analysis_rasters(
              results,
              state$output_folder,
              season_label,
              state$indicators,
              include_monthly = isTRUE(input$an_include_monthly_exports)
            )
          }

          shiny::showNotification("Analysis complete!", type = "message", duration = 8)
          set_script_preview(generate_rwapor_script())

        }, error = function(e) {
          shiny::showNotification(paste("Analysis failed:", e$message), type = "error", duration = 15)
        }, finally = {
          .an_running(FALSE)
          shinyjs::enable("an_run_btn")
        })
      })
    })

    output$an_kc_plot <- shiny::renderPlot({
      kc_list <- active_kc_data()
      params <- collect_crop_params()
      shiny::req(kc_list, params)

      if (length(kc_list) == 0) return()
      max_len <- max(vapply(kc_list, length, integer(1)))
      if (max_len == 0) return()

      old_mar <- graphics::par("mar")
      old_mgp <- graphics::par("mgp")
      on.exit(graphics::par(mar = old_mar, mgp = old_mgp), add = TRUE)
      graphics::par(mar = c(3.2, 3.2, 2.2, 1), mgp = c(2, 0.7, 0))

      cols <- grDevices::hcl.colors(length(kc_list), "Set2")
      graphics::plot(
        NULL,
        xlim = c(1, max_len),
        ylim = c(0, 1.5),
        xlab = "Day of Season",
        ylab = "Kc",
        main = "Crop Coefficient Curves (Preview)",
        axes = FALSE
      )
      graphics::axis(1)
      graphics::axis(2)
      graphics::box()
      
      for (i in seq_along(kc_list)) {
        kc <- kc_list[[i]]
        if (length(kc) > 0) {
          graphics::lines(seq_along(kc), kc, col = cols[i], lwd = 3)
        }
      }
      graphics::legend(
        "topright",
        legend = params$crop_label,
        col = cols,
        lwd = 3,
        cex = 0.8,
        bty = "n",
        inset = 0.02
      )
    })

    output$an_etc_aeti_table <- shiny::renderTable({
      res <- an_results()
      shiny::req(res)

      rows <- list()
      if (!is.null(res$seasonal_aeti$by_class)) {
        aeti_tbl <- res$seasonal_aeti$by_class
        ret_tbl <- if (!is.null(res$seasonal_ret)) res$seasonal_ret$by_class else NULL
        etc_means <- if (!is.null(res$etc_by_class)) {
          vapply(names(res$etc_by_class), function(cls) {
            etc_r <- res$etc_by_class[[cls]]$etc_seasonal
            if (!is.null(etc_r)) Rwapor:::wapor_masked_global_mean(etc_r) else NA_real_
          }, numeric(1))
        } else {
          numeric()
        }


        for (i in seq_len(nrow(aeti_tbl))) {
          cls_str <- as.character(aeti_tbl$class_value[i])
          label <- if (!is.null(res$crop_params)) {
            idx <- which(res$crop_params$class_value == aeti_tbl$class_value[i])
            if (length(idx) > 0) res$crop_params$crop_label[idx[1]] else cls_str
          } else {
            cls_str
          }

          # Get Yield if available
          yield_val <- if (!is.null(res$yield_by_class) && cls_str %in% names(res$yield_by_class)) {
            terra::global(res$yield_by_class[[cls_str]], "mean", na.rm = TRUE)$mean
          } else NA_real_

          rows[[i]] <- data.frame(
            Class = label,
            `AETI (mm)` = round(aeti_tbl$mean_seasonal_aeti[i], 1),
            `RET (mm)` = if (!is.null(ret_tbl)) {
              ret_idx <- match(aeti_tbl$class_value[i], ret_tbl$class_value)
              if (!is.na(ret_idx)) round(ret_tbl$mean_seasonal_ret[ret_idx], 1) else NA
            } else {
              NA
            },
            `ETc (mm)` = if (cls_str %in% names(etc_means)) round(etc_means[cls_str], 1) else NA,
            `Yield (t/ha)` = if (!is.na(yield_val)) round(yield_val, 2) else NA,
            `Beneficial Frac.` = if (!is.null(res$beneficial_fraction)) {
              cls_mask <- if (!is.null(res$h_mask)) terra::ifel(res$h_mask == as.integer(cls_str), 1L, NA) else NULL
              round(Rwapor:::wapor_masked_global_mean(res$beneficial_fraction, cls_mask), 3)
            } else NA,
            check.names = FALSE,
            stringsAsFactors = FALSE
          )
        }
      }

      if (length(rows) > 0) do.call(rbind, rows) else {
        data.frame(Message = "Run analysis first.", stringsAsFactors = FALSE)
      }
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    output$an_adequacy_table <- shiny::renderTable({
      res <- an_results()
      shiny::req(res)

      rows <- list()
      params <- res$crop_params
      mask_rast <- res$h_mask %||% an_crop_mask_rast()

      if (!is.null(res$adequacy_etc)) {
        classes <- params$class_value %||% integer(0)
        for (cls in classes) {
          cls_mask <- if (!is.null(mask_rast)) terra::ifel(mask_rast == cls, 1L, NA) else NULL
          mean_adq <- Rwapor:::wapor_masked_global_mean(res$adequacy_etc, cls_mask)

          label <- if (!is.null(params)) {
            idx <- which(params$class_value == cls)
            if (length(idx) > 0) params$crop_label[idx[1]] else as.character(cls)
          } else {
            as.character(cls)
          }
          rows[[length(rows) + 1]] <- data.frame(
            Class = label,
            Indicator = "Adequacy_ETc",
            Mean = if (!is.nan(mean_adq)) round(mean_adq, 3) else NA,
            check.names = FALSE,
            stringsAsFactors = FALSE
          )

        }
      }

      if (!is.null(res$adequacy_p95)) {
        p95_tbl <- res$p95_table
        for (i in seq_len(nrow(p95_tbl))) {
          cls <- p95_tbl$class_value[i]
          cls_mask <- if (!is.null(mask_rast)) terra::ifel(mask_rast == cls, 1L, NA) else NULL
          mean_adq <- Rwapor:::wapor_masked_global_mean(res$adequacy_p95, cls_mask)
          label <- if (!is.null(params)) {
            idx <- which(params$class_value == cls)
            if (length(idx) > 0) params$crop_label[idx[1]] else as.character(cls)
          } else {
            as.character(cls)
          }
          rows[[length(rows) + 1]] <- data.frame(
            Class = label,
            Indicator = "Adequacy_P95",
            Mean = if (p95_tbl$valid[i]) round(mean_adq, 3) else NA,
            check.names = FALSE,
            stringsAsFactors = FALSE
          )
        }
      }

      if (length(rows) > 0) do.call(rbind, rows) else {
        data.frame(Message = "Run analysis with adequacy indicators selected.", stringsAsFactors = FALSE)
      }
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    output$an_peff_table <- shiny::renderTable({
      peff_m <- an_peff_monthly()
      if (!is.null(peff_m)) {
        peff_m$month_name <- month.abb[peff_m$month]
        out <- peff_m[, c("year", "month_name", "p_monthly_mm", "peff_mm")]
        names(out) <- c("Year", "Month", "Precip (mm)", "Peff (mm)")
        total_row <- data.frame(
          Year = "",
          Month = "TOTAL",
          `Precip (mm)` = round(sum(peff_m$p_monthly_mm, na.rm = TRUE), 1),
          `Peff (mm)` = round(sum(peff_m$peff_mm, na.rm = TRUE), 1),
          check.names = FALSE,
          stringsAsFactors = FALSE
        )
        rbind(out, total_row)
      } else {
        data.frame(Message = "Run analysis with Peff indicator selected.", stringsAsFactors = FALSE)
      }
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    output$an_cwp_bwp_table <- shiny::renderTable({
      res <- an_results()
      shiny::req(res)

      rows <- list()
      if (!is.null(res$cwp)) {
        rows[[length(rows) + 1]] <- data.frame(
          Metric = "CWP",
          Value = round(res$cwp, 3),
          Unit = "kg/m3",
          stringsAsFactors = FALSE
        )
      }
      if (!is.null(res$bwp)) {
        rows[[length(rows) + 1]] <- data.frame(
          Metric = "BWP",
          Value = round(res$bwp, 3),
          Unit = "kg/m3",
          stringsAsFactors = FALSE
        )
      }

      if (length(rows) > 0) do.call(rbind, rows) else {
        data.frame(Message = "Upload yield/biomass rasters and run analysis.", stringsAsFactors = FALSE)
      }
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    output$an_green_blue_table <- shiny::renderTable({
      res <- an_results()
      shiny::req(res)

      rows <- list()
      mask_rast <- res$h_mask %||% an_crop_mask_rast()
      params <- res$crop_params

      if (!is.null(res$green_water)) {
        classes <- if (!is.null(params)) params$class_value else integer(0)
        for (cls in classes) {
          cls_mask <- if (!is.null(mask_rast)) terra::ifel(mask_rast == cls, 1L, NA) else NULL
          mean_gw <- Rwapor:::wapor_masked_global_mean(res$green_water, cls_mask)
          label <- if (!is.null(params)) {
            idx <- which(params$class_value == cls)
            if (length(idx) > 0) params$crop_label[idx[1]] else as.character(cls)
          } else {
            as.character(cls)
          }
          rows[[length(rows) + 1]] <- data.frame(
            Class = label,
            Indicator = "Green Water (mm)",
            Mean = if (!is.nan(mean_gw)) round(mean_gw, 1) else NA,
            check.names = FALSE,
            stringsAsFactors = FALSE
          )
        }
      }

      if (!is.null(res$blue_water)) {
        classes <- if (!is.null(params)) params$class_value else integer(0)
        for (cls in classes) {
          cls_mask <- if (!is.null(mask_rast)) terra::ifel(mask_rast == cls, 1L, NA) else NULL
          mean_bw <- Rwapor:::wapor_masked_global_mean(res$blue_water, cls_mask)
          label <- if (!is.null(params)) {
            idx <- which(params$class_value == cls)
            if (length(idx) > 0) params$crop_label[idx[1]] else as.character(cls)
          } else {
            as.character(cls)
          }
          rows[[length(rows) + 1]] <- data.frame(
            Class = label,
            Indicator = "Blue Water (mm)",
            Mean = if (!is.nan(mean_bw)) round(mean_bw, 1) else NA,
            check.names = FALSE,
            stringsAsFactors = FALSE
          )
        }
      }

      if (length(rows) > 0) do.call(rbind, rows) else {
        data.frame(Message = "Run analysis with Green/Blue Water indicators and a precipitation variable selected.", stringsAsFactors = FALSE)
      }
    }, striped = TRUE, hover = TRUE, bordered = TRUE)

    output$an_dl_crop_params <- shiny::downloadHandler(
      filename = function() paste0("crop_parameters_", Sys.Date(), ".csv"),
      content = function(file) {
        params <- an_crop_params()
        if (!is.null(params)) utils::write.csv(params, file, row.names = FALSE)
      }
    )

    output$an_dl_results <- shiny::downloadHandler(
      filename = function() paste0("seasonal_results_", Sys.Date(), ".csv"),
      content = function(file) {
        res <- an_results()
        if (!is.null(res) && !is.null(res$seasonal_aeti$by_class)) {
          out <- res$seasonal_aeti$by_class
          if (!is.null(res$seasonal_ret$by_class)) {
            out <- merge(out, res$seasonal_ret$by_class, by = "class_value", all = TRUE)
          }
          out$season <- input$an_season_label
          out$ref_year <- input$an_ref_year
          utils::write.csv(out, file, row.names = FALSE)
        }
      }
    )

    output$an_dl_peff <- shiny::downloadHandler(
      filename = function() paste0("monthly_peff_", Sys.Date(), ".csv"),
      content = function(file) {
        peff_m <- an_peff_monthly()
        if (!is.null(peff_m)) {
          peff_m$method <- "USDA_SCS"
          utils::write.csv(peff_m, file, row.names = FALSE)
        }
      }
    )

    output$an_dl_script <- shiny::downloadHandler(
      filename = function() {
        paste0("rwapor_analysis_", Sys.Date(), ".R")
      },
      content = function(file) {
        script_text <- an_script_text()
        if (!nzchar(trimws(script_text %||% ""))) {
          script_text <- generate_rwapor_script()
        }
        writeLines(script_text, con = file, useBytes = TRUE)
      }
    )

    shiny::onFlushed(function() {
      set_script_preview(shiny::isolate(an_script_text()))
    }, once = TRUE)

    list(
      mask_rast = an_crop_mask_rast,
      start_rast = an_start_rast,
      end_rast = an_end_rast,
      crop_params = an_crop_params
    )
  })
}
