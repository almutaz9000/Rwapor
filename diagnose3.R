setwd("c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor")
devtools::load_all(".", quiet = TRUE)
library(sf)

farms_sf <- sf::st_read("Pivots_savola2.geojson", quiet = TRUE)
farms_sf[["farm_id"]] <- paste0("farm_", seq_len(nrow(farms_sf)))
small <- farms_sf[1:2, ]

# Full traceback
options(warn = 1)

withCallingHandlers(
  tryCatch(
    Rwapor::wapor_ts(
      region          = small,
      variable        = "L1-PCP-D",
      period          = c("2020-01-01", "2020-01-31"),
      identifier      = "farm_id",
      unit_conversion = "dekad",
      batching        = FALSE
    ),
    error = function(e) {
      cat("CAUGHT ERROR:", conditionMessage(e), "\n")
    }
  ),
  error = function(e) {
    cat("HANDLER ERROR:", conditionMessage(e), "\n")
    cat("Call stack:\n")
    calls <- sys.calls()
    for (i in seq_along(calls)) {
      cat(sprintf("  [%d] %s\n", i, deparse(calls[[i]])[1]))
    }
  }
)

cat("\nTraceback:\n")
traceback()
