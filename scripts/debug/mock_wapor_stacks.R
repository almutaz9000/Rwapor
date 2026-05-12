#!/usr/bin/env Rscript

if (!requireNamespace("terra", quietly = TRUE)) {
  stop("terra package is required.")
}

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[[1]] else file.path(tempdir(), "rwapor_mock")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

set.seed(42)
base <- terra::rast(ncols = 50, nrows = 50, xmin = 36, xmax = 37, ymin = 8, ymax = 9, crs = "EPSG:4326")

make_stack <- function(prefix, layers, low, high) {
  r <- terra::rast(replicate(layers, base, simplify = FALSE))
  names(r) <- sprintf("%s_%02d", prefix, seq_len(layers))
  for (i in seq_len(layers)) {
    values <- stats::runif(terra::ncell(base), min = low, max = high)
    terra::values(r[[i]]) <- values
  }
  r
}

aeti <- make_stack("AETI", 6, 0, 8)
ret <- make_stack("RET", 6, 1, 10)
pcp <- make_stack("PCP", 6, 0, 12)

terra::writeRaster(aeti, file.path(out_dir, "mock_aeti.tif"), overwrite = TRUE)
terra::writeRaster(ret, file.path(out_dir, "mock_ret.tif"), overwrite = TRUE)
terra::writeRaster(pcp, file.path(out_dir, "mock_pcp.tif"), overwrite = TRUE)

cat("Mock stacks written to:", normalizePath(out_dir, winslash = "/", mustWork = FALSE), "\n")
