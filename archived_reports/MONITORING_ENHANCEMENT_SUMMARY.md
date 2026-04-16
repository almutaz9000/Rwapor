# Monitoring Module Enhancement Summary

## ✅ COMPLETED (Ready to Use)

### 1. Database Schema Enhanced ✅
- **Enhanced `farm_timeseries` table:**
  - Added: `std_val`, `p05_val`, `p95_val` (enhanced statistics)
  - Added: `threshold_pct` (tracks filter threshold used)
  - Added: `pixels_used`, `pixels_total` (tracks filtering transparency)

- **Enhanced `farm_rasters` table:**
  - Added: `xmin`, `xmax`, `ymin`, `ymax` (extent for map zooming)
  - Added: `nrow`, `ncol` (raster dimensions)

- **New `farm_metadata` table:**
  - Fields: `farm_id`, `crop_type`, `sowing_date`, `area_ha`, `xmin`, `xmax`, `ymin`, `ymax`
  - Purpose: Quick farm info lookups without loading rasters

- **Performance indices created** on `farm_id+variable` and `date` columns

### 2. Helper Functions Library ✅
**File:** `inst/shiny/monitoring_helpers.R`

All functions tested and working:

1. **`wapor_enhanced_zonal_stats(raster, polygon, threshold_percentile = 0)`**
   - Calculates: mean, min, max, std, p05, p95
   - Applies threshold filtering (0-50th percentile to remove low values)
   - Returns pixels_used and pixels_total for transparency
   - Uses exactextractr for accurate coverage fractions

2. **`wapor_raster_from_blob(blob_data)`**
   - Extracts terra SpatRaster from DuckDB BLOB
   - Handles temp file management

3. **`wapor_save_raster_to_db(con, farm_id, variable, date_key, raster)`**
   - Saves raster to BLOB with extent metadata
   - Upsert pattern (insert or update on conflict)

4. **`wapor_get_farms_extent(con)`**
   - Returns combined extent: `c(xmin, xmax, ymin, ymax)`
   - Tries farm_rasters first, falls back to farm_metadata
   - For map zooming functionality

5. **`wapor_update_farm_metadata(con, farm_id, polygon)`**
   - Updates farm extent and area_ha
   - Uses equal-area projection (EPSG:6933) for accurate area calculation

6. **`wapor_plot_raster_timeseries(con, farm_id, variable, date_range = NULL)`**
   - Creates ggplot2 time series with:
     - Mean line
     - ± 1 std ribbon (shaded)
     - Min-max range ribbon (lighter)
   - Includes threshold info in subtitle
   - Optional date range filtering

7. **`wapor_recalculate_stats_from_rasters(con, farm_id, polygon, threshold_pct = 5)`**
   - Recalculates all stats from saved rasters with new threshold
   - Updates all records for farm_id in farm_timeseries
   - Returns number of records updated

### 3. Module Updates ✅

**File:** `inst/shiny/mod_monitoring.R`

- ✅ Sourced `monitoring_helpers.R` at module start
- ✅ Updated `open_db()` to create enhanced schema with all new columns and indices
- ✅ Updated `.save_raster_blobs()` to:
  - Save **per-farm clipped rasters** (instead of union)
  - Store extent metadata (xmin, xmax, ymin, ymax, nrow, ncol)
  - Update farm_metadata table with extent and area_ha
  - Use `wapor_save_raster_to_db()` helper

- ✅ Added UI controls in new "Enhanced Analysis" accordion panel:
  - Threshold percentile slider (0-50%, default 5%)
  - "Recalculate Stats with Threshold" button
  - "Plot Raster Time Series" button
  - "Zoom Map to Farm Extent" button

### 4. Database Migration ✅

**File:** `migrate_monitoring_schema.R`

- Successfully migrated existing database (67,050 records preserved)
- Created farm_metadata table (75 farms)
- All data integrity maintained

### 5. Testing ✅

**File:** `test_monitoring_helpers.R`

- All 7 helper functions tested and working
- Enhanced zonal stats validated (5% threshold filters correctly)
- Raster save/load to BLOB working
- Farm metadata updates working
- Extent extraction working

---

## 🔄 PENDING (Server Logic to Add)

