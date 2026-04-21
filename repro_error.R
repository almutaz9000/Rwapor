# Reproduce L3-AETI-D Error
library(devtools)
load_all(".")

db_path <- "C:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Desktop/wapor_data/Savola/Savola4_test.duckdb"
if (file.exists(db_path)) unlink(db_path)

geo_path <- "C:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/my-research-agent/projects/Savola/data/raw/vectors/Pivots_savola2.geojson"
farms_sf <- sf::st_read(geo_path)
if (!"farm_id" %in% names(farms_sf)) farms_sf$farm_id <- paste0("farm_", seq_len(nrow(farms_sf)))

con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)
wapor_init_monitoring_db(con)

# Try fetching L3-AETI-D for a short period
var <- "L3-AETI-D"
period <- c("2018-01-01", "2018-06-30")

message("Fetching TS for ", var)
ts_df <- wapor_ts(
  region          = farms_sf,
  variable        = var,
  period          = period,
  identifier      = "farm_id",
  unit_conversion = "dekad",
  l3_region       = "AWA",
  batching        = TRUE
)

message("Rows fetched: ", nrow(ts_df))

insert_df <- data.frame(
  farm_id     = as.character(ts_df$farm_id),
  crop_type   = NA_character_,
  sowing_date = as.Date(period[1]),
  variable    = var,
  start_date  = as.Date(ts_df$start_date),
  end_date    = as.Date(ts_df$end_date),
  mean_val    = as.numeric(ts_df$mean),
  min_val     = if ("min" %in% names(ts_df)) as.numeric(ts_df$min) else NA_real_,
  max_val     = if ("max" %in% names(ts_df)) as.numeric(ts_df$max) else NA_real_,
  units       = attr(ts_df, "units") %||% NA_character_,
  stringsAsFactors = FALSE
)

message("Attempting dbWriteTable...")
tryCatch({
  duckdb::dbWriteTable(con, "farm_timeseries", insert_df, append = TRUE)
  message("Success!")
}, error = function(e) {
  message("Error caught: ", e$message)
  print(e)
})

DBI::dbDisconnect(con, shutdown = TRUE)
