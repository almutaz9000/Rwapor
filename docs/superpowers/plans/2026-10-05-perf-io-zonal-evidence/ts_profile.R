suppressMessages(pkgload::load_all(".", quiet = TRUE))
n <- 150L; nx <- ceiling(sqrt(n / 4)); ny <- ceiling(n / nx)
g <- expand.grid(x = seq(740500, 749000, length.out = nx), y = seq(3583000, 3618000, length.out = ny))[seq_len(n), ]
farms <- sf::st_transform(sf::st_sf(id = seq_len(n), geometry = sf::st_sfc(lapply(seq_len(n), function(i) sf::st_polygon(list(cbind(
  g$x[i] + c(0, 300, 300, 0, 0), g$y[i] + c(0, 0, 300, 300, 0))))), crs = 32636)), 4326)
f <- tempfile(fileext = ".gpkg"); sf::st_write(farms, f, quiet = TRUE)
t0 <- Sys.time(); stamp <- function(m) message(sprintf("[%5.1f s] %s", as.numeric(Sys.time() - t0, units = "secs"), conditionMessage(m)), appendLF = FALSE)
pf <- tempfile(); Rprof(pf, interval = 0.05)
df <- withCallingHandlers(
  wapor_ts(region = f, variable = "L3-AETI-D", period = c("2023-01-01", "2023-12-31"), identifier = "id", l3_region = "JVA"),
  message = function(m) { stamp(m); invokeRestart("muffleMessage") })
Rprof(NULL)
cat(sprintf("total %.1f s, rows %d\n", as.numeric(Sys.time() - t0, units = "secs"), nrow(df)))
s <- summaryRprof(pf)$by.total
keep <- grep("wapor_|exact_extract|rast|req_perform|\\.wapor|retry|global|crop", rownames(s))
print(utils::head(s[keep, c("total.time", "total.pct")], 28))
