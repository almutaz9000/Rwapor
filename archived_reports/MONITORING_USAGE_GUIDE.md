# 🎉 Monitoring Tab - Ready to Use!

## ✅ Issue Resolved

**Original Error:**
```
DB error: 'dbExecute' is not an exported object from 'namespace:duckdb'
```

**Fix Applied:**
Changed all instances of `duckdb::dbExecute()` to `DBI::dbExecute()` in `inst/shiny/mod_monitoring.R`

## 🧪 Test Results

### ✓ All Tests Passed

```
✓ Loaded 75 farm polygons from Pivots_savola2.geojson
✓ DuckDB tables created successfully
✓ Downloaded WaPOR data (L1-AETI-A)
✓ Extracted raster statistics
✓ Inserted 1 time series records
✓ Saved 1 rasters as BLOBs
✓ Successfully retrieved raster from database
```

## 📋 How to Use the Monitoring Tab

### 1. Launch the Shiny App

```r
# From R console (using R 4.5.3)
Rwapor::run_wapor()
```

### 2. Navigate to Monitoring Tab

Click on the "Monitoring" tab in the app

### 3. Load Your Polygon

1. Click **"Upload Polygon"**
2. Select: `C:\Users\Mohammedal\OneDrive - Food and Agriculture Organization\Documents\GitHub\Rwapor\Pivots_savola2.geojson`
3. Verify 75 farms loaded (A1, A3, A31, A34, A35, A40, A41, A42, A45, A46, etc.)

### 4. Set Date Range

- **Start Date:** 2018-01-01
- **End Date:** 2026-04-15 (or current date)
- **Total Period:** ~8 years (3026 days)

### 5. Configure DuckDB Storage

1. **Enable DuckDB**: Check "Save to database"
2. **Database Path**: Choose location (e.g., `monitoring_data.duckdb`)
3. **Extract Rasters**: Check "Save raster data" to store rasters as BLOBs

### 6. Select Variables to Monitor

Recommended variables for farm monitoring:

**Water Use:**
- `L1-AETI-A` - Actual Evapotranspiration (mm)
- `L1-T-A` - Transpiration (mm)
- `L1-E-A` - Evaporation (mm)

**Biomass Production:**
- `L1-NPP-D` - Net Primary Production (gC/m²)
- `L1-TBP-D` - Total Biomass Production (kg/ha)

**Climate:**
- `AGERA5-PRECIP-E` - Precipitation (mm)
- `AGERA5-TMIN-E` - Minimum Temperature (°C)
- `AGERA5-TMAX-E` - Maximum Temperature (°C)

### 7. Run Monitoring

Click **"Start Monitoring"** to begin data download and processing

## 📊 Database Schema

The monitoring system creates 3 tables:

### farm_timeseries
Stores aggregated statistics per farm:
- `farm_id`: Farm identifier (A1, A3, etc.)
- `crop_type`: Crop name (Wheat, Beet, etc.)
- `variable`: WaPOR variable (AETI-A, NPP-D, etc.)
- `start_date`: Time step date
- `mean_val`, `min_val`, `max_val`: Statistics
- `updated_at`: Last update timestamp

### farm_rasters
Stores raster BLOBs for spatial analysis:
- `farm_id`: Farm identifier
- `variable`: WaPOR variable
- `date_key`: Date of the raster
- `raster_blob`: Compressed GeoTIFF as BLOB
- `updated_at`: Last update timestamp

### monitoring_log
Tracks monitoring runs:
- `run_id`: Unique run identifier
- `started_at`, `finished_at`: Timestamps
- `n_records`: Number of records processed
- `status`, `message`: Run status and logs

## 🔍 Querying the Database

### Connect to DuckDB

```r
library(duckdb)
library(DBI)

con <- duckdb::dbConnect(duckdb::duckdb(), "monitoring_data.duckdb")
```

### View Available Tables

