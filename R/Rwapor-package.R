#' @keywords internal
#' @section Options:
#' \describe{
#'   \item{`Rwapor.verbose`}{Print progress messages (default `TRUE`). Warnings are always shown.}
#'   \item{`Rwapor.disk_check`}{Check free disk space before file-backed processing (default `TRUE`).}
#'   \item{`Rwapor.memory_budget_mb`}{Memory budget in MB for processing; by default half of available memory is used.}
#'   \item{`Rwapor.cache_ttl`}{URL metadata cache lifetime in seconds (default `86400`).}
#'   \item{`Rwapor.remote_fallback`}{Remote-read fallback mode (default `"stream"`; use `"download"` for the local cache).}
#'   \item{`Rwapor.configure_gdal`}{Configure GDAL on package load when needed (default `TRUE`).}
#'   \item{`Rwapor.max_season_profiles`}{Maximum number of per-pixel season profiles (default `64`).}
#'   \item{`Rwapor.plan_thresholds`}{Optional named processing-mode thresholds; defaults are calculated from the memory budget.}
#'   \item{`Rwapor.remote_cache_dir`}{Directory for cached remote rasters; by default the R user cache directory is used.}
#' }
"_PACKAGE"
