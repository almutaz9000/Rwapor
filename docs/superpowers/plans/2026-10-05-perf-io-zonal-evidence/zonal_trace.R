a <- commandArgs(trailingOnly = TRUE); nlyr <- as.integer(a[1]); which_fn <- if (length(a) > 1) a[2] else "new"
suppressMessages(pkgload::load_all(".", quiet = TRUE)); options(Rwapor.memory_budget_mb = 512)
mkfile <- function(n, nlyr) { tf <- tempfile(fileext = ".tif")
  r <- terra::rast(nrows = n, ncols = n, xmin = 5e5, xmax = 5e5 + 20 * n, ymin = 35e5, ymax = 35e5 + 20 * n, crs = "EPSG:32636", nlyrs = nlyr)
  set.seed(1); terra::values(r) <- round(runif(n * n * nlyr, 0, 80)) / 10; names(r) <- sprintf("d%02d", seq_len(nlyr)); terra::units(r) <- "mm/day"
  terra::writeRaster(r, tf, datatype = "FLT4S"); tf }
r <- terra::rast(mkfile(900L, nlyr))
z <- sf::st_sf(farm = "ALL", geometry = sf::st_as_sfc(sf::st_bbox(c(xmin = 5e5 + 7, ymin = 35e5 + 7, xmax = 5e5 + 17993, ymax = 35e5 + 17993), crs = 32636)))
invisible(gc(reset = TRUE)); base <- sum(gc()[, 2])
mx <- function(tag) cat(sprintf("  %-28s live %5.0f MB, max since reset %5.0f MB\n", tag, sum(gc()[, 2]) - base, sum(gc()[, 6]) - base))
if (FALSE) suppressMessages(trace(exactextractr::exact_extract, exit = quote(mx("after one exact_extract")), print = FALSE, where = asNamespace("Rwapor")))
t0 <- proc.time()[["elapsed"]]
f <- wapor_zonal_stats
if (which_fn == "old") { e <- new.env(parent = asNamespace("Rwapor")); sys.source("tests/testthat/helper-zonal-reference.R", envir = e); f <- e$reference_zonal_stats }
o <- suppressWarnings(f(r, z, id = "farm", dissolve = FALSE, aoi = FALSE)); cat(which_fn, "")
cat(sprintf("%d layers, 0.81 M cells in the zone: %.1f s\n", nlyr, proc.time()[["elapsed"]] - t0)); mx("after the function")

