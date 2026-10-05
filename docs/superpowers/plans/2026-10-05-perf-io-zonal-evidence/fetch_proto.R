# Prototype: small remote files (WaPOR L3) fetched whole and in parallel, then read locally.
# Arg 1: number of years (36 dekads each). Same polygons and statistic as net_worker.R.
a <- commandArgs(trailingOnly = TRUE); years <- if (length(a)) as.integer(a[1]) else 1L
Sys.setenv(RWAPOR_AUTO_CONFIG = "true")
suppressMessages(pkgload::load_all(".", quiet = TRUE)); options(Rwapor.verbose = FALSE)
period <- c(sprintf("%d-01-01", 2024 - years), "2023-12-31")
urls <- sub("^/vsicurl/", "", wapor_generate_urls("L3-AETI-D", l3_region = "JVA", period = period))
cat("files:", length(urls), "\n")

npoly <- 150L; nx <- ceiling(sqrt(npoly / 4)); ny <- ceiling(npoly / nx)
g <- expand.grid(x = seq(740500, 749000, length.out = nx), y = seq(3583000, 3618000, length.out = ny))[seq_len(npoly), ]
v <- sf::st_sf(id = seq_len(npoly), geometry = sf::st_sfc(lapply(seq_len(npoly), function(i) sf::st_polygon(list(cbind(
  g$x[i] + c(0, 300, 300, 0, 0), g$y[i] + c(0, 0, 300, 300, 0))))), crs = 32636))

t0 <- proc.time()[["elapsed"]]
# 1. sizes: one parallel round of HEAD requests
reqs <- lapply(urls, function(u) httr2::req_method(httr2::request(u), "HEAD"))
heads <- httr2::req_perform_parallel(reqs, on_error = "continue", progress = FALSE)
size <- vapply(heads, function(h) if (inherits(h, "httr2_response")) as.numeric(httr2::resp_header(h, "content-length")) else NA_real_, numeric(1))
t_head <- proc.time()[["elapsed"]] - t0
cat(sprintf("HEAD x%d in parallel: %.1f s; sizes %.2f to %.2f MB, total %.1f MB\n",
            length(urls), t_head, min(size) / 1e6, max(size) / 1e6, sum(size) / 1e6))
# 2. whole files, parallel, atomic publish into a cache folder
dir <- file.path(tempdir(), "l3cache"); dir.create(dir, showWarnings = FALSE)
dest <- file.path(dir, basename(urls))
res <- curl::multi_download(urls, paste0(dest, ".part"), progress = FALSE)
ok <- res$success & res$status_code == 200 & file.size(paste0(dest, ".part")) == size
stopifnot(all(ok)); file.rename(paste0(dest, ".part"), dest)
t_dl <- proc.time()[["elapsed"]] - t0
# 3. local read, same extraction as the package
r <- terra::rast(dest); names(r) <- paste0("L", seq_len(terra::nlyr(r)))
ex <- exactextractr::exact_extract(r, sf::st_transform(v, terra::crs(r)), c("mean", "min", "max"), progress = FALSE)
t_all <- proc.time()[["elapsed"]] - t0
cat(sprintf("download done at %.1f s; total with extraction %.1f s; checksum %s\n", t_dl, t_all,
            format(signif(sum(as.matrix(ex[, grep("^mean", names(ex))]), na.rm = TRUE), 10), nsmall = 3)))
# 4. second run from the cache (no network)
t1 <- proc.time()[["elapsed"]]
r <- terra::rast(dest); names(r) <- paste0("L", seq_len(terra::nlyr(r)))
ex <- exactextractr::exact_extract(r, sf::st_transform(v, terra::crs(r)), c("mean", "min", "max"), progress = FALSE)
cat(sprintf("repeat from cache: %.1f s\n", proc.time()[["elapsed"]] - t1))
