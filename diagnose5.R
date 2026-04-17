setwd("c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor")
devtools::load_all(".", quiet = TRUE)
library(sf)

farms_sf <- sf::st_read("Pivots_savola2.geojson", quiet = TRUE)
farms_sf[["farm_id"]] <- paste0("farm_", seq_len(nrow(farms_sf)))
small <- farms_sf[1:2, ]

options(error = function() {
  cat("\n=== ERROR TRACEBACK ===\n")
  traceback(5)
  cat("======================\n")
})

# Run without tryCatch so options(error=) fires
Rwapor::wapor_ts(
  region          = small,
  variable        = "L1-PCP-D",
  period          = c("2020-01-01", "2020-01-31"),
  identifier      = "farm_id",
  unit_conversion = "dekad",
  batching        = FALSE
)
