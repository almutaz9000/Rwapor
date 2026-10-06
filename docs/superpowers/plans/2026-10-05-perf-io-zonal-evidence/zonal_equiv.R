suppressMessages(pkgload::load_all(".", quiet = TRUE))
env <- new.env(parent = asNamespace("Rwapor")); sys.source("tests/testthat/helper-zonal-reference.R", envir = env)
ref <- env$reference_zonal_stats
set.seed(7)
r <- terra::rast(nrows = 120, ncols = 120, xmin = 700000, xmax = 702400, ymin = 3600000, ymax = 3602400, crs = "EPSG:32636", nlyrs = 12)
x <- round(runif(120 * 120 * 12, 0, 80)) / 10; x[sample(length(x), 4000)] <- NA
terra::values(r) <- x; names(r) <- sprintf("d%02d", 1:12); terra::units(r) <- "mm/day"
r[[1]][1:40, 1:40] <- NA   # one zone mostly without data (below min_coverage)
g <- expand.grid(i = 0:3, j = 0:3)
z <- sf::st_sf(scheme = paste0("S", g$i %/% 2), farm = sprintf("f%02d ", seq_len(16)),
  geometry = sf::st_sfc(lapply(seq_len(16), function(k) { x0 <- 700000 + g$i[k] * 600 + 7; y0 <- 3600000 + g$j[k] * 600 + 13
    sf::st_polygon(list(cbind(x0 + c(0, 430, 430, 0, 0), y0 + c(0, 0, 380, 380, 0)))) }), crs = 32636))
far <- sf::st_sf(scheme = "S9", farm = "away", geometry = sf::st_sfc(sf::st_polygon(list(cbind(c(9e5, 9e5 + 50, 9e5 + 50, 9e5, 9e5), c(36e5, 36e5, 36e5 + 50, 36e5 + 50, 36e5)))), crs = 32636))
tiny <- sf::st_sf(scheme = "S0", farm = "tiny", geometry = sf::st_sfc(sf::st_polygon(list(cbind(700905 + c(0, 30, 30, 0, 0), 3600905 + c(0, 0, 30, 30, 0)))), crs = 32636))
zz <- rbind(z, far, tiny)
mk <- terra::rast(r[[1]]); terra::values(mk) <- rbinom(14400, 1, .7); wt <- terra::rast(r[[1]]); terra::values(wt) <- runif(14400)
cl <- terra::rast(r[[1]]); terra::values(cl) <- sample(1:4, 14400, TRUE); names(cl) <- "cls"
ll <- terra::project(r[[1:3]], "EPSG:4326"); terra::units(ll) <- "mm"
all_stats <- c("mean", "sd", "cv", "cu", "du_lq", "gini", "theil", "min", "max", "count", "n_eff", "quantiles", "area_ha", "mask_fraction", "coverage", "sum_volume")
run <- function(f, args) { w <- character(); v <- withCallingHandlers(tryCatch(do.call(f, args), error = function(e) paste("ERROR:", conditionMessage(e))),
  warning = function(c) { w <<- c(w, conditionMessage(c)); invokeRestart("muffleWarning") }); list(v = v, w = w) }
cases <- list(
  "defaults, two id levels, dissolve, AOI" = list(x = r, zones = zz, id = c("scheme", "farm")),
  "all statistics, days" = list(x = r, zones = zz, id = "farm", stats = all_stats, days = rep(10, 12), dissolve = FALSE, aoi = FALSE),
  "all statistics, no days (volume skipped)" = list(x = r, zones = zz, id = "farm", stats = all_stats, aoi = FALSE),
  "mask and weights" = list(x = r, zones = zz, id = "farm", stats = c("mean", "sd", "coverage", "mask_fraction", "quantiles"), mask = mk, weights = wt),
  "sample sd, probs, min thresholds" = list(x = r, zones = zz, id = "farm", stats = c("mean", "sd", "cv", "quantiles"), sd_type = "sample", probs = c(.05, .5, .95), min_coverage = .9, min_cell_fraction = .5, min_mask_area_ha = 1),
  "class_share from breaks" = list(x = r[[2:4]], zones = zz, id = "farm", stats = c("mean", "class_share"), breaks = c(2, 4, 6), labels = c("a", "b", "c", "d"), aoi = FALSE),
  "class_share integer layer" = list(x = cl, zones = zz, id = "farm", stats = "class_share"),
  "single statistic count" = list(x = r, zones = z, id = "farm", stats = "count", aoi = FALSE),
  "lon/lat raster" = list(x = ll, zones = zz, id = c("scheme", "farm"), stats = c("mean", "area_ha", "coverage", "sum_volume")),
  "layers subset, season, no normalise" = list(x = r, zones = z, id = "farm", layers = c(3, 7), season = "2024", normalize_id = FALSE),
  "wide format" = list(x = r[[1:2]], zones = z, id = "farm", stats = c("mean", "coverage"), format = "wide", aoi = FALSE),
  "class_share error" = list(x = r[[2]], zones = z, id = "farm", stats = "class_share")
)
for (mb in c(NA, 0.02)) {
  options(Rwapor.memory_budget_mb = if (is.na(mb)) NULL else mb)
  cat(sprintf("\nmemory budget %s MB\n", if (is.na(mb)) "default" else format(mb)))
  for (nm in names(cases)) {
    a <- run(ref, cases[[nm]]); b <- run(wapor_zonal_stats, cases[[nm]])
    cat(sprintf("  %-42s rows %5s | identical table: %-5s | same warnings (%d): %s\n", nm, if (is.data.frame(a$v)) nrow(a$v) else "-",
                identical(a$v, b$v), length(a$w), identical(a$w, b$w)))
    if (is.character(a$v)) cat("      both:", substr(a$v, 1, 150), "\n")
    if (!identical(a$v, b$v)) { print(all.equal(a$v, b$v)); if (is.character(b$v)) print(b$v) }
    if (!identical(a$w, b$w)) { print(a$w); print(b$w) }
  }
}

