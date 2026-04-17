setwd("c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor")
devtools::load_all(".", quiet = TRUE)
library(sf)

farms_sf <- sf::st_read("Pivots_savola2.geojson", quiet = TRUE)
farms_sf[["farm_id"]] <- paste0("farm_", seq_len(nrow(farms_sf)))

# Test with 1 farm, short period
small <- farms_sf[1, ]
cat("Testing wapor_ts with 1 farm and 2 months...\n")
result <- tryCatch(
  Rwapor::wapor_ts(
    region          = small,
    variable        = "L1-PCP-D",
    period          = c("2020-01-01", "2020-02-28"),
    identifier      = "farm_id",
    unit_conversion = "dekad",
    batching        = FALSE
  ),
  error = function(e) {
    cat("ERROR:", conditionMessage(e), "\n")
    traceback()
    NULL
  }
)
if (!is.null(result)) {
  cat("SUCCESS! Rows:", nrow(result), "\n")
  print(head(result))
}
