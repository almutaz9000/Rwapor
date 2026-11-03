# Rwapor large-raster benchmark
# =============================================================================
# Measures peak process memory and run time of wapor_run_seasonal_analysis()
# in auto, memory, stream and tiled modes on synthetic data, optionally against an
# older checkout of the package.
#
# Usage (from a shell):
#   Rscript large_raster_benchmark.R [pkg_path] [old_pkg_path] [nrow] [n_dekads] [budget_mb] [workers] [results_dir] [modes]
#
#   pkg_path      Package source to benchmark (default: current directory).
#   old_pkg_path  Optional source checkout to compare against, for example a
#                 worktree of the v1.0.0-final tag. Use "-" to skip.
#   nrow          Analysis grid side in cells (default 1500, a 30 km AOI at 20 m).
#   n_dekads      Dekads in the season (default 18).
#   budget_mb     Rwapor.memory_budget_mb given to the planner (default 512).
#   workers       future workers for the benchmark child (default 1).
#   results_dir   Directory for benchmark_results.csv (default: temporary output).
#   modes         Comma-separated new-package modes to run (default: auto,memory,stream,tiled).
#                 Use a subset such as auto,tiled for a large run to avoid forced-memory stress.
#
# Each run happens in its own R process. Memory is sampled from that process
# and its child workers every 0.1 s; "peak" is the aggregate resident set size
# and "above_baseline" subtracts a single R session with the package loaded.
# GDAL/VSI caches start fresh per child process; the OS page cache is uncontrolled
# and is recorded in the CSV. Requires: processx, ps, pkgload, terra, sf.

args <- commandArgs(trailingOnly = TRUE)
arg <- function(i, default) if (length(args) >= i && nzchar(args[i]) && args[i] != "-") args[i] else default
pkg_path <- normalizePath(arg(1, "."), winslash = "/")
old_path <- arg(2, NA_character_)
nrow_big <- as.integer(arg(3, "1500"))
n_dekads <- as.integer(arg(4, "18"))
budget_mb <- as.numeric(arg(5, "512"))
workers <- as.integer(arg(6, "1"))
results_dir <- arg(7, file.path(tempdir(), "rwapor-bench-results"))
requested_modes <- unique(trimws(strsplit(arg(8, "auto,memory,stream,tiled"), ",", fixed = TRUE)[[1]]))
if (length(workers) != 1L || is.na(workers) || workers < 1L) {
  stop("workers must be a positive integer", call. = FALSE)
}
if (!length(requested_modes) || any(!requested_modes %in% c("auto", "memory", "stream", "tiled"))) {
  stop("modes must be a comma-separated subset of auto,memory,stream,tiled", call. = FALSE)
}

for (p in c("processx", "ps", "pkgload", "terra", "sf", "future", "future.apply")) {
  if (!requireNamespace(p, quietly = TRUE)) stop("Package required: ", p, call. = FALSE)
}
# Loading the package also points PROJ at the right database (wapor_fix_proj()),
# which matters on machines where another PROJ, such as PostGIS, is on the PATH.
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE, export_all = FALSE))

work <- normalizePath(file.path(tempdir(), "rwapor-bench"), winslash = "/", mustWork = FALSE)
dir.create(work, showWarnings = FALSE, recursive = TRUE)
results_dir <- path.expand(results_dir)
dir.create(results_dir, showWarnings = FALSE, recursive = TRUE)
results_dir <- normalizePath(results_dir, winslash = "/", mustWork = FALSE)

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
child_script <- function(pkg, root, mode, budget_mb, workers = 1L, baseline_only = FALSE) {
  # Paths are inserted with deparse() so backslashes in Windows paths
  # (C:\Users\...) are escaped instead of being read as R escape sequences.
  worker_plan <- if (workers > 1L) {
    sprintf("future::plan(future::multisession, workers = %dL)", workers)
  } else {
    "future::plan(future::sequential)"
  }
  worker_warmup <- if (workers > 1L) {
    sprintf(paste0(
      "invisible(future.apply::future_lapply(seq_len(%dL), function(i) { ",
      "writeLines(as.character(Sys.getpid()), file.path(worker_monitor_dir, ",
      "paste0('worker-', i, '.pid'))); TRUE }, future.scheduling = Inf))"
    ), workers)
  } else {
    "invisible(NULL)"
  }
  sprintf('
suppressMessages(pkgload::load_all(%s, quiet = TRUE, export_all = FALSE))
options(Rwapor.memory_budget_mb = %s)
%s
worker_monitor_dir <- Sys.getenv("RWAPOR_BENCH_MONITOR_DIR")
%s
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
if (is.null(res$processing)) {
  plan_workers <- 1L
  tile_size <- NA_integer_
  batch_size <- NA_integer_
  plan_budget_per_worker_mb <- NA_real_
  plan_total_budget_mb <- NA_real_
  planned_working_set_mb <- NA_real_
} else {
  plan <- res$processing
  plan_workers <- as.integer(plan$workers)
  tile_size <- as.integer(plan$tile_size)
  batch_size <- as.integer(plan$batch_size)
  fraction <- if (identical(plan$mode, "tiled") && is.finite(tile_size)) {
    min(1, tile_size^2 / max(plan$cells, 1))
  } else {
    1
  }
  active_batch <- if (identical(plan$mode, "memory")) plan$n_layers else plan$batch_size
  planned_working_set_mb <- Rwapor:::.wapor_working_set_bytes(
    plan$cells, plan$native_cells, plan$n_layers, plan$n_targets,
    batch = active_batch, frac = fraction
  ) / 1024^2
  plan_budget_per_worker_mb <- plan$budget_bytes / 1024^2
  plan_total_budget_mb <- plan_budget_per_worker_mb * plan_workers
}
cat(sprintf("RESULT %%.3f %%s %%.6f %%d %%s %%s %%.2f %%.2f %%.2f\\n", proc.time()[["elapsed"]] - t0,
            if (is.null(res$processing)) "legacy" else res$processing$mode, m,
            plan_workers, as.character(tile_size), as.character(batch_size),
            plan_budget_per_worker_mb, plan_total_budget_mb, planned_working_set_mb))
', deparse(pkg), budget_mb, worker_plan, worker_warmup,
        if (baseline_only) "TRUE" else "FALSE", deparse(root), deparse(mode))
}

