#!/usr/bin/env Rscript

# Development helper for refreshing bundled metadata snapshots.
# The package implementation owns API access, normalization, validation,
# provenance, atomic writes, and cache invalidation.

args <- commandArgs(trailingOnly = TRUE)
level <- if (length(args) >= 1L) args[[1L]] else "all"
dest <- if (length(args) >= 2L) args[[2L]] else NULL

script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[[1L]]) else ""
root <- if (nzchar(script_path)) {
  normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}

if (!file.exists(file.path(root, "DESCRIPTION"))) {
  stop("Run this development helper from an Rwapor source checkout.", call. = FALSE)
}
if (!requireNamespace("pkgload", quietly = TRUE)) {
  stop("Install the 'pkgload' package to refresh bundled metadata.", call. = FALSE)
}

pkgload::load_all(root, quiet = TRUE)
if (is.null(dest)) dest <- file.path(root, "inst", "metadata")
Rwapor::wapor_update_metadata(level = level, dest = dest)
