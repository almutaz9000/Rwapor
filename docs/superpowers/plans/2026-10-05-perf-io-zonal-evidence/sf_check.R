suppressMessages(pkgload::load_all(".", quiet = TRUE))
r <- terra::rast(nrows = 60, ncols = 60, xmin = 5e5, xmax = 5e5 + 1200, ymin = 35e5, ymax = 35e5 + 1200, crs = "EPSG:32636")
terra::values(r) <- seq_len(3600) / 100; names(r) <- "v"
z <- sf::st_sf(farm = sprintf("F%02d", 1:4), geometry = sf::st_sfc(lapply(0:3, function(i) sf::st_polygon(list(cbind(
  5e5 + 100 + i * 280 + c(0, 200, 200, 0, 0), 35e5 + 100 + c(0, 0, 200, 200, 0))))), crs = 32636))
for (st in list("mean", c("mean", "area_ha"))) {
  s <- suppressWarnings(wapor_zonal_stats(r, z, id = "farm", dissolve = FALSE, aoi = FALSE, stats = st, format = "sf"))
  own <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(z)))[match(s$zone_id, z$farm), "X"]
  got <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(s)))[, "X"]
  cat(sprintf("stats = %-14s rows %d, rows carrying their own zone geometry: %d\n", paste(st, collapse = "+"), nrow(s), sum(abs(own - got) < 1)))
}
w <- tryCatch(suppressWarnings(wapor_zonal_stats(r, z, id = "farm", dissolve = FALSE, aoi = FALSE, stats = c("mean", "coverage"), format = "wide")), error = function(e) conditionMessage(e))
print(w)