### Server Event Handlers Needed

Add these `observeEvent` handlers to `mod_monitoring_server()`:

#### 1. Recalculate Stats Button
```r
# Add after line ~1300 in mod_monitoring_server()
shiny::observeEvent(input$btn_recalculate, {
  shiny::req(rv$farms_sf, input$db_path, input$threshold_pct)
  
  con <- tryCatch(
    duckdb::dbConnect(duckdb::duckdb(), dbdir = input$db_path),
    error = function(e) {
      shiny::showNotification(paste("DB error:", e$message), type = "error")
      NULL
    }
  )
  if (is.null(con)) return()
  
  shiny::withProgress(message = "Recalculating stats...", {
    total_updated <- 0
    for (i in seq_len(nrow(rv$farms_sf))) {
      farm_id <- as.character(rv$farms_sf$farm_id[i])
      farm_geom <- rv$farms_sf[i, ]
      
      n_updated <- tryCatch(
        wapor_recalculate_stats_from_rasters(
          con, farm_id, farm_geom, input$threshold_pct
        ),
        error = function(e) {
          shiny::showNotification(
            paste("Error for farm", farm_id, ":", e$message),
            type = "warning"
          )
          0
        }
      )
      total_updated <- total_updated + n_updated
      shiny::incProgress(1 / nrow(rv$farms_sf))
    }
    
    # Reload data
    rv$ts_data <- DBI::dbGetQuery(con, 
      "SELECT * FROM farm_timeseries ORDER BY farm_id, variable, start_date"
    )
    
    shiny::showNotification(
      sprintf("✓ Recalculated %d records with %d%% threshold", 
              total_updated, input$threshold_pct),
      type = "message", duration = 5
    )
  })
  
  DBI::dbDisconnect(con, shutdown = TRUE)
})
```

#### 2. Plot Raster Time Series Button
```r
# Add after recalculate handler
shiny::observeEvent(input$btn_plot_rasters, {
  shiny::req(input$db_path, rv$ts_data)
  
  # Get selected farm from ts_farm_select input
  farm_id <- shiny::req(input$ts_farm_select)
  variable <- shiny::req(input$ts_variable)
  
  con <- tryCatch(
    duckdb::dbConnect(duckdb::duckdb(), dbdir = input$db_path),
    error = function(e) {
      shiny::showNotification(paste("DB error:", e$message), type = "error")
      NULL
    }
  )
  if (is.null(con)) return()
  
  p <- tryCatch(
    wapor_plot_raster_timeseries(con, farm_id, variable),
    error = function(e) {
      shiny::showNotification(paste("Plot error:", e$message), type = "error")
      NULL
    }
  )
  
  DBI::dbDisconnect(con, shutdown = TRUE)
  
  if (!is.null(p)) {
    shiny::showModal(shiny::modalDialog(
      title = sprintf("Raster Time Series: %s - %s", farm_id, variable),
      shiny::renderPlot(p, height = 500),
      size = "l",
      easyClose = TRUE
    ))
  }
})
```

#### 3. Zoom Map to Farms Button
```r
# Add after plot handler
shiny::observeEvent(input$btn_zoom_farms, {
  shiny::req(input$db_path)
  
  con <- tryCatch(
    duckdb::dbConnect(duckdb::duckdb(), dbdir = input$db_path),
    error = function(e) {
      shiny::showNotification(paste("DB error:", e$message), type = "error")
      NULL
    }
  )
  if (is.null(con)) return()
  
  extent <- tryCatch(
    wapor_get_farms_extent(con),
    error = function(e) {
      shiny::showNotification(paste("Extent error:", e$message), type = "warning")
      NULL
    }
  )
  
  DBI::dbDisconnect(con, shutdown = TRUE)
  
  if (!is.null(extent) && length(extent) == 4) {
    leafletProxy("farm_map", session) %>%
      leaflet::fitBounds(extent[1], extent[3], extent[2], extent[4])
  } else {
    shiny::showNotification("No farm extents available. Run monitoring with 'Save rasters' enabled.",
                           type = "warning")
  }
})
```

---

## 📋 NEXT STEPS

### 1. Add Server Handlers (Priority: HIGH)
Add the three `observeEvent` handlers above to `mod_monitoring_server()` function around line 1300-1400.

