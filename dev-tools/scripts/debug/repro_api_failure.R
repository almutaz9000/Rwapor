#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
variable <- if (length(args) >= 1) args[[1]] else "L1-AETI-D"
start_date <- if (length(args) >= 2) args[[2]] else "2024-01-01"
end_date <- if (length(args) >= 3) args[[3]] else "2024-02-01"
out_dir <- if (length(args) >= 4) args[[4]] else file.path(tempdir(), "rwapor_api_repro")

if (!requireNamespace("Rwapor", quietly = TRUE)) {
  stop("Rwapor package is required for this script.")
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("API repro harness\n")
cat("Variable:", variable, "\n")
cat("Period:", start_date, "to", end_date, "\n")
cat("Output:", normalizePath(out_dir, winslash = "/", mustWork = FALSE), "\n\n")

bbox <- c(36.0, 8.0, 36.2, 8.2)

result <- tryCatch({
  Rwapor::wapor_map(
    region = bbox,
    variable = variable,
    period = c(start_date, end_date),
    folder = out_dir,
    separate_files = TRUE,
    parallel = FALSE,
    batching = FALSE
  )
}, error = function(e) {
  structure(list(error = conditionMessage(e)), class = "rwapor_api_error")
})

if (inherits(result, "rwapor_api_error")) {
  cat("[ERROR]", result$error, "\n")
  quit(status = 1)
}

cat("[OK] Request completed.\n")
