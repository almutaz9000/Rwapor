# Rwapor large-raster benchmark
# =============================================================================
# Measures peak process memory and run time of wapor_run_seasonal_analysis()
# in memory, stream and tiled modes on synthetic data, optionally against an
# older checkout of the package.
#
# Usage (from a shell):
#   Rscript large_raster_benchmark.R [pkg_path] [old_pkg_path] [nrow] [n_dekads] [budget_mb]
#
#   pkg_path      Package source to benchmark (default: current directory).
#   old_pkg_path  Optional source checkout to compare against, for example a
#                 worktree of the v1.0.0-final tag. Use "-" to skip.
#   nrow          Analysis grid side in cells (default 1500, a 30 km AOI at 20 m).
#   n_dekads      Dekads in the season (default 18).
#   budget_mb     Rwapor.memory_budget_mb given to the planner (default 512).
#
# Each run happens in its own R process. Memory is sampled from that process
# every 0.1 s with the ps package; "peak" is the highest resident set size and
# "above_baseline" subtracts the size of an R session with the package loaded.
# Requires: processx, ps, pkgload, terra.

args <- commandArgs(trailingOnly = TRUE)
arg <- function(i, default) if (length(args) >= i && nzchar(args[i]) && args[i] != "-") args[i] else default
pkg_path <- normalizePath(arg(1, "."), winslash = "/")
old_path <- arg(2, NA_character_)
nrow_big <- as.integer(arg(3, "1500"))
n_dekads <- as.integer(arg(4, "18"))
budget_mb <- as.numeric(arg(5, "512"))

for (p in c("processx", "ps", "pkgload", "terra")) {
  if (!requireNamespace(p, quietly = TRUE)) stop("Package required: ", p, call. = FALSE)
}
# Loading the package also points PROJ at the right database (wapor_fix_proj()),
# which matters on machines where another PROJ, such as PostGIS, is on the PATH.
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE, export_all = FALSE))

work <- normalizePath(file.path(tempdir(), "rwapor-bench"), winslash = "/", mustWork = FALSE)
dir.create(work, showWarnings = FALSE, recursive = TRUE)

# --- Synthetic inputs ---------------------------------------------------------
dekad_starts <- function(n) {
  months <- seq(as.Date("2023-01-01"), by = "month", length.out = ceiling(n / 3))
  sort(c(months, months + 10, months + 20))[seq_len(n)]
}

period_end <- function(last_start) {
  if (format(last_start, "%d") == "21") {
    first_next <- seq(as.Date(format(last_start, "%Y-%m-01")), by = "month", length.out = 2)[2]
    first_next - 1
  } else {
    last_start + 9
  }
}

make_fixture <- function(root, n, n_dekads, seed = 1) {
  if (file.exists(file.path(root, "ready"))) return(invisible(root))
  set.seed(seed)
  dir.create(root, showWarnings = FALSE, recursive = TRUE)
  res <- 0.0002  # about 20 m
  aoi <- terra::rast(nrows = n, ncols = n, xmin = 35, xmax = 35 + n * res,
                     ymin = 33, ymax = 33 + n * res, crs = "EPSG:4326")
  coarse <- terra::rast(terra::extend(terra::ext(aoi), 0.2), resolution = 0.1, crs = "EPSG:4326")
  dk <- dekad_starts(n_dekads)
  write_var <- function(var, grid) {
    d <- file.path(root, var)
    dir.create(d, showWarnings = FALSE)
    for (i in seq_along(dk)) {
      r <- terra::init(grid, fun = function(k) stats::runif(k, 1, 6))
      terra::writeRaster(r, file.path(d, sprintf("WAPOR-3.%s.%s.tif", var, format(dk[i]))),
                         overwrite = TRUE, gdal = c("TILED=YES", "COMPRESS=LZW"))
    }
  }
  write_var("L1-AETI-D", aoi)
  write_var("L1-RET-D", coarse)
  mask <- terra::init(aoi, fun = function(k) sample(c(1L, 2L), k, TRUE))
  terra::writeRaster(mask, file.path(root, "mask.tif"), overwrite = TRUE, datatype = "INT1U")
  writeLines(format(period_end(max(dk))), file.path(root, "period_end"))
  writeLines("ok", file.path(root, "ready"))
  invisible(root)
}

