#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: repro_alignment_check.R <raster_a.tif> <raster_b.tif>")
}

if (!requireNamespace("terra", quietly = TRUE)) {
  stop("terra package is required.")
}

a <- terra::rast(args[[1]])
b <- terra::rast(args[[2]])

report <- list(
  a_path = normalizePath(args[[1]], winslash = "/", mustWork = FALSE),
  b_path = normalizePath(args[[2]], winslash = "/", mustWork = FALSE),
  a_crs = terra::crs(a, proj = TRUE),
  b_crs = terra::crs(b, proj = TRUE),
  a_extent = as.character(terra::ext(a)),
  b_extent = as.character(terra::ext(b)),
  a_res = paste(terra::res(a), collapse = ","),
  b_res = paste(terra::res(b), collapse = ","),
  overlap_cells = terra::global(!is.na(terra::crop(a, terra::ext(b))), "sum", na.rm = TRUE)[1, 1]
)

cat("Alignment report\n")
cat("================\n")
for (nm in names(report)) {
  cat(sprintf("%s: %s\n", nm, report[[nm]]))
}

if (!identical(report$a_crs, report$b_crs)) {
  cat("\n[WARN] CRS differs between rasters.\n")
}
