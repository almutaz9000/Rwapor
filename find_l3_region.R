setwd("c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor")
devtools::load_all(".", quiet = TRUE)
library(sf)

farms_sf <- sf::st_read("Pivots_savola2.geojson", quiet = TRUE)
farms_sf[["farm_id"]] <- paste0("farm_", seq_len(nrow(farms_sf)))
cat("BBox:", paste(round(as.numeric(sf::st_bbox(farms_sf)), 4), collapse = " "), "\n")

# List L3 regions
cat("\nAvailable L3 regions:\n")
regs <- Rwapor::L3_REGIONS
for (code in names(regs)) {
  r <- regs[[code]]
  cat(sprintf("  %s: %s - %s\n", code, r$country, r$name))
}

# Try to auto-detect
cat("\nAuto-detecting L3 region...\n")
reg_info <- Rwapor:::wapor_parse_region(farms_sf)
period <- c("2022-01-01", "2022-03-31")
codes <- tryCatch(
  Rwapor:::wapor_guess_region("L3-AETI-D", reg_info, period),
  error = function(e) { cat("Error:", e$message, "\n"); NULL }
)
cat("Detected L3 codes:", paste(codes, collapse = ", "), "\n")