# --- One measured run in a child process ----------------------------------------
child_script <- function(pkg, root, mode, budget_mb, baseline_only = FALSE) {
  # Paths are inserted with deparse() so backslashes in Windows paths
  # (C:\Users\...) are escaped instead of being read as R escape sequences.
  sprintf('
suppressMessages(pkgload::load_all(%s, quiet = TRUE, export_all = FALSE))
options(Rwapor.memory_budget_mb = %s)
invisible(gc())
cat("LOADED\\n")
if (%s) { Sys.sleep(2); quit(save = "no") }
root <- %s
mask <- terra::rast(file.path(root, "mask.tif"))
period_end <- readLines(file.path(root, "period_end"))
config <- list(
  period = c("2023-01-01", period_end), data_source = "local", folder = root,
  aeti_var = "L1-AETI-D", ret_var = "L1-RET-D",
  indicators = c("agg_aeti", "agg_ret", "etc", "adequacy_etc"),
  use_crop_mask = TRUE, use_season_rasters = FALSE,
  processing = %s, output_dir = tempfile("bench-run-")
)
cp <- data.frame(class_value = c(1L, 2L), crop_label = c("A", "B"), kc_ini = 0.5, kc_mid = 1.1,
                 kc_end = 0.7, l_ini_days = 15L, l_mid_days = 40L, l_late_days = 20L,
                 HI = 0.4, MC = 0.1, fc = 1, AOT = 1)
t0 <- proc.time()[["elapsed"]]
res <- suppressMessages(wapor_run_seasonal_analysis(config, cp, list(crop_mask = mask)))
m <- terra::global(res$seasonal_aeti$raster, "mean", na.rm = TRUE)[[1]]
cat(sprintf("RESULT %%.3f %%s %%.6f\\n", proc.time()[["elapsed"]] - t0,
            if (is.null(res$processing)) "legacy" else res$processing$mode, m))
', deparse(pkg), budget_mb, if (baseline_only) "TRUE" else "FALSE", deparse(root), deparse(mode))
}

measure <- function(pkg, root, mode, budget_mb, baseline_only = FALSE) {
  script <- tempfile(fileext = ".R")
  writeLines(child_script(pkg, root, mode, budget_mb, baseline_only), script)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  p <- processx::process$new(rscript, script, stdout = "|", stderr = "|")
  h <- ps::ps_handle(p$get_pid())
  peak <- 0
  out <- character(0)
  while (p$is_alive()) {
    rss <- tryCatch(ps::ps_memory_info(h)[["rss"]], error = function(e) NA)
    if (is.finite(rss)) peak <- max(peak, rss)
    out <- c(out, p$read_output_lines())
    Sys.sleep(0.1)
  }
  out <- c(out, p$read_all_output_lines())
  err <- p$read_all_error()
  line <- grep("^RESULT", out, value = TRUE)
  if (baseline_only && !any(out == "LOADED")) {
    stop("The baseline R session could not load the package, so no run can be measured:\n",
         err, call. = FALSE)
  }
  if (!baseline_only && !length(line)) {
    # Record the failure (for example out of memory) and keep benchmarking.
    err_lines <- strsplit(err, "\n")[[1]]
    msg <- trimws(c(grep("^Error", err_lines, value = TRUE), tail(err_lines, 1))[1])
    message(sprintf("Run failed (%s, %s): %s", basename(pkg), mode, msg))
    line <- sprintf("RESULT NA FAILED:%s NA", gsub("\\s+", "_", msg))
  }
  parts <- if (length(line)) strsplit(line, " ")[[1]] else c("", NA, NA, NA)
  data.frame(package = basename(pkg), requested = mode, mode = parts[3],
             seconds = as.numeric(parts[2]), peak_mb = peak / 1024^2,
             mean_aeti = as.numeric(parts[4]), stringsAsFactors = FALSE)
}

# --- Run -------------------------------------------------------------------------
big <- file.path(work, sprintf("big-%d-%d", nrow_big, n_dekads))
small <- file.path(work, sprintf("small-%d", n_dekads))
cat(sprintf("Preparing inputs: %d x %d cells, %d dekads ...\n", nrow_big, nrow_big, n_dekads))
make_fixture(big, nrow_big, n_dekads)
make_fixture(small, 500L, n_dekads)

pkgs <- c(new = pkg_path)
if (!is.na(old_path)) pkgs <- c(old = normalizePath(old_path, winslash = "/"), pkgs)

baseline <- measure(pkg_path, big, "auto", budget_mb, baseline_only = TRUE)$peak_mb
cat(sprintf("Baseline R session with the package loaded: %.0f MB\n", baseline))

rows <- list()
for (nm in names(pkgs)) {
  modes <- if (nm == "old") "auto" else c("memory", "stream", "tiled")
  for (m in modes) {
    cat(sprintf("Running %s / %s ...\n", nm, m))
    r <- measure(pkgs[[nm]], big, m, budget_mb)
    r$package <- nm
    rows[[length(rows) + 1]] <- r
  }
  for (rep in 1:3) {
    r <- measure(pkgs[[nm]], small, "auto", budget_mb)
    r$package <- nm
    r$requested <- sprintf("small-auto-%d", rep)
    rows[[length(rows) + 1]] <- r
  }
}
tab <- do.call(rbind, rows)
tab$above_baseline_mb <- tab$peak_mb - baseline
tab$budget_mb <- budget_mb
print(tab, row.names = FALSE, digits = 4)

small_tab <- tab[grepl("^small", tab$requested), ]
if (length(unique(small_tab$package)) == 2) {
  med <- tapply(small_tab$seconds, small_tab$package, stats::median)
  cat(sprintf("\nSmall in-memory job, median seconds: old %.2f, new %.2f (%+.0f%%)\n",
              med[["old"]], med[["new"]], 100 * (med[["new"]] / med[["old"]] - 1)))
}
big_new <- tab[tab$package == "new" & !grepl("^small", tab$requested), ]
n_failed <- sum(grepl("^FAILED", tab$mode))
if (n_failed) {
  cat(sprintf("\n%d of %d run(s) FAILED (see the mode column); checks below use successful runs only.\n",
              n_failed, nrow(tab)))
}
ok <- big_new[!grepl("^FAILED", big_new$mode), ]
stream_tiled <- ok[ok$mode %in% c("stream", "tiled"), ]
cat("\nStream/tiled above-baseline peak within budget: ",
    if (nrow(stream_tiled)) all(stream_tiled$above_baseline_mb <= budget_mb) else "NOT MEASURED",
    "\n", sep = "")
cat("Modes agree on mean AETI: ",
    if (nrow(ok) >= 2) isTRUE(all.equal(ok$mean_aeti, rep(ok$mean_aeti[1], nrow(ok)), tolerance = 1e-6))
    else "NOT MEASURED",
    "\n", sep = "")
utils::write.csv(tab, file.path(work, "benchmark_results.csv"), row.names = FALSE)
cat("Results written to", file.path(work, "benchmark_results.csv"), "\n")