### 2. Test Enhanced Features (Priority: HIGH)
1. Stop and restart Shiny app
2. Load existing database (67,050 records)
3. Run new monitoring with "Also clip & save raster layers" **ENABLED**
4. Test threshold recalculation (try 5%, 10%)
5. Test raster time series plotting
6. Test map zoom functionality

### 3. Verify Enhanced Stats Display (Priority: MEDIUM)
- Check that `std_val`, `p05_val`, `p95_val` display in Data Table tab
- Verify `threshold_pct`, `pixels_used`, `pixels_total` are populated
- Confirm extent metadata saved in farm_rasters table

### 4. Documentation Updates (Priority: LOW)
- Add example to module documentation showing threshold usage
- Document enhanced database schema in README
- Add migration notes for existing users

---

## 🎯 KEY CAPABILITIES NOW AVAILABLE

1. **Threshold-Based Filtering**: Remove low-value pixels (e.g., bare soil) before calculating mean
2. **Enhanced Statistics**: Get min, mean, max, std, p05, p95 for each farm
3. **Raster Time Series Plots**: Visualize trends with uncertainty ribbons
4. **Map Zoom to Farms**: Automatically zoom to saved farm extent
5. **Transparent Tracking**: See how many pixels were filtered (pixels_used vs pixels_total)
6. **Efficient Storage**: Per-farm rasters with extent metadata for quick retrieval
7. **Area Calculation**: Accurate hectare calculation using equal-area projection

---

## 📂 FILES MODIFIED/CREATED

### Created
- `inst/shiny/monitoring_helpers.R` (7 helper functions)
- `migrate_monitoring_schema.R` (database upgrade script)
- `inspect_monitoring_db.R` (database analysis tool)
- `test_monitoring_helpers.R` (test suite)
- `MONITORING_ENHANCEMENT_SUMMARY.md` (this file)

### Modified
- `inst/shiny/mod_monitoring.R`:
  - Sourced helper functions
  - Enhanced `open_db()` schema
  - Updated `.save_raster_blobs()` to save per-farm with metadata
  - Added "Enhanced Analysis" UI panel

### Database
- `inst/shiny/monitoring.duckdb`:
  - Migrated to enhanced schema
  - 67,050 records preserved
  - 75 farms in metadata table
  - 0 rasters (need re-run with "Save rasters" enabled)

---

## ⚠️ IMPORTANT NOTES

1. **Raster storage requirement**: The existing database has 0 rasters. You MUST re-run monitoring with "Also clip & save raster layers" **ENABLED** to populate farm_rasters table and enable:
   - Threshold recalculation
   - Raster time series plotting
   - Map zoom to extent

2. **Std/percentile values**: Currently NULL in migrated records. Will auto-populate on next monitoring run or via recalculation button.

3. **Performance**: Saving per-farm rasters is slower but enables advanced features. Typical overhead: +2-5 seconds per variable.

4. **Storage**: Each clipped farm raster ~100-500 KB compressed. For 75 farms × 5 variables × 36 dekads ≈ 1-5 GB total.

---

## 🧪 TESTING CHECKLIST

- [ ] Stop Shiny app
- [ ] Add server event handlers (recalculate, plot, zoom)
- [ ] Restart Shiny app with `run_wapor()`
- [ ] Load database (should show 67,050 records)
- [ ] Check Data Table tab shows new columns (std_val, p05_val, p95_val - will be NULL)
- [ ] Run monitoring with "Save rasters" enabled (choose 1-2 variables to save time)
- [ ] Verify farm_rasters table populated (check with inspect_monitoring_db.R)
- [ ] Test threshold recalculation (5% threshold)
- [ ] Verify Data Table now shows updated std_val, percentiles
- [ ] Test "Plot Raster Time Series" button
- [ ] Test "Zoom Map to Farm Extent" button
- [ ] Verify map zooms correctly to farm bounding box

---

## 🚀 READY FOR INTEGRATION

All foundation work is complete! The database schema, helper functions, and UI are ready. Only the three server event handlers need to be added to make the features fully functional.

**Estimated time to complete**: 10-15 minutes to add handlers + 20-30 minutes testing