process_pss_bytes <- function(pid) {
  if (!identical(Sys.info()[["sysname"]], "Linux") || length(pid) != 1L || is.na(pid)) {
    return(NA_real_)
  }
  path <- file.path("/proc", as.integer(pid), "smaps_rollup")
  lines <- suppressWarnings(tryCatch(readLines(path, warn = FALSE), error = function(e) character()))
  pss_line <- grep("^Pss:", lines, value = TRUE)
  if (!length(pss_line)) return(NA_real_)
  pss_kb <- suppressWarnings(as.numeric(sub(
    "^Pss:[[:space:]]*([0-9]+)[[:space:]]+kB.*$", "\\\\1", pss_line[[1]]
  )))
  if (!is.finite(pss_kb)) NA_real_ else pss_kb * 1024
}

measure <- function(pkg, root, mode, budget_mb, workers = 1L, baseline_only = FALSE) {
  script <- tempfile(fileext = ".R")
  writeLines(child_script(pkg, root, mode, budget_mb, workers, baseline_only), script)
  monitor_dir <- tempfile("rwapor-bench-monitor-")
  dir.create(monitor_dir, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(monitor_dir, recursive = TRUE, force = TRUE), add = TRUE)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  child_env <- Sys.getenv()
  child_env[["RWAPOR_BENCH_MONITOR_DIR"]] <- monitor_dir
  p <- processx::process$new(
    rscript, script, env = child_env,
    stdout = "|", stderr = "|"
  )
  h <- ps::ps_handle(p$get_pid())
  peak <- 0
  peak_worker <- 0
  peak_non_worker <- 0
  peak_pss <- NA_real_
  peak_worker_pss <- NA_real_
  peak_non_worker_pss <- NA_real_
  processes_at_peak <- 1L
  max_processes <- 1L
  out <- character(0)
  while (p$is_alive()) {
    worker_files <- list.files(monitor_dir, pattern = "^worker-[0-9]+[.]pid$", full.names = TRUE)
    worker_pids <- if (length(worker_files)) {
      unique(suppressWarnings(as.integer(unlist(lapply(worker_files, readLines, warn = FALSE)))))
    } else {
      integer(0)
    }
    worker_pids <- worker_pids[!is.na(worker_pids)]
    worker_handles <- lapply(worker_pids, function(pid) {
      tryCatch(ps::ps_handle(pid), error = function(e) NULL)
    })
    worker_handles <- Filter(Negate(is.null), worker_handles)
    children <- tryCatch(ps::ps_children(h, recursive = TRUE), error = function(e) list())
    handles <- c(list(h), children, worker_handles)
    pids <- vapply(handles, function(handle) {
      tryCatch(as.integer(ps::ps_pid(handle)), error = function(e) NA_integer_)
    }, integer(1))
    keep <- !is.na(pids) & !duplicated(pids)
    handles <- handles[keep]
    pids <- pids[keep]
    rss_values <- vapply(handles, function(handle) {
      tryCatch(as.numeric(ps::ps_memory_info(handle)[["rss"]]), error = function(e) NA_real_)
    }, numeric(1))
    worker_rss <- sum(rss_values[pids %in% worker_pids], na.rm = TRUE)
    non_worker_rss <- sum(rss_values[!(pids %in% worker_pids)], na.rm = TRUE)
    rss <- worker_rss + non_worker_rss
    pss_values <- vapply(pids, process_pss_bytes, numeric(1))
    if (any(is.finite(pss_values))) {
      worker_pss <- sum(pss_values[pids %in% worker_pids], na.rm = TRUE)
      non_worker_pss <- sum(pss_values[!(pids %in% worker_pids)], na.rm = TRUE)
      pss <- worker_pss + non_worker_pss
      peak_worker_pss <- max(if (is.finite(peak_worker_pss)) peak_worker_pss else 0, worker_pss)
      peak_non_worker_pss <- max(if (is.finite(peak_non_worker_pss)) peak_non_worker_pss else 0,
                                 non_worker_pss)
      peak_pss <- max(if (is.finite(peak_pss)) peak_pss else 0, pss)
    }
    peak_worker <- max(peak_worker, worker_rss)
    peak_non_worker <- max(peak_non_worker, non_worker_rss)
    if (is.finite(rss) && rss > peak) {
      peak <- rss
      processes_at_peak <- length(handles)
    }
    max_processes <- max(max_processes, length(handles))
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
    line <- sprintf("RESULT NA FAILED:%s NA NA NA NA NA NA NA", gsub("\\s+", "_", msg))
  }
  parts <- if (length(line)) strsplit(line, " ")[[1]] else rep(NA_character_, 10L)
  parse_int <- function(i) suppressWarnings(as.integer(parts[[i]]))
  parse_num <- function(i) suppressWarnings(as.numeric(parts[[i]]))
  data.frame(package = basename(pkg), requested = mode, mode = parts[3],
             workers = as.integer(workers),
             plan_workers = parse_int(5L),
             tile_size = parse_int(6L), batch_size = parse_int(7L),
             plan_budget_per_worker_mb = parse_num(8L),
             plan_total_budget_mb = parse_num(9L),
             planned_working_set_mb = parse_num(10L),
             processes_at_peak = as.integer(processes_at_peak),
             max_processes = as.integer(max_processes),
             peak_worker_mb = peak_worker / 1024^2,
             peak_non_worker_mb = peak_non_worker / 1024^2,
             peak_pss_mb = peak_pss / 1024^2,
             peak_worker_pss_mb = peak_worker_pss / 1024^2,
             peak_non_worker_pss_mb = peak_non_worker_pss / 1024^2,
             seconds = parse_num(2L), peak_mb = peak / 1024^2,
             mean_aeti = parse_num(4L), stringsAsFactors = FALSE)
}

