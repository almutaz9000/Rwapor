# Local files: how should a many-file stack be read for polygon extraction?
Sys.setenv(RWAPOR_AUTO_CONFIG = "false")
suppressMessages(pkgload::load_all(".", quiet = TRUE)); options(Rwapor.verbose = FALSE)
urls <- sub("^/vsicurl/", "", wapor_generate_urls("L3-AETI-D", l3_region = "JVA", period = c("2023-01-01", "2023-12-31")))
dir <- file.path(tempdir(), "l3cache"); dir.create(dir, showWarnings = FALSE)
dest <- file.path(dir, basename(urls)); invisible(curl::multi_download(urls, dest, progress = FALSE))
mkv <- function(npoly, size) {
  nx <- ceiling(sqrt(npoly / 4)); ny <- ceiling(npoly / nx)
  g <- expand.grid(x = seq(740500, 749000, length.out = nx), y = seq(3583000, 3618000, length.out = ny))[seq_len(npoly), ]
  sf::st_sf(id = seq_len(npoly), geometry = sf::st_sfc(lapply(seq_len(npoly), function(i) sf::st_polygon(list(cbind(
    g$x[i] + c(0, size, size, 0, 0), g$y[i] + c(0, 0, size, size, 0))))), crs = 32636))
}
tm <- function(e) { t0 <- proc.time()[["elapsed"]]; v <- force(e); list(s = round(proc.time()[["elapsed"]] - t0, 2), v = v) }
ops <- c("mean", "min", "max")
chk <- function(x) signif(sum(as.matrix(x[, grep("^mean", names(x))]), na.rm = TRUE), 10)
for (np in c(20L, 150L, 600L)) {
  v <- mkv(np, 300)
  a <- tm({ r <- terra::rast(dest); names(r) <- paste0("L", 1:36); exactextractr::exact_extract(r, v, ops, progress = FALSE) })
  b <- tm({ r <- terra::rast(dest); r <- terra::crop(r, terra::ext(terra::vect(v)), snap = "out") * 1
            names(r) <- paste0("L", 1:36); exactextractr::exact_extract(r, v, ops, progress = FALSE) })
  c3 <- tm({ vf <- tempfile(fileext = ".vrt"); r <- terra::vrt(dest, vf, options = "-separate", overwrite = TRUE)
             names(r) <- paste0("L", 1:36); exactextractr::exact_extract(r, v, ops, progress = FALSE) })
  d <- tm({ r <- terra::rast(dest); names(r) <- paste0("L", 1:36)
            exactextractr::exact_extract(r, v, ops, progress = FALSE, max_cells_in_memory = 1e9) })
  cat(sprintf("%3d polygons x 36 local files: direct %5.2f s | crop into memory first %5.2f s | one VRT %5.2f s | direct, big max_cells %5.2f s | same result: %s\n",
              np, a$s, b$s, c3$s, d$s, isTRUE(all.equal(chk(a$v), chk(b$v))) && isTRUE(all.equal(chk(a$v), chk(c3$v)))))
}
# sf output of wapor_zonal_stats with two statistics: does each row carry its own zone's geometry?
r1 <- terra::rast(dest[1]); z <- mkv(6L, 300); z$farm <- sprintf("F%02d", 1:6)
s <- suppressWarnings(wapor_zonal_stats(r1, z, id = "farm", dissolve = FALSE, aoi = FALSE, stats = c("mean", "area_ha"), format = "sf"))
cz <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(z)))[match(s$zone_id, z$farm), ]
cs <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(s)))
cat("format = 'sf', 2 stats: rows", nrow(s), "| rows whose geometry is their own zone:", sum(rowSums(abs(cz - cs)) < 1), "\n")
