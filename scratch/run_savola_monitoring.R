# run_savola_monitoring.R
# Script to run the monitoring pipeline for Savola project pivots

message("[", Sys.time(), "] Starting Savola Monitoring Sync...")

# 1. Load Package and Dependencies
devtools::load_all(".")
library(sf)
library(DBI)
library(duckdb)

# 2. Configuration
vector_path <- "C:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/WP_Analysis/Savola/Vectors/Pivots_savola2.geojson"
db_path <- "C:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/WP_Analysis/Savola/Savola.duckdb"
variables <- c("L1-RET-D", "L1-PCP-D", "L3-AETI-D", "L3-NPP-D", "L3-T-D")
start_date <- "2018-01-01"
end_date <- format(Sys.time(), "%Y-%m-%d")

# 3. Load Geometry
message("Loading AOI from: ", vector_path)
pivots <- st_read(vector_path, quiet = TRUE)
# Ensure farm_id exists (using 'Name' column)
if (!"farm_id" %in% names(pivots) && "Name" %in% names(pivots)) {
  pivots$farm_id <- pivots$Name
}

# 4. Open Database Connection
message("Connecting to DuckDB: ", db_path)
con <- dbConnect(duckdb::duckdb(), dbdir = db_path)

# 5. Run Monitoring
message("Processing variables: ", paste(variables, collapse = ", "))
message("Period: ", start_date, " to ", end_date)

tryCatch({
  wapor_run_monitoring(
    con = con,
    farms_sf = pivots,
    variables = variables,
    period = c(start_date, end_date),
    save_rasters = TRUE  # Saving rasters for enhanced analysis
  )
  message("\n[", Sys.time(), "] Monitoring sync completed successfully.")
}, error = function(e) {
  message("\n[", Sys.time(), "] ERROR during monitoring sync: ", e$message)
})

# 6. Cleanup
dbDisconnect(con, shutdown = TRUE)
