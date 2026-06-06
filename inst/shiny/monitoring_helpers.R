# monitoring_helpers.R
# Helper functions for enhanced farm monitoring module
#
# NOTE: Most utility functions previously in this file have been migrated
# to the core Rwapor package (R/wapor_monitoring.R and R/wapor_plots_monitoring.R)
# to ensure consistent logic between the dashboard and standalone scripts.

# Null-coalescing operator (if not already defined by the Shiny runtime)
if (!exists("%||%", mode = "function", inherits = TRUE)) {
  `%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b
}
