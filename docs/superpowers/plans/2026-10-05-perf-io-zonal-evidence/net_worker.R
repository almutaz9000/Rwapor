# One benchmark run in a fresh process. Args: config method level npoly out_csv
# GDAL settings are set as environment variables BEFORE terra/GDAL load.
a <- commandArgs(trailingOnly = TRUE)
config <- a[1]; method <- a[2]; level <- a[3]; npoly <- as.integer(a[4]); out_csv <- a[5]

Sys.setenv(RWAPOR_AUTO_CONFIG = "false", CPL_CURL_VERBOSE = "YES")
# Auto-config is off so each run controls its GDAL settings; keep the package's PROJ fix,
# otherwise every raster open costs about 0.35 s on this machine (PostGIS PROJ on the path).
pj <- system.file("proj", package = "sf"); Sys.setenv(PROJ_LIB = pj, PROJ_DATA = pj)
rwapor_now <- c(CPL_VSIL_CURL_CHUNK_SIZE = "10485760", VSI_CACHE = "TRUE", VSI_CACHE_SIZE = "100000000",
                GDAL_CACHEMAX = "512", GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR", GDAL_HTTP_MAX_RETRY = "3",
                GDAL_HTTP_RETRY_DELAY = "2", GDAL_HTTP_TIMEOUT = "60", GDAL_HTTP_MULTIPLEX = "YES",
                GDAL_HTTP_VERSION = "2")
extra <- c(CPL_VSIL_CURL_ALLOWED_EXTENSIONS = ".tif,.tiff", GDAL_HTTP_MERGE_CONSECUTIVE_RANGES = "YES")
set <- switch(config,
  gdal_default = character(0),
  rwapor_now   = rwapor_now,
  ai_suggested = c(rwapor_now, extra),
  # GDAL's own 16 KB chunk (it grows reads itself), sidecar probes and HEAD removed
  tuned_a = c(rwapor_now[setdiff(names(rwapor_now), "CPL_VSIL_CURL_CHUNK_SIZE")], extra,
              CPL_VSIL_CURL_USE_HEAD = "NO"),
  # one change at a time, to see which setting matters
  no_chunk    = rwapor_now[setdiff(names(rwapor_now), "CPL_VSIL_CURL_CHUNK_SIZE")],
  no_chunk_ext = c(rwapor_now[setdiff(names(rwapor_now), "CPL_VSIL_CURL_CHUNK_SIZE")], extra),
  # 1 MB chunk with a region cache large enough to hold 128 chunks
  tuned_b = c(replace(rwapor_now, "CPL_VSIL_CURL_CHUNK_SIZE", "1048576"), extra,
              CPL_VSIL_CURL_USE_HEAD = "NO", CPL_VSIL_CURL_CACHE_SIZE = "134217728"),
  # keep the 10 MB chunk but give the region cache room for 25 chunks
  tuned_c = c(rwapor_now, extra, CPL_VSIL_CURL_USE_HEAD = "NO", CPL_VSIL_CURL_CACHE_SIZE = "268435456"),
  stop("unknown config"))
if (length(set)) do.call(Sys.setenv, as.list(set))

suppressMessages(pkgload::load_all(".", quiet = TRUE))
options(Rwapor.verbose = FALSE)

var <- sprintf("%s-AETI-D", level)
urls <- wapor_generate_urls(var, l3_region = if (level == "L3") "JVA" else NULL,
                            period = c("2023-01-01", "2023-12-31"))
urls <- Rwapor:::.wapor_resolve_remote_sources(urls)

# npoly squares of 300 m on a regular grid inside the JVA L3 extent (UTM 36N).
set.seed(1)
nx <- ceiling(sqrt(npoly / 4)); ny <- ceiling(npoly / nx)
gx <- seq(740500, 749000, length.out = nx); gy <- seq(3583000, 3618000, length.out = ny)
g <- expand.grid(x = gx, y = gy)[seq_len(npoly), ]
sq <- lapply(seq_len(npoly), function(i) sf::st_polygon(list(cbind(
  g$x[i] + c(0, 300, 300, 0, 0), g$y[i] + c(0, 0, 300, 300, 0)))))
v <- sf::st_sf(id = seq_len(npoly), geometry = sf::st_sfc(sq, crs = 32636))
if (npoly == 1L) {  # one scheme-size polygon: 8 km x 30 km
  v <- sf::st_sf(id = 1L, geometry = sf::st_sfc(sf::st_polygon(list(cbind(
    c(741000, 749000, 749000, 741000, 741000), c(3585000, 3585000, 3615000, 3615000, 3585000)))), crs = 32636))
}
reg_info <- list(type = "vector", value = sf::st_transform(v, 4326))

t0 <- proc.time()[["elapsed"]]
io_plan <- Rwapor:::.wapor_io_plan(urls, reg_info, processing = "auto", n_targets = 3L)
res <- Rwapor:::.wapor_with_gdal_chunk(io_plan$gdal_chunk_bytes, {
  r <- terra::rast(urls)
  t_open <- proc.time()[["elapsed"]] - t0
  vv <- sf::st_transform(v, terra::crs(r))
  if (method == "crop_first") {
    e <- terra::ext(terra::vect(vv))
    r <- terra::crop(r, e, snap = "out") * 1   # one windowed read per layer into memory
  }
  names(r) <- paste0("L", seq_len(terra::nlyr(r)))
  exactextractr::exact_extract(r, vv, c("mean", "min", "max"), progress = FALSE)
})
t_all <- proc.time()[["elapsed"]] - t0
chk <- sum(as.matrix(res[, grep("^mean", names(res))]), na.rm = TRUE)
row <- data.frame(config = config, method = method, level = level, npoly = npoly,
                  planned_chunk = io_plan$gdal_chunk_bytes, batch = io_plan$batch_size,
                  t_open = round(t_open, 2), t_total = round(t_all, 2), checksum = signif(chk, 10))
write.table(row, out_csv, sep = ",", row.names = FALSE, col.names = !file.exists(out_csv), append = TRUE)
