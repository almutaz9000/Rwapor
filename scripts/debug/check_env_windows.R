#!/usr/bin/env Rscript

cat("Rwapor environment diagnostics\n")
cat("============================\n")
cat("R version:", R.version.string, "\n")
cat("R.home():", R.home(), "\n")
cat("Working directory:", normalizePath(getwd(), winslash = "/", mustWork = FALSE), "\n\n")

pkgs <- c("terra", "sf", "httr2", "future", "testthat", "devtools")
for (pkg in pkgs) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("[OK] %s %s\n", pkg, as.character(utils::packageVersion(pkg))))
  } else {
    cat(sprintf("[MISSING] %s\n", pkg))
  }
}

cat("\nSystem environment snippets\n")
cat("PROJ_LIB:", Sys.getenv("PROJ_LIB"), "\n")
cat("GDAL_DATA:", Sys.getenv("GDAL_DATA"), "\n")
cat("R_LIBS_USER:", Sys.getenv("R_LIBS_USER"), "\n")

cat("\nterra capabilities\n")
if (requireNamespace("terra", quietly = TRUE)) {
  print(terra::gdal())
  print(terra::proj_info())
}
