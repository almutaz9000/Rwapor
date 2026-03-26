# Timeseries Module for Rwapor Dashboard
# Plots time series of raster data and vector-based zonal statistics

#' Timeseries Module UI
#'
#' @param id Module namespace ID
#' @export
mod_timeseries_ui <- function(id) {
  ns <- NS(id)
  
  bslib::page_fillable(
    bslib::layout_sidebar(
      sidebar = bslib::sidebar(
        width = 350,
        
        ## --- Data Source Section ---
        bslib::card(
          bslib::card_header("Data Source"),
          bslib::card_body(
            shiny::selectInput(
              ns("ts_source"),
              "Source Type",
              choices = c("Raster Files" = "raster", "Vector File" = "vector"),
              selected = "raster"
            ),
            
            # Vector file upload (shown when source = vector)
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] == 'vector'", ns("ts_source")),
              ns = ns,
              shiny::fileInput(
                ns("ts_vector_file"),
                "Upload Vector File",
                accept = c(".shp", ".geojson", ".gpkg", ".kml", ".json")
              ),
              shiny::uiOutput(ns("ts_vector_id_ui"))
            ),
            
            # Raster folder browser
            shiny::conditionalPanel(
              condition = sprintf("input['%s'] == 'raster'", ns("ts_source")),
              ns = ns,
              shiny::helpText("Using folder from Download tab:", style = "font-size: 90%; color: #666;"),
              shiny::verbatimTextOutput(ns("ts_folder_display"), placeholder = TRUE)
            )
          )
        ),
        
        ## --- Variable Selection Section ---
        bslib::card(
          bslib::card_header("Variables"),
          bslib::card_body(
            shiny::selectInput(
              ns("ts_variables"),
              "Select Variable(s)",
              choices = NULL,
              multiple = TRUE
            ),
            shiny::helpText("Select one or more variables to plot", style = "font-size: 90%;")
          )
        ),
        
        ## --- Time Range Section ---
        bslib::card(
          bslib::card_header("Time Range"),
          bslib::card_body(
            shiny::dateRangeInput(
              ns("ts_date_range"),
              "Date Range",
              start = Sys.Date() - 365,
              end = Sys.Date(),
              format = "yyyy-mm-dd"
            ),
            shiny::checkboxInput(
              ns("ts_auto_range"),
              "Auto-detect from data",
              value = TRUE
            )
          )
        ),
        
        ## --- Plot Options Section ---
        bslib::card(
          bslib::card_header("Plot Options"),
          bslib::card_body(
            shiny::selectInput(
              ns("ts_plot_type"),
              "Plot Type",
              choices = c(
                "Line Chart" = "line",
                "Point Chart" = "point",
                "Line + Points" = "both",
                "Seasonal Regression" = "seasonal",
                "Smoothed Trend" = "smooth"
              ),
              selected = "line"
            ),
            shiny::checkboxInput(
              ns("ts_facet_vars"),
              "Separate panel per variable",
              value = TRUE
            ),
            shiny::checkboxInput(
              ns("ts_show_mean"),
              "Show mean line (for vectors)",
              value = FALSE
            )
          )
        ),
        
        ## --- Action Buttons ---
        bslib::card(
          bslib::card_body(
            shiny::actionButton(
              ns("ts_plot_btn"),
              "Generate Plot",
              icon = icon("chart-line"),
              class = "btn-primary w-100 mb-2"
            ),
            shiny::actionButton(
              ns("ts_reset_btn"),
              "Reset",
              icon = icon("redo"),
              class = "btn-secondary w-100"
            )
          )
        )
      ),
      
      ## --- Main Panel: Results ---
      bslib::navset_card_tab(
        id = ns("ts_results_tabs"),
        
        # Plot Tab
        bslib::nav_panel(
          "Plot",
          icon = icon("chart-line"),
          bslib::card_body(
            shiny::plotOutput(ns("ts_plot"), height = "600px") %>%
              shinycssloaders::withSpinner(type = 6, color = "#2c3e50")
          )
        ),
        
        # Data Table Tab
        bslib::nav_panel(
          "Data Table",
          icon = icon("table"),
          bslib::card_body(
            shiny::downloadButton(ns("ts_export_csv"), "Export CSV", class = "btn-sm mb-2"),
            shiny::downloadButton(ns("ts_export_parquet"), "Export Parquet", class = "btn-sm mb-2"),
            shiny::downloadButton(ns("ts_export_rds"), "Export RDS", class = "btn-sm mb-2"),
            DT::DTOutput(ns("ts_data_table"))
          )
        ),
        
        # Summary Tab
        bslib::nav_panel(
          "Summary",
          icon = icon("info-circle"),
          bslib::card_body(
            shiny::verbatimTextOutput(ns("ts_summary"))
          )
        )
      )
    )
  )
}


