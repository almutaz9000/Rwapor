setwd("c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor")
library(duckdb); library(DBI)
con <- duckdb::dbConnect(duckdb::duckdb(), dbdir="inst/shiny/monitoring_test_savola.duckdb", read_only=TRUE)
cat("=== farm_timeseries ===\n")
print(DBI::dbGetQuery(con, "
  SELECT variable, units, COUNT(*) n_rows,
         COUNT(DISTINCT farm_id) n_farms,
         MIN(start_date) from_d, MAX(start_date) to_d,
         ROUND(AVG(mean_val),4) avg_mean
  FROM farm_timeseries GROUP BY variable, units ORDER BY variable"))
cat("\n=== farm_rasters ===\n")
print(DBI::dbGetQuery(con, "
  SELECT variable, units, ROUND(resolution_x,6) res_x, ROUND(resolution_y,6) res_y,
         crs_epsg, COUNT(*) n_rasters,
         COUNT(DISTINCT farm_id) n_farms,
         MIN(date_key) from_d, MAX(date_key) to_d
  FROM farm_rasters GROUP BY variable, units, resolution_x, resolution_y, crs_epsg ORDER BY variable"))
DBI::dbDisconnect(con, shutdown=TRUE)
