lib <- file.path(Sys.getenv("USERPROFILE"), "R", "win-library", "4.5")
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages({ library(terra); library(gdalcubes) })
set.seed(42)
root <- file.path(tempdir(), "rwapor-gdalcubes-benchmark")
dir.create(root, recursive = TRUE, showWarnings = FALSE)
ny <- 256L; nx <- 256L; nt <- 6L
template <- terra::rast(nrows = ny, ncols = nx, xmin = 0, xmax = nx,
                         ymin = 0, ymax = ny, crs = "EPSG:3857")
files <- character(nt)
dates <- as.Date("2023-01-01") + seq(0, by = 10, length.out = nt)
for (i in seq_len(nt)) {
  r <- terra::setValues(template, rep(i, terra::ncell(template)))
  files[i] <- file.path(root, sprintf("WAPOR-3.L1-AETI-D.%s.tif", dates[i]))
  terra::writeRaster(
    r, files[i], overwrite = TRUE, datatype = "FLT4S",
    gdal = c("TILED=YES", "BLOCKXSIZE=256", "BLOCKYSIZE=256", "COMPRESS=LZW")
  )
}
aoi <- terra::ext(32, 224, 32, 224)
bench <- function(expr) {
  gc()
  t <- system.time(ans <- force(expr))
  list(value = ans, elapsed = unname(t[["elapsed"]]),
       user = unname(t[["user.self"]]), sys = unname(t[["sys.self"]]))
}
terra_run <- bench({
  x <- terra::rast(files)
  y <- terra::crop(x, aoi)
  terra::app(y, mean, na.rm = TRUE)
})
gc_collection <- gdalcubes::create_image_collection(
  files, date_time = dates, band_names = "aeti", quiet = TRUE
)
gc_view <- gdalcubes::cube_view(
  extent = list(left = 32, right = 224, bottom = 32, top = 224,
                t0 = "2023-01-01", t1 = "2023-03-01"),
  srs = "EPSG:3857", nx = 192L, ny = 192L, dt = "P10D",
  aggregation = "mean", resampling = "near"
)
gc_proxy <- gdalcubes::raster_cube(
  gc_collection, gc_view, chunking = c(1L, 128L, 128L), incomplete_ok = FALSE
)
gdalcubes_run <- bench({
  x <- gdalcubes::reduce_time(gc_proxy, "mean(aeti)")
  gdalcubes::as_array(x)
})
terra_values <- terra::values(terra_run$value)
gc_values <- as.numeric(gdalcubes_run$value)
cat(jsonlite::toJSON(list(
  r_version = R.version.string,
  terra = as.character(packageVersion("terra")),
  gdalcubes = as.character(packageVersion("gdalcubes")),
  gdal_terra = as.character(terra::gdal()),
  fixture = list(nrow = ny, ncol = nx, layers = nt,
                 subset_nrow = 192L, subset_ncol = 192L),
  terra = terra_run[c("elapsed", "user", "sys")],
  gdalcubes = gdalcubes_run[c("elapsed", "user", "sys")],
  terra_cells = length(terra_values),
  gdalcubes_cells = length(gc_values),
  terra_mean = mean(terra_values, na.rm = TRUE),
  gdalcubes_mean = mean(gc_values, na.rm = TRUE),
  max_abs_difference = max(abs(terra_values - gc_values), na.rm = TRUE),
  collection_files = length(files)
), auto_unbox = TRUE, pretty = TRUE), "\n")
