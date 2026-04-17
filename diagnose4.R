setwd("c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor")
devtools::load_all(".", quiet = TRUE)
library(sf)

farms_sf <- sf::st_read("Pivots_savola2.geojson", quiet = TRUE)
farms_sf[["farm_id"]] <- paste0("farm_", seq_len(nrow(farms_sf)))
small <- farms_sf[1:2, ]

# Use rlang to capture the full call stack
if (requireNamespace("rlang", quietly = TRUE)) {
  rlang::with_abort(
    Rwapor::wapor_ts(
      region          = small,
      variable        = "L1-PCP-D",
      period          = c("2020-01-01", "2020-01-31"),
      identifier      = "farm_id",
      unit_conversion = "dekad",
      batching        = FALSE
    )
  )
} else {
  # Fallback: options(error = ...) to get traceback
  options(error = function() {
    cat("Error traceback:\n")
    traceback(3)
  })
  Rwapor::wapor_ts(
    region          = small,
    variable        = "L1-PCP-D",
    period          = c("2020-01-01", "2020-01-31"),
    identifier      = "farm_id",
    unit_conversion = "dekad",
    batching        = FALSE
  )
}
