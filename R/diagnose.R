#' Diagnose Agent and System Setup
#'
#' Runs diagnostic checks on the active system to verify R version, spatial libraries (GDAL/PROJ),
#' package dependencies, gcloud authentication, and path/OneDrive configurations. Prints a detailed
#' markdown report useful for troubleshooting agent environments.
#'
#' @return Invisibly returns the diagnostic report string.
#' @export
#'
#' @examples
#' \dontrun{
#' wapor_diagnose_agent_setup()
#' }
wapor_diagnose_agent_setup <- function() {
  report <- c()
  report <- c(report, "# Rwapor Agent Diagnostics Report")
  report <- c(report, sprintf("- **Timestamp:** %s", Sys.time()))
  report <- c(report, sprintf("- **R Version:** %s", R.version.string))
  report <- c(report, sprintf("- **Platform:** %s", R.version$platform))
  report <- c(report, sprintf("- **Working Directory:** `%s`", getwd()))
  
  # Check OneDrive
  is_onedrive <- grepl("OneDrive", getwd(), ignore.case = TRUE)
  report <- c(report, sprintf("- **OneDrive Directory:** %s", if (is_onedrive) "Yes (Note: OneDrive paths on Windows can sometimes cause locking/PROJ issues)" else "No"))
  
  report <- c(report, "\n## 1. Spatial Libraries Status")
  
  # Environment variables check
  report <- c(report, "  - **Environment variables:**")
  proj_lib_val <- Sys.getenv("PROJ_LIB")
  gdal_data_val <- Sys.getenv("GDAL_DATA")
  report <- c(report, sprintf("    - `PROJ_LIB`: %s", if (proj_lib_val == "") "[Not Set]" else paste0("`", proj_lib_val, "`")))
  report <- c(report, sprintf("    - `GDAL_DATA`: %s", if (gdal_data_val == "") "[Not Set]" else paste0("`", gdal_data_val, "`")))

  # sf status
  if (requireNamespace("sf", quietly = TRUE)) {
    sf_version <- as.character(utils::packageVersion("sf"))
    deps <- sf::sf_extSoftVersion()
    report <- c(report, sprintf("- **`sf` Package:** Version %s", sf_version))
    report <- c(report, sprintf("  - GDAL: %s", deps["GDAL"]))
    report <- c(report, sprintf("  - PROJ: %s", deps["PROJ"]))
    report <- c(report, sprintf("  - GEOS: %s", deps["GEOS"]))
  } else {
    report <- c(report, "- **`sf` Package:** NOT INSTALLED")
  }
  
  # terra status
  if (requireNamespace("terra", quietly = TRUE)) {
    terra_version <- as.character(utils::packageVersion("terra"))
    gdal_info <- terra::gdal(lib="all")
    report <- c(report, sprintf("- **`terra` Package:** Version %s", terra_version))
    report <- c(report, sprintf("  - GDAL: %s", gdal_info["gdal"]))
    report <- c(report, sprintf("  - PROJ: %s", gdal_info["proj"]))
  } else {
    report <- c(report, "- **`terra` Package:** NOT INSTALLED")
  }
  
  # check exactextractr
  if (requireNamespace("exactextractr", quietly = TRUE)) {
    report <- c(report, sprintf("- **`exactextractr` Package:** Version %s", utils::packageVersion("exactextractr")))
  } else {
    report <- c(report, "- **`exactextractr` Package:** NOT INSTALLED")
  }

  report <- c(report, "\n## 2. Core Dependencies Status")
  deps <- c("shiny", "bslib", "shinyFiles", "shinyvalidate", "future.apply", "httr2", "duckdb", "DBI")
  for (dep in deps) {
    if (requireNamespace(dep, quietly = TRUE)) {
      report <- c(report, sprintf("- **`%s`:** Version %s", dep, utils::packageVersion(dep)))
    } else {
      report <- c(report, sprintf("- **`%s`:** NOT INSTALLED", dep))
    }
  }

  report <- c(report, "\n## 3. External CLI Dependencies")
  
  # Check gcloud
  gcloud_path <- Sys.which("gcloud")
  if (gcloud_path != "") {
    report <- c(report, sprintf("- **gcloud PATH:** `%s`", gcloud_path))
    # Try listing active accounts safely
    tryCatch({
      auth_list <- system("gcloud auth list --format=value(account)", intern = TRUE, ignore.stderr = TRUE)
      if (length(auth_list) > 0 && auth_list[1] != "") {
        report <- c(report, sprintf("  - **Active Account:** %s", paste(auth_list, collapse = ", ")))
      } else {
        report <- c(report, "  - **Active Account:** None detected (run `gcloud auth login`)")
      }
    }, error = function(e) {
      report <- c(report, "  - **Active Account Check Failed:** (unable to run command)")
    })
  } else {
    report <- c(report, "- **gcloud CLI:** NOT FOUND on system PATH")
  }
  
  # Check git
  git_path <- Sys.which("git")
  if (git_path != "") {
    report <- c(report, sprintf("- **git PATH:** `%s`", git_path))
    tryCatch({
      branch <- system("git rev-parse --abbrev-ref HEAD", intern = TRUE, ignore.stderr = TRUE)
      report <- c(report, sprintf("  - **Active Branch:** `%s`", branch))
    }, error = function(e) {})
  } else {
    report <- c(report, "- **git CLI:** NOT FOUND on system PATH")
  }
  
  report_str <- paste(report, collapse = "\n")
  cat(report_str, "\n")
  return(invisible(report_str))
}
