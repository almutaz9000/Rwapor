#!/usr/bin/env Rscript
# Minimal smoke check: structured return path + centralized /vsicurl prefix helper.
# No live WaPOR API calls, no rasters opened from vsicurl URLs.

setwd("C:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor")
devtools::load_all(".", quiet = TRUE)
cat("loaded Rwapor via devtools::load_all()\n")

cat("\n=== 1. Parse check: all touched R files compile cleanly ===\n")
for (f in c("R/utils.R","R/wapor_cog.R","R/analysis_engine.R",
            "R/analysis_tiled.R","R/seasonal_download.R","R/api_client.R")) {
  stopifnot(file.exists(f))
  parse(file = f)
  cat(sprintf("  %s ... OK\n", f))
}

cat("\n=== 2. Centralized /vsicurl prefix helper (.wapor_prefix_vsicurl) ===\n")
fake <- c(
  "https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-01-D1.tif",
  "/vsicurl/https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-01-D2.tif",
  "/vsicurl/https://gismgr.fao.org/already/prefixed.tif",
  "relative/path/file.tif",
  character(0)
)
out <- .wapor_prefix_vsicurl(fake)
stopifnot(length(out) == length(fake))
for (i in seq_along(fake)) {
  x <- fake[i]; y <- out[i]
  if (length(x) == 0L) {
    cat(sprintf("  [%d] empty input -> empty output ... OK\n", i))
    next
  }
  if (grepl("^/vsicurl/", x)) {
    ok <- identical(y, x)
    cat(sprintf("  [%d] already prefixed -> identical: %s ... %s\n", i, if(ok)"yes":"NO", if(ok)"OK"else"FAIL"))
    stopifnot(ok)
  } else {
    ok <- identical(y, paste0("/vsicurl/", x))
    cat(sprintf("  [%d] bare url -> prefixed once: %s ... %s\n", i, if(ok)"yes":"NO", if(ok)"OK"else"FAIL"))
    stopifnot(ok)
    stopifnot(!grepl("/vsicurl//vsicurl/", y))
  }
  stopifnot(grepl("^/vsicurl/", y))
}
cat("  -> .wapor_prefix_vsicurl contract holds on all fake URLs.\n")

cat("\n=== 3. Structured return path: wapor_date_info ===\n")
info <- wapor_date_info(
  "https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-01-D1.tif",
  tres = "D")
stopifnot(is.list(info))
stopifnot(all(c("start_date","end_date","number_of_days","raw_date") %in% names(info)))
stopifnot(is.character(info$start_date), length(info$start_date) == 1)
stopifnot(is.character(info$end_date),   length(info$end_date) == 1)
stopifnot(is.numeric(info$number_of_days), length(info$number_of_days) == 1)
stopifnot(info$start_date == "2023-01-01")
stopifnot(info$end_date   == "2023-01-10")
stopifnot(info$number_of_days == 10)
cat("  wapor_date_info return shape + values ... OK\n")

cat("\n=== 4. Structured return path: wapor_resolve_l3_selection ===\n")
sel <- wapor_resolve_l3_selection(c("AWA","LDA"), l3_region = "AWA", l3_mode = "select")
stopifnot(identical(sel, "AWA"))
cat("  single select ... OK\n")
sel_all <- wapor_resolve_l3_selection(c("AWA","LDA"), l3_mode = "mosaic_all")
stopifnot(identical(sort(sel_all), c("AWA","LDA")))
cat("  mosaic_all ... OK\n")

cat("\n=== 5. Structured return path: wapor_parse_region (bbox + L3 code) ===\n")
bb <- wapor_parse_region(c(35.0, 33.0, 36.0, 34.0))
stopifnot(identical(bb$type, "bbox"))
stopifnot(inherits(bb$value, "bbox"))
cat("  bbox parse ... OK\n")
l3 <- wapor_parse_region("AWA")
stopifnot(identical(l3$type, "l3_code"))
stopifnot(identical(l3$value, "AWA"))
cat("  L3 code parse ... OK\n")

cat("\n=== 6. Structured return path: wapor_write_cog argument validation ===\n")
ok <- tryCatch({ wapor_write_cog(NULL, "x.tif"); FALSE },
               error = function(e) grepl("must be a SpatRaster", conditionMessage(e)))
stopifnot(ok); cat("  rejects non-SpatRaster ... OK\n")
ok <- tryCatch({ wapor_write_cog(terra::rast(ncols=2,nrows=2), ""); FALSE },
               error = function(e) grepl("non-empty path", conditionMessage(e)))
stopifnot(ok); cat("  rejects empty filename ... OK\n")

cat("\n=== 7. Structured return path: get_seasonal_multiplier_values (empty plan) ===\n")
m <- get_seasonal_multiplier_values("L1-AETI-D", data.frame())
stopifnot(identical(m, numeric(0)))
cat("  empty plan -> numeric(0) ... OK\n")

cat("\n=== 8. Structured return path: analysis_tiled window helpers ===\n")
wins <- .wapor_tiled_row_windows(10L, 4L)
stopifnot(is.list(wins), length(wins) == 3L)
stopifnot(identical(wins[[1]], list(row=1L, nrows=4L)))
stopifnot(identical(wins[[3]], list(row=9L, nrows=2L)))
cat("  .wapor_tiled_row_windows ... OK\n")
grid <- .wapor_tiled_windows(10L, 10L, 4L)
stopifnot(is.list(grid), length(grid) == 9L)
stopifnot(all(c("id","row","col","nrows","ncols") %in% names(grid[[1]])))
cat("  .wapor_tiled_windows ... OK\n")

cat("\n=== 9. Structured return path: wapor_write_l3_mosaic input validation ===\n")
ok <- tryCatch({ wapor_write_l3_mosaic(character(0), "d", "s"); FALSE },
               error = function(e) grepl("named vector of existing", conditionMessage(e)))
stopifnot(ok)
cat("  rejects empty asset_paths ... OK\n")

cat("\n=== 10. Structured return path: wapor_suggest_tile_size ===\n")
t <- suppressMessages(wapor_suggest_tile_size(36L, 2L, target_ram_mb = 8192))
stopifnot(is.integer(t), t >= 64L, t <= 4096L)
cat(sprintf("  suggested tile size = %d ... OK\n", t))

cat("\n=== ALL CHECKS PASSED ===\n")
q("no")