#' Timeseries Module Server
#'
#' @param id Module namespace ID
#' @param global_folder Reactive returning the current working folder path
#' @param aoi_region Reactive returning the AOI region (from Download module)
#' @export
mod_timeseries_server <- function(id, global_folder, aoi_region) {
  moduleServer(id, function(input, output, session) {
    
    ## --- Reactive Values ---
    rv <- reactiveValues(
      ts_data = NULL,
      vector_sf = NULL,
      available_vars = character(0)
    )
    
    ## --- Display Current Folder ---
    output$ts_folder_display <- renderText({
      folder <- global_folder()
      if (is.null(folder) || folder == "") {
        "No folder selected"
      } else {
        folder
      }
    })
    
    ## --- Scan Available Variables from Folder ---
    observe({
      folder <- global_folder()
      if (!is.null(folder) && folder != "" && dir.exists(folder)) {
        tryCatch({
          # Scan for variable codes from file names
          tif_files <- list.files(folder, pattern = "\\.tif$", full.names = FALSE, recursive = FALSE)
          
          # Extract variable codes (pattern: L1-AETI-D, L2-AETI-D, etc.)
          var_pattern <- "^(L[1-3]-[A-Z0-9]+-[DEMS])_"
          vars <- unique(sub(var_pattern, "\\1", tif_files[grepl(var_pattern, tif_files)]))
          
          if (length(vars) > 0) {
            rv$available_vars <- sort(vars)
            updateSelectInput(session, "ts_variables", choices = rv$available_vars)
          }
        }, error = function(e) {
          showNotification(paste("Error scanning folder:", e$message), type = "error")
        })
      }
    })
    
    ## --- Load Vector File ---
    observe({
      req(input$ts_vector_file)
      
      tryCatch({
        file_path <- input$ts_vector_file$datapath
        rv$vector_sf <- sf::st_read(file_path, quiet = TRUE)
        
        showNotification(
          paste("Vector file loaded:", nrow(rv$vector_sf), "features"),
          type = "message"
        )
      }, error = function(e) {
        showNotification(paste("Error loading vector file:", e$message), type = "error")
        rv$vector_sf <- NULL
      })
    })
    
    ## --- Vector ID Column Selector ---
    output$ts_vector_id_ui <- renderUI({
      req(rv$vector_sf)
      
      cols <- names(rv$vector_sf)
      cols <- cols[cols != "geometry" & cols != "geom"]
      
      ns <- session$ns
      shiny::selectInput(
        ns("ts_vector_id_col"),
        "Identifier Column",
        choices = cols,
        selected = cols[1]
      )
    })
    
    ## --- Extract Time Series Data ---
    extract_timeseries <- reactive({
      req(input$ts_plot_btn)
      
      isolate({
        folder <- global_folder()
        vars <- input$ts_variables
        source_type <- input$ts_source
        
        # Validation
        if (is.null(folder) || folder == "" || !dir.exists(folder)) {
          showNotification("No valid data folder selected", type = "error")
          return(NULL)
        }
        
        if (length(vars) == 0) {
          showNotification("Please select at least one variable", type = "error")
          return(NULL)
        }
        
        if (source_type == "vector") {
          req(rv$vector_sf, input$ts_vector_id_col)
          
          # Vector-based extraction using wapor_ts
          withProgress(message = "Extracting time series...", value = 0, {
            
            ts_list <- lapply(seq_along(vars), function(i) {
              setProgress(value = i / length(vars), detail = vars[i])
              
              tryCatch({
                # Get date range
                date_start <- if (input$ts_auto_range) NULL else as.character(input$ts_date_range[1])
                date_end <- if (input$ts_auto_range) NULL else as.character(input$ts_date_range[2])
                
                # Call wapor_ts for extraction
                ts_df <- Rwapor::wapor_ts(
                  variable = vars[i],
                  region = rv$vector_sf,
                  date_start = date_start,
                  date_end = date_end,
                  folder = folder,
                  fun = "mean",  # Can be made configurable
                  id_col = input$ts_vector_id_col
                )
                
                if (!is.null(ts_df) && nrow(ts_df) > 0) {
                  ts_df$variable <- vars[i]
                  return(ts_df)
                }
                return(NULL)
              }, error = function(e) {
                showNotification(paste("Error extracting", vars[i], ":", e$message), type = "warning")
                return(NULL)
              })
            })
            
            # Combine all variables
            ts_combined <- do.call(rbind, Filter(Negate(is.null), ts_list))
            
            if (is.null(ts_combined) || nrow(ts_combined) == 0) {
              showNotification("No data extracted", type = "error")
              return(NULL)
            }
            
            return(ts_combined)
          })
          
        } else {
          # Raster-based extraction (pixel time series)
          # For simplicity, we'll extract from center pixel or mean of all pixels
          withProgress(message = "Reading raster time series...", value = 0, {
            
            ts_list <- lapply(seq_along(vars), function(i) {
              setProgress(value = i / length(vars), detail = vars[i])
              
              tryCatch({
                # Find all files for this variable
                var_pattern <- paste0("^", gsub("-", "[_-]", vars[i]), "[_-]")
                tif_files <- list.files(
                  folder,
                  pattern = paste0(var_pattern, ".*\\.tif$"),
                  full.names = TRUE
                )
                
                if (length(tif_files) == 0) {
                  return(NULL)
                }
                
                # Extract dates from filenames (pattern: YYYYMMDD or YYYY-MM-DD)
                dates <- sub(".*([0-9]{4}[-_]?[0-9]{2}[-_]?[0-9]{2}).*", "\\1", basename(tif_files))
                dates <- as.Date(gsub("_", "-", dates), format = "%Y-%m-%d")
                
                # Filter by date range if not auto
                if (!input$ts_auto_range) {
                  date_filter <- dates >= input$ts_date_range[1] & dates <= input$ts_date_range[2]
                  tif_files <- tif_files[date_filter]
                  dates <- dates[date_filter]
                }
                
                # Calculate mean value for each raster
                values <- vapply(tif_files, function(f) {
                  r <- terra::rast(f)
                  mean(terra::values(r), na.rm = TRUE)
                }, numeric(1))
                
                data.frame(
                  date = dates,
                  value = values,
                  variable = vars[i],
                  identifier = "Mean",
                  stringsAsFactors = FALSE
                )
              }, error = function(e) {
                showNotification(paste("Error reading", vars[i], ":", e$message), type = "warning")
                return(NULL)
              })
            })
            
            ts_combined <- do.call(rbind, Filter(Negate(is.null), ts_list))
            
            if (is.null(ts_combined) || nrow(ts_combined) == 0) {
              showNotification("No data extracted", type = "error")
              return(NULL)
            }
            
            return(ts_combined)
          })
        }
      })
    })
    
    ## --- Update rv$ts_data when extraction completes ---
    observeEvent(input$ts_plot_btn, {
      rv$ts_data <- extract_timeseries()
      
      if (!is.null(rv$ts_data)) {
        showNotification("Time series extracted successfully", type = "message")
      }
    })
    
    ## --- Generate Plot ---
    output$ts_plot <- renderPlot({
      req(rv$ts_data)
      
      df <- rv$ts_data
      plot_type <- input$ts_plot_type
      facet_vars <- input$ts_facet_vars
      show_mean <- input$ts_show_mean
      
      # Base plot
      p <- ggplot2::ggplot(df, ggplot2::aes(x = date, y = value, color = identifier)) +
        ggplot2::labs(
          x = "Date",
          y = "Value",
          color = "Feature",
          title = "Time Series Analysis"
        ) +
        ggplot2::theme_minimal(base_size = 14) +
        ggplot2::theme(
          legend.position = "bottom",
          plot.title = ggplot2::element_text(face = "bold", size = 16)
        )
      
      # Add geom based on plot type
      if (plot_type == "line") {
        p <- p + ggplot2::geom_line(linewidth = 0.8)
      } else if (plot_type == "point") {
        p <- p + ggplot2::geom_point(size = 2)
      } else if (plot_type == "both") {
        p <- p + ggplot2::geom_line(linewidth = 0.8) + ggplot2::geom_point(size = 2)
      } else if (plot_type == "smooth") {
        p <- p + ggplot2::geom_smooth(method = "loess", se = TRUE, linewidth = 1)
      } else if (plot_type == "seasonal") {
        # Add seasonal decomposition / regression
        p <- p + ggplot2::geom_line(linewidth = 0.6, alpha = 0.5) +
          ggplot2::geom_smooth(method = "gam", formula = y ~ s(x, bs = "cc"), se = TRUE, linewidth = 1.2)
      }
      
      # Add mean line if requested (for vector data with multiple features)
      if (show_mean && input$ts_source == "vector") {
        df_mean <- df %>%
          dplyr::group_by(date, variable) %>%
          dplyr::summarise(mean_value = mean(value, na.rm = TRUE), .groups = "drop")
        
        p <- p + ggplot2::geom_line(
          data = df_mean,
          ggplot2::aes(x = date, y = mean_value),
          color = "black",
          linewidth = 1.2,
          linetype = "dashed",
          inherit.aes = FALSE
        )
      }
      
      # Facet by variable if requested
      if (facet_vars && length(unique(df$variable)) > 1) {
        p <- p + ggplot2::facet_wrap(~ variable, scales = "free_y", ncol = 1)
      }
      
      p
    })
    
    ## --- Data Table ---
    output$ts_data_table <- DT::renderDT({
      req(rv$ts_data)
      
      DT::datatable(
        rv$ts_data,
        options = list(
          pageLength = 25,
          scrollX = TRUE,
          order = list(list(1, 'asc'))  # Sort by date column
        ),
        rownames = FALSE
      )
    })
    
    ## --- Summary Statistics ---
    output$ts_summary <- renderPrint({
      req(rv$ts_data)
      
      cat("=== Time Series Summary ===\n\n")
      cat("Total observations:", nrow(rv$ts_data), "\n")
      cat("Variables:", paste(unique(rv$ts_data$variable), collapse = ", "), "\n")
      cat("Date range:", min(rv$ts_data$date), "to", max(rv$ts_data$date), "\n")
      cat("Unique features:", length(unique(rv$ts_data$identifier)), "\n\n")
      
      cat("--- Summary by Variable ---\n")
      print(summary(rv$ts_data))
    })
    
    ## --- Export Handlers ---
    output$ts_export_csv <- downloadHandler(
      filename = function() {
        paste0("timeseries_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) {
        req(rv$ts_data)
        write.csv(rv$ts_data, file, row.names = FALSE)
      }
    )
    
    output$ts_export_parquet <- downloadHandler(
      filename = function() {
        paste0("timeseries_", format(Sys.Date(), "%Y%m%d"), ".parquet")
      },
      content = function(file) {
        req(rv$ts_data)
        if (requireNamespace("arrow", quietly = TRUE)) {
          arrow::write_parquet(rv$ts_data, file)
        } else {
          showNotification("arrow package not installed", type = "error")
        }
      }
    )
    
    output$ts_export_rds <- downloadHandler(
      filename = function() {
        paste0("timeseries_", format(Sys.Date(), "%Y%m%d"), ".rds")
      },
      content = function(file) {
        req(rv$ts_data)
        saveRDS(rv$ts_data, file)
      }
    )
    
    ## --- Reset Handler ---
    observeEvent(input$ts_reset_btn, {
      rv$ts_data <- NULL
      rv$vector_sf <- NULL
      updateSelectInput(session, "ts_variables", selected = character(0))
    })
  })
}
