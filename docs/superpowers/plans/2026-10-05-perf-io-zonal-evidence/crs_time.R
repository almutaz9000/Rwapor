a <- commandArgs(trailingOnly = TRUE); mode <- a[1]; mc <- as.numeric(a[2]); level <- a[3]
suppressMessages(pkgload::load_all(".", quiet = TRUE)); options(Rwapor.verbose = FALSE)
ns <- asNamespace("Rwapor")
n <- 150L; nx <- ceiling(sqrt(n / 4)); ny <- ceiling(n / nx)
g <- expand.grid(x = seq(740507, 749007, length.out = nx), y = seq(3583007, 3618007, length.out = ny))[seq_len(n), ]
utm <- sf::st_sf(id = seq_len(n), geometry = sf::st_sfc(lapply(seq_len(n), function(i) sf::st_polygon(list(cbind(
  g$x[i] + c(0, 300, 300, 0, 0), g$y[i] + c(0, 0, 300, 300, 0))))), crs = 32636))
ll <- sf::st_transform(utm, 4326)
urls <- ns$.wapor_resolve_remote_sources(wapor_generate_urls(sprintf("%s-AETI-D", level), l3_region = if (level == "L3") "JVA" else NULL, period = c("2023-01-01", "2023-12-31")))
t0 <- proc.time()[["elapsed"]]
res <- ns$.wapor_with_remote_io({
  r <- terra::rast(urls); names(r) <- paste0("L", 1:36); t1 <- proc.time()[["elapsed"]]
  z <- if (mode == "lonlat") ll else sf::st_transform(ll, terra::crs(r))
  suppressWarnings(exactextractr::exact_extract(r, z, c("mean", "min", "max"), progress = FALSE, max_cells_in_memory = mc))
})
cat(sprintf("%s %-10s max_cells %-6g: open %5.1f s, extract %5.1f s, checksum %s\n", level, mode, mc, t1 - t0,
            proc.time()[["elapsed"]] - t1, format(sum(as.matrix(res[, grep("^mean", names(res))]), na.rm = TRUE), digits = 10)))
