# Test existing DuckDB structure and data
library(duckdb)
library(DBI)
library(terra)

db_path <- "C:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor/inst/shiny/monitoring.duckdb"

if (!file.exists(db_path)) {
  cat("Database not found at:", db_path, "\n")
  quit()
}

cat("=== Inspecting DuckDB Structure ===\n\n")

con <- duckdb::dbConnect(duckdb::duckdb(), db_path)

# List tables
tables <- DBI::dbListTables(con)
cat("Tables:\n")
print(tables)
cat("\n")

# Check each table
for (tbl in tables) {
  cat("--- Table:", tbl, "---\n")
  
  # Get row count
  count <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) as n FROM ", tbl))
  cat("  Rows:", count$n, "\n")
  
  # Get schema
  schema <- DBI::dbGetQuery(con, paste0("DESCRIBE ", tbl))
  cat("  Schema:\n")
  print(schema)
  cat("\n")
  
  # Get sample data
  if (count$n > 0) {
    sample <- DBI::dbGetQuery(con, paste0("SELECT * FROM ", tbl, " LIMIT 3"))
    cat("  Sample data:\n")
    print(sample)
    cat("\n")
  }
}

# Check raster availability
cat("=== Raster BLOB Analysis ===\n")
raster_info <- DBI::dbGetQuery(con, "
  SELECT 
    farm_id,
    variable,
    COUNT(*) as n_dates,
    MIN(date_key) as first_date,
    MAX(date_key) as last_date,
    AVG(OCTET_LENGTH(raster_blob)) as avg_blob_size
  FROM farm_rasters
  GROUP BY farm_id, variable
  ORDER BY farm_id, variable
")
print(raster_info)

# Check farm extent info
cat("\n=== Farm Extent Analysis ===\n")
farms <- DBI::dbGetQuery(con, "
  SELECT DISTINCT farm_id
  FROM farm_timeseries
  ORDER BY farm_id
")
cat("Unique farms:", nrow(farms), "\n")
print(head(farms, 10))

# Try to extract and plot one raster to verify structure
cat("\n=== Testing Raster Extraction ===\n")
raster_sample <- DBI::dbGetQuery(con, "
  SELECT farm_id, variable, date_key, raster_blob
  FROM farm_rasters
  LIMIT 1
")

if (nrow(raster_sample) > 0) {
  cat("Testing raster from farm:", raster_sample$farm_id, "\n")
  cat("Variable:", raster_sample$variable, "\n")
  cat("Date:", as.character(raster_sample$date_key), "\n")
  
  temp_file <- tempfile(fileext = ".tif")
  writeBin(raster_sample$raster_blob[[1]], temp_file)
  
  r <- terra::rast(temp_file)
  cat("Raster dimensions:", nrow(r), "x", ncol(r), "\n")
  cat("Raster values range:", min(terra::values(r), na.rm=TRUE), "-", 
      max(terra::values(r), na.rm=TRUE), "\n")
  cat("Raster extent:", as.vector(terra::ext(r)), "\n")
  cat("Raster CRS:", terra::crs(r), "\n")
  
  unlink(temp_file)
}

DBI::dbDisconnect(con, shutdown = TRUE)
cat("\n=== Analysis Complete ===\n")
