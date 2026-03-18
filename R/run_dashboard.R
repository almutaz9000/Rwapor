#' Run the Rwapor Shiny Dashboard
#'
#' Launches an interactive Shiny application that provides a graphical user
#' interface for configuring and executing WaPOR and AgERA5 data downloads
#' via the \code{\link{wapor_map}} function.
#'
#' @param display.mode Character. Passed to [shiny::runApp()].
#' @param launch.browser Logical. Passed to [shiny::runApp()].
#' @param ... Additional arguments passed to [shiny::runApp()].
#'
#' @details
#' The dashboard allows users to:
#' \itemize{
#'   \item Select variables (WaPOR or AgERA5).
#'   \item Define regions of interest by drawing bounding boxes on a satellite map or by uploading a vector file (.geojson, .gpkg, .kml).
#'   \item Configure output formats, unit conversions, and temporal periods.
#'   \item Preview the exact R code that will be executed.
#'   \item Trigger data downloads directly from the interface.
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' run_wapor()
#' }
run_wapor <- function(display.mode = "normal", launch.browser = interactive(), ...) {
  # 1. Try finding it in the installed package
  app_dir <- system.file("shiny", package = "Rwapor")
  
  # 2. Fallback for local development (if package is not yet installed)
  if (app_dir == "") {
    local_path <- file.path("inst", "shiny")
    if (dir.exists(local_path)) {
      app_dir <- local_path
    }
  }
  
  if (app_dir == "") {
    stop("Could not find shiny directory. Try re-installing `Rwapor` or running from the package root.", call. = FALSE)
  }
  
  app_file <- file.path(app_dir, "app.R")
  if (!file.exists(app_file)) {
    stop(sprintf("Could not find dashboard app.R at %s", app_dir), call. = FALSE)
  }
  
  # Ensure required suggest packages are available
  required_pkgs <- c("shiny", "leaflet", "bslib", "shinyFiles", "shinyvalidate", "shinyjs", "shinyAce")
  missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace, quietly = TRUE, FUN.VALUE = logical(1))]
  
  if (length(missing_pkgs) > 0) {
    stop("The following packages are required for the dashboard but are not installed:\n  ",
         paste(missing_pkgs, collapse = ", "),
         "\n\nPlease install them using:\n  install.packages(c('", 
         paste(missing_pkgs, collapse = "', '"), "'))", 
         call. = FALSE)
  }
  
  message("Starting Rwapor Dashboard from: ", app_dir)
  shiny::runApp(
    app_dir,
    display.mode = display.mode,
    launch.browser = launch.browser,
    ...
  )
}
