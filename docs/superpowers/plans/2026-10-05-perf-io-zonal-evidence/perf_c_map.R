# perf-c: the ti-07 case. wapor_map() of 36 Level 3 dekads for the citrus area (opening took 95 s on 2026-09-24).
a <- commandArgs(trailingOnly = TRUE); settings <- a[1]
if (settings == "old") { Sys.setenv(CPL_VSIL_CURL_CHUNK_SIZE = "10485760"); options(Rwapor.remote_extension_filter = FALSE) }
suppressMessages(pkgload::load_all(".", quiet = TRUE))
out <- tempfile("map"); t0 <- proc.time()[["elapsed"]]
p <- withCallingHandlers(
  wapor_map(region = "training/data/citrus/Citrus_NJV.geojson", variable = "L3-AETI-D", l3_region = "JVA",
            period = c("2024-03-01", "2025-02-28"), folder = out, separate_files = TRUE, mask = TRUE),
  message = function(m) { if (grepl("opened in", conditionMessage(m))) cat("OPEN", trimws(conditionMessage(m)), "\n"); invokeRestart("muffleMessage") })
cat(sprintf("RESULT settings=%s files=%d seconds=%.1f\n", settings, length(unlist(p)), proc.time()[["elapsed"]] - t0))
