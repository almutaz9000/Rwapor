#!/usr/bin/env Rscript

if (!requireNamespace("profvis", quietly = TRUE)) {
  stop("profvis package is required. Install with install.packages('profvis').")
}

if (!requireNamespace("Rwapor", quietly = TRUE)) {
  stop("Rwapor package is required.")
}

cat("Profiling seasonal analysis entrypoint scaffold...\n")
cat("Edit this script with a concrete local dataset before use.\n")

# Minimal profiling wrapper. Replace `expr` with your reproducible workload.
prof <- profvis::profvis({
  Sys.sleep(0.25)
  # Example only:
  # Rwapor::wapor_run_seasonal_analysis(
  #   period = c("2023-10-01", "2024-05-31"),
  #   folder = "path/to/local/data",
  #   crop_mask = "path/to/crop_mask.tif",
  #   season_start = "path/to/season_start.tif",
  #   season_end = "path/to/season_end.tif"
  # )
})

html_out <- file.path(getwd(), "profile_seasonal_analysis.html")
htmlwidgets::saveWidget(prof, file = html_out, selfcontained = TRUE)
cat("Profile report:", normalizePath(html_out, winslash = "/", mustWork = FALSE), "\n")
