# perf-c: the ti-06 case. Citrus seasonal analysis (JVA, 36 dekads, AETI/T at L3, RET/PCP at L1),
# streamed from the API or read from the files saved by the training notebook.
a <- commandArgs(trailingOnly = TRUE); source_mode <- a[1]; settings <- a[2]
if (settings == "old") { Sys.setenv(CPL_VSIL_CURL_CHUNK_SIZE = "10485760"); options(Rwapor.remote_extension_filter = FALSE) }
suppressMessages(pkgload::load_all(".", quiet = TRUE)); options(Rwapor.verbose = FALSE)
period <- c("2024-03-01", "2025-02-28"); poly_path <- "training/data/citrus/Citrus_NJV.geojson"
data_dir <- "training/wapor_data/citrus/dekadal"
tmpl <- terra::rast(list.files(file.path(data_dir, "L3-AETI-D"), "[.]tif$", full.names = TRUE)[1])
poly <- sf::st_read(poly_path, quiet = TRUE)
mask <- terra::rasterize(terra::vect(sf::st_transform(poly, terra::crs(tmpl))), tmpl, field = 1, background = NA)
names(mask) <- "crop_mask"
params <- wapor_create_crop_params(class_value = 1L, crop_name = "Citrus", kc_ini = 0.70, kc_mid = 0.65, kc_end = 0.70,
                                   l_ini_days = 60L, l_mid_days = 120L, l_late_days = 95L, max_height_m = 4.0,
                                   region = "Mediterranean")
config <- list(period = period, aeti_var = "L3-AETI-D", t_var = "L3-T-D", ret_var = "L1-RET-D", precip_var = "L1-PCP-D",
               data_source = source_mode, folder = data_dir, use_crop_mask = TRUE, area_weighted = TRUE,
               keep_intermediates = FALSE, l3_code = "JVA",
               indicators = c("agg_aeti", "agg_t", "agg_ret", "agg_pcp", "agg_peff", "etc", "adequacy_etc",
                              "adequacy_p95", "beneficial_fraction", "green_water", "blue_water"))
t0 <- proc.time()[["elapsed"]]
res <- suppressWarnings(wapor_run_seasonal_analysis(config = config, crop_params = params, rasters = list(crop_mask = mask),
                                                    aoi_region = poly_path))
s <- proc.time()[["elapsed"]] - t0
m <- function(x) if (inherits(x, "SpatRaster")) terra::global(x, "mean", na.rm = TRUE)[1, 1] else NA_real_
num <- function(n) { x <- res[[n]]; if (inherits(x, "SpatRaster")) m(x) else if (is.numeric(x) && length(x) == 1) x else NA_real_ }
cat("fields:", paste(names(res), collapse = " "), "\n")
cat(sprintf("VALUES aeti=%.2f etc=%.2f bf=%.3f\n", num("seasonal_aeti_mean") , num("seasonal_etc_mean"), num("beneficial_fraction_mean")))
cat(sprintf("RESULT source=%s settings=%s cells=%d seconds=%.1f AETI=%.2f ETc=%.2f adequacy=%.3f\n", source_mode, settings,
            sum(!is.na(terra::values(mask))), s, m(res$seasonal_aeti), m(res$seasonal_etc), m(res$adequacy_etc)))


