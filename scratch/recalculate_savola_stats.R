# recalculate_savola_stats.R
# Script to recalculate zonal statistics with a 5% threshold for Savola pivots

message("[", Sys.time(), "] Starting Recalculation (5% Threshold)...")

# 1. Load Package and Dependencies
devtools::load_all(".")
library(sf)
library(DBI)
library(duckdb)

# 2. Configuration
db_path <- "C:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/WP_Analysis/Savola/Savola.duckdb"
vector_path <- "C:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/WP_Analysis/Savola/Vectors/Pivots_savola2.geojson"
threshold <- 5  # Percentile to discard (bottom 5%)

# 3. Load Geometry
pivots <- st_read(vector_path, quiet = TRUE)
if (!"farm_id" %in% names(pivots)) {
  pivots$farm_id <- pivots$Name
}

# 4. Open Database Connection
con <- dbConnect(duckdb::duckdb(), dbdir = db_path)

# 5. Run Seasonal Adaptive Recalculation
# We define seasons (e.g., Summer/Winter or simply Year-by-Year)
# For Savola, we will apply a mask based on the total AETI sum of each year.
seasons <- list(
  "2018" = c("2018-01-01", "2018-12-31"),
  "2019" = c("2019-01-01", "2019-12-31"),
  "2020" = c("2020-01-01", "2020-12-31"),
  "2021" = c("2021-01-01", "2021-12-31"),
  "2022" = c("2022-01-01", "2022-12-31"),
  "2023" = c("2023-01-01", "2023-12-31"),
  "2024" = c("2024-01-01", "2024-12-31")
)

message("Processing ", nrow(pivots), " farms with Seasonal Adaptive Masking")

for (i in seq_len(nrow(pivots))) {
  fid <- pivots$farm_id[i]
  poly <- pivots[i, ]
  
  message("\n--- Pivot: ", fid, " ---")
  
  for (s_name in names(seasons)) {
    s_dates <- seasons[[s_name]]
    
    tryCatch({
      wapor_apply_seasonal_mask_recalc(
        con = con,
        farm_id = fid,
        polygon = poly,
        start_date = s_dates[1],
        end_date = s_dates[2],
        mask_variable = "L3-AETI-D", # Use AETI sum to find cultivated area
        percentile_threshold = 40     # Discard pixels in the bottom 40% of seasonal sum
      )
    }, error = function(e) {
      message("  [SKIP] Season ", s_name, " failed: ", e$message)
    })
  }
}

# 6. Cleanup
dbDisconnect(con, shutdown = TRUE)
message("\n[", Sys.time(), "] Recalculation completed successfully.")
