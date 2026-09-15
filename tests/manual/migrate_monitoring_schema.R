# Database Schema Migration for Enhanced Monitoring
# This script upgrades the monitoring.duckdb schema to support:
# - Enhanced statistics (std, percentiles)
# - Farm metadata (extents, areas)
# - Threshold tracking
# - Better querying capabilities

library(duckdb)
library(DBI)

migrate_monitoring_db <- function(db_path) {
  cat("=== Migrating Monitoring Database ===\n")
  cat("Database:", db_path, "\n\n")
  
  if (!file.exists(db_path)) {
    stop("Database not found at: ", db_path)
  }
  
  con <- duckdb::dbConnect(duckdb::duckdb(), db_path)
  
  # Check current schema
  cat("Step 1: Checking current schema...\n")
  tables <- DBI::dbListTables(con)
  cat("  Current tables:", paste(tables, collapse = ", "), "\n\n")
  
  # Backup existing data
  cat("Step 2: Backing up existing data...\n")
  if ("farm_timeseries" %in% tables) {
    ts_backup <- DBI::dbGetQuery(con, "SELECT * FROM farm_timeseries")
    cat("  Backed up", nrow(ts_backup), "timeseries records\n")
  } else {
    ts_backup <- NULL
  }
  
  if ("farm_rasters" %in% tables) {
    raster_backup <- DBI::dbGetQuery(con, "SELECT * FROM farm_rasters")
    cat("  Backed up", nrow(raster_backup), "raster records\n")
  } else {
    raster_backup <- NULL
  }
  cat("\n")
  
  # Create enhanced schema
  cat("Step 3: Creating enhanced schema...\n")
  
  # Drop old tables (will recreate with new schema)
  if ("farm_timeseries" %in% tables) {
    DBI::dbExecute(con, "DROP TABLE farm_timeseries")
    cat("  Dropped old farm_timeseries\n")
  }
  
  # Enhanced farm_timeseries with std, percentiles, and threshold info
  DBI::dbExecute(con, "
    CREATE TABLE farm_timeseries (
      farm_id        TEXT,
      crop_type      TEXT,
      sowing_date    DATE,
      variable       TEXT,
      start_date     DATE,
      end_date       DATE,
      mean_val       DOUBLE,
      min_val        DOUBLE,
      max_val        DOUBLE,
      std_val        DOUBLE,
      p05_val        DOUBLE,
      p95_val        DOUBLE,
      threshold_pct  DOUBLE DEFAULT 0.0,
      pixels_used    INTEGER,
      pixels_total   INTEGER,
      updated_at     TIMESTAMP DEFAULT current_timestamp,
      PRIMARY KEY (farm_id, variable, start_date)
    )
  ")
  cat("  Created enhanced farm_timeseries table\n")
  
  # Enhanced farm_rasters with extent info
  if ("farm_rasters" %in% tables) {
    DBI::dbExecute(con, "DROP TABLE farm_rasters")
    cat("  Dropped old farm_rasters\n")
  }
  
  DBI::dbExecute(con, "
    CREATE TABLE farm_rasters (
      farm_id      TEXT,
      variable     TEXT,
      date_key     DATE,
      raster_blob  BLOB,
      xmin         DOUBLE,
      xmax         DOUBLE,
      ymin         DOUBLE,
      ymax         DOUBLE,
      nrow         INTEGER,
      ncol         INTEGER,
      updated_at   TIMESTAMP DEFAULT current_timestamp,
      PRIMARY KEY (farm_id, variable, date_key)
    )
  ")
  cat("  Created enhanced farm_rasters table\n")
  
  # New farm_metadata table
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS farm_metadata (
      farm_id      TEXT PRIMARY KEY,
      crop_type    TEXT,
      sowing_date  DATE,
      area_ha      DOUBLE,
      xmin         DOUBLE,
      xmax         DOUBLE,
      ymin         DOUBLE,
      ymax         DOUBLE,
      created_at   TIMESTAMP DEFAULT current_timestamp
    )
  ")
  cat("  Created farm_metadata table\n")
  
  # Monitoring log (keep as-is, no changes needed)
  if (!("monitoring_log" %in% tables)) {
    DBI::dbExecute(con, "
      CREATE TABLE IF NOT EXISTS monitoring_log (
        run_id       TEXT PRIMARY KEY,
        started_at   TIMESTAMP,
        finished_at  TIMESTAMP,
        n_records    INTEGER,
        n_farms      INTEGER,
        status       TEXT,
        message      TEXT
      )
    ")
    cat("  Created monitoring_log table\n")
  }
  cat("\n")
  
  # Restore data with migration
  cat("Step 4: Restoring data...\n")
  if (!is.null(ts_backup) && nrow(ts_backup) > 0) {
    # Migrate old data to new schema (fill new columns with defaults)
    ts_backup$std_val <- NA_real_
    ts_backup$p05_val <- NA_real_
    ts_backup$p95_val <- NA_real_
    ts_backup$threshold_pct <- 0.0
    ts_backup$pixels_used <- NA_integer_
    ts_backup$pixels_total <- NA_integer_
    
    DBI::dbWriteTable(con, "farm_timeseries", ts_backup, append = TRUE)
    cat("  Restored", nrow(ts_backup), "timeseries records\n")
    cat("  NOTE: std_val, percentiles need recalculation from rasters\n")
  }
  
  if (!is.null(raster_backup) && nrow(raster_backup) > 0) {
    # Add extent columns (will be NULL, need to recalculate)
    raster_backup$xmin <- NA_real_
    raster_backup$xmax <- NA_real_
    raster_backup$ymin <- NA_real_
    raster_backup$ymax <- NA_real_
    raster_backup$nrow <- NA_integer_
    raster_backup$ncol <- NA_integer_
    
    DBI::dbWriteTable(con, "farm_rasters", raster_backup, append = TRUE)
    cat("  Restored", nrow(raster_backup), "raster records\n")
  }
  cat("\n")
  
  # Extract farm metadata from timeseries
  cat("Step 5: Populating farm_metadata...\n")
  if (!is.null(ts_backup) && nrow(ts_backup) > 0) {
    farm_meta_sql <- "
      INSERT INTO farm_metadata (farm_id, crop_type, sowing_date)
      SELECT DISTINCT farm_id, crop_type, sowing_date
      FROM farm_timeseries
      WHERE farm_id IS NOT NULL
      ON CONFLICT (farm_id) DO NOTHING
    "
    n_farms <- DBI::dbExecute(con, farm_meta_sql)
    cat("  Populated metadata for", n_farms, "farms\n")
    cat("  NOTE: area_ha and extents need to be set from polygon data\n")
  }
  cat("\n")
  
  # Create indices for faster queries
  cat("Step 6: Creating indices...\n")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ts_farmvar ON farm_timeseries(farm_id, variable)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_ts_date ON farm_timeseries(start_date)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_raster_farmvar ON farm_rasters(farm_id, variable)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_raster_date ON farm_rasters(date_key)")
  cat("  Created performance indices\n\n")
  
  # Show final schema
  cat("Step 7: Final schema summary\n")
  for (tbl in c("farm_timeseries", "farm_rasters", "farm_metadata", "monitoring_log")) {
    if (tbl %in% DBI::dbListTables(con)) {
      count <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) as n FROM ", tbl))$n
      cat("  ", tbl, ":", count, "rows\n")
    }
  }
  
  DBI::dbDisconnect(con, shutdown = TRUE)
  
  cat("\n=== Migration Complete ===\n")
  cat("Database upgraded successfully!\n")
  cat("\nNext steps:\n")
  cat("1. Re-run monitoring with 'Save rasters' enabled to populate farm_rasters\n")
  cat("2. Enhanced stats (std, percentiles) will be calculated automatically\n")
  cat("3. Use threshold controls to filter out low-value pixels\n")
  
  invisible(TRUE)
}

# Run migration if called directly
if (!interactive()) {
  db_path <- "C:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor/inst/shiny/monitoring.duckdb"
  migrate_monitoring_db(db_path)
}