# --- Run -------------------------------------------------------------------------
big <- file.path(work, sprintf("big-%d-%d", nrow_big, n_dekads))
small <- file.path(work, sprintf("small-%d", n_dekads))
cat(sprintf("Preparing inputs: %d x %d cells, %d dekads ...\n", nrow_big, nrow_big, n_dekads))
make_fixture(big, nrow_big, n_dekads)
make_fixture(small, 500L, n_dekads)

pkgs <- c(new = pkg_path)
if (!is.na(old_path)) pkgs <- c(old = normalizePath(old_path, winslash = "/"), pkgs)

baseline <- measure(pkg_path, big, "auto", budget_mb, workers = workers, baseline_only = TRUE)$peak_mb
cat(sprintf("Baseline process tree with the package and %d worker(s): %.0f MB\n", workers, baseline))

rows <- list()
for (nm in names(pkgs)) {
  modes <- if (nm == "old") "auto" else requested_modes
  for (m in modes) {
    cat(sprintf("Running %s / %s ...\n", nm, m))
    r <- measure(pkgs[[nm]], big, m, budget_mb, workers = workers)
    r$package <- nm
    rows[[length(rows) + 1]] <- r
  }
  for (rep in 1:3) {
    r <- measure(pkgs[[nm]], small, "auto", budget_mb, workers = workers)
    r$package <- nm
    r$requested <- sprintf("small-auto-%d", rep)
    rows[[length(rows) + 1]] <- r
  }
}
tab <- do.call(rbind, rows)
tab$above_baseline_mb <- tab$peak_mb - baseline
tab$budget_mb <- budget_mb
tab$grid_nrow <- nrow_big
tab$n_dekads <- n_dekads
tab$r_version <- R.version.string
tab$terra_version <- as.character(utils::packageVersion("terra"))
soft_versions <- sf::sf_extSoftVersion()
tab$gdal_version <- unname(soft_versions[["GDAL"]])
tab$proj_version <- unname(soft_versions[["PROJ"]])
tab$platform <- R.version$platform
tab$cache_condition <- "fresh R process; OS page cache uncontrolled"
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
results_file <- file.path(results_dir, "benchmark_results.csv")
utils::write.csv(tab, results_file, row.names = FALSE)
cat("Results written to", results_file, "\n")