```r
DBI::dbListTables(con)
```

### Query Timeseries Data

```r
# Get all data for farm A1
farm_data <- DBI::dbGetQuery(con, "
  SELECT farm_id, variable, start_date, mean_val
  FROM farm_timeseries
  WHERE farm_id = 'A1'
  ORDER BY start_date
")

# Get average AETI by farm
avg_aeti <- DBI::dbGetQuery(con, "
  SELECT farm_id, AVG(mean_val) as avg_aeti
  FROM farm_timeseries
  WHERE variable = 'AETI-A'
  GROUP BY farm_id
  ORDER BY avg_aeti DESC
")

# Monthly totals
monthly <- DBI::dbGetQuery(con, "
  SELECT 
    farm_id,
    strftime('%Y-%m', start_date) as month,
    SUM(mean_val) as monthly_total
  FROM farm_timeseries
  WHERE variable = 'AETI-A'
  GROUP BY farm_id, month
  ORDER BY farm_id, month
")
```

### Retrieve Raster from BLOB

```r
# Get raster for specific farm and date
raster_row <- DBI::dbGetQuery(con, "
  SELECT raster_blob 
  FROM farm_rasters 
  WHERE farm_id = 'A1' 
    AND variable = 'AETI-A' 
    AND date_key = '2024-01-01'
  LIMIT 1
")

# Save BLOB to file
temp_file <- tempfile(fileext = ".tif")
writeBin(raster_row$raster_blob[[1]], temp_file)

# Read with terra
library(terra)
farm_raster <- terra::rast(temp_file)
plot(farm_raster)
```

### Disconnect

```r
DBI::dbDisconnect(con, shutdown = TRUE)
```

## 📁 Files Created

### Test Scripts
- ✅ `test_monitoring.R` - Comprehensive end-to-end test
- ✅ `test_minimal_duckdb.R` - Minimal DuckDB verification
- ✅ `test_monitoring_module_load.R` - Module loading test

### Documentation
- ✅ `MONITORING_FIX_SUMMARY.md` - Technical fix details
- ✅ `MONITORING_USAGE_GUIDE.md` - This file

### Test Outputs (can be deleted)
- `test_monitoring.duckdb`
- `test_monitoring_output/`
- `test_minimal.duckdb`

## ⚠️ Important Notes

### R Version
Always use R 4.5.3 located at:
```
C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe
```

### Memory Considerations
- 75 farms × 8 years × multiple variables = large dataset
- Consider monitoring in smaller batches (e.g., by year)
- Use `batch_size` parameter in `wapor_map()` to control memory

### Data Availability
- L1 (Global): Best coverage, coarser resolution
- L2 (Regional): Better resolution, may have gaps
- L3 (Local): Highest resolution, limited areas
- Check WaPOR data availability for your region and period

### Storage
- Raster BLOBs can become large (MB per raster)
- A full 8-year monitoring with all variables could be >10GB
- Consider storing only summary statistics if storage is limited

## 🚀 Next Steps

1. **Test with Small Period First**
   - Try 1 month before running full 8 years
   - Verify data quality and database size

2. **Optimize Variable Selection**
   - Choose only variables needed for your analysis
   - L1-AETI-A and L1-NPP-D are good starting points

3. **Set Up Automated Monitoring**
   - Schedule regular updates (e.g., weekly)
   - Monitor new data as it becomes available

4. **Analysis and Visualization**
   - Export to CSV for Excel/PowerBI
   - Create time series plots
   - Compare farms and seasons
   - Detect anomalies and trends

## ✉️ Support

If you encounter any issues:
1. Check R version (must be 4.5.3)
2. Verify polygon file path
3. Check internet connection (for WaPOR API)
4. Review database file permissions
5. Check available disk space

---

**Status:** ✅ READY FOR PRODUCTION USE

**Last Updated:** 2026-04-15
**Tested With:** Rwapor v0.1.0, R 4.5.3
