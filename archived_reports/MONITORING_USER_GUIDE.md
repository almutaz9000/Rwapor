# Monitoring Module - Enhanced Features User Guide

## 🎉 NEW FEATURES

Your monitoring module now includes powerful new capabilities for threshold-based filtering, enhanced statistics, and raster time series visualization!

---

## 📊 Enhanced Statistics

### What's New
Every farm now gets **7 statistical measures** instead of 3:
- **mean_val**: Area-weighted mean (as before)
- **min_val**: Minimum pixel value
- **max_val**: Maximum pixel value
- **std_val**: Standard deviation (NEW)
- **p05_val**: 5th percentile (NEW)
- **p95_val**: 95th percentile (NEW)
- **threshold_pct**: Percentile threshold used for filtering (NEW)
- **pixels_used** / **pixels_total**: Transparency into how many pixels were filtered (NEW)

### How It Works
The enhanced stats are automatically calculated when you:
1. Enable "Also clip & save raster layers to database"
2. Run monitoring

For existing data, use the "Recalculate Stats with Threshold" button.

---

## 🎯 Threshold-Based Filtering

### Problem Solved
Fields often have bare soil patches, infrastructure, or non-cropped areas that drag down the mean values and give a misleading picture of crop health.

### Solution
The **Threshold Percentile** slider removes low-value pixels before calculating statistics.

### Example
```
Without threshold (0%):  Mean AETI = 296.6 mm/dekad (includes bare soil)
With 5% threshold:       Mean AETI = 301.2 mm/dekad (bare soil removed)
```

### How to Use
1. **Set threshold**: Move slider to 5-10% (sidebar → "Enhanced Analysis")
2. **Save rasters**: Enable "Also clip & save raster layers" when monitoring
3. **Recalculate**: Click "Recalculate Stats with Threshold" button
4. **Review**: Check Data Table tab - `pixels_used` shows how many pixels remained

### Recommended Values
- **5%**: Default, removes bare soil patches
- **10%**: Aggressive filtering for fields with significant non-cropped areas
- **0%**: No filtering (original behavior)
- **25%+**: Use with caution, removes too much data

---

## 📈 Raster Time Series Plots

### What It Does
Creates beautiful time series plots showing:
- **Mean line**: The primary trend
- **± 1 std ribbon**: Variability around the mean (shaded)
- **Min-max ribbon**: Full range of values (lighter shade)

### How to Use
1. **Select farm**: In "Time Series" tab, choose a farm from dropdown
2. **Select variable**: Choose which variable to plot (e.g., L1-AETI-D)
3. **Click button**: "Plot Raster Time Series" (sidebar → "Enhanced Analysis")
4. **View modal**: Plot appears in popup with title showing farm ID and variable

### Example Plot
```
Farm: farm_42 - L1-AETI-D

Y-axis: mm/dekad
X-axis: Date

Blue line: Mean AETI
Light blue ribbon: Mean ± 1 std
Lighter ribbon: Min to Max range

Subtitle shows: "Threshold: 5% (623/656 pixels used)"
```

### Requirements
- Must have saved rasters for the farm and variable
- Run monitoring with "Save rasters" enabled

---

## 🗺️ Map Zoom to Farm Extent

### What It Does
Automatically zooms the map to show all monitored farms based on their saved raster extents.

### How to Use
1. **Click button**: "Zoom Map to Farm Extent" (sidebar → "Enhanced Analysis")
2. **Map updates**: Farm Map tab automatically zooms to fit all farms

### Benefits
- No manual panning/zooming needed
- Consistent view across sessions
- Especially useful for widely distributed farms

### Requirements
- Database must have farm_rasters or farm_metadata with extent information
- Populated automatically when monitoring with "Save rasters" enabled

---

## 🔄 Workflow: First Time Setup

### Step 1: Load Farm Layer
Upload your GeoJSON/GPKG file with farm polygons in the "Farm Layer" panel.

### Step 2: Configure Season
Set sowing date and harvest/end date in "Season Setup" panel.

### Step 3: Select Variables
Choose variables to monitor (e.g., L1-AETI-D, L1-RET-D, L1-NPP-D) in "WaPOR Variables" panel.

### Step 4: Enable Raster Saving ⭐
**IMPORTANT**: Check "Also clip & save raster layers to database" in "Database" panel.
- This enables all new features
- Adds ~1-5 GB storage (75 farms × 5 variables × 36 dekads)
- Slower initial run but enables powerful analysis

### Step 5: Set Threshold (Optional)
Set "Threshold percentile" to 5% in "Enhanced Analysis" panel (recommended starting point).

### Step 6: Run Monitoring
Click "Monitor / Update" button. Progress bar shows:
- Downloading rasters
- Saving per-farm clipped rasters
- Calculating enhanced statistics
- Updating farm metadata

### Step 7: Explore Results
- **Farm Map**: Color-coded by stress index or cumulative AETI
- **Time Series**: Traditional time series per farm
- **Raster View**: View individual raster layers
- **Data Table**: Export enhanced stats (includes std, percentiles)

---

## 🔄 Workflow: Adjusting Threshold

If you want to try different threshold values:

### Step 1: Change Threshold
Move slider to new value (e.g., 10%) in "Enhanced Analysis" panel.

### Step 2: Recalculate
Click "Recalculate Stats with Threshold" button.
- Progress bar shows farm-by-farm processing
- Uses existing saved rasters (no re-download needed!)
- Updates all timeseries records with new stats

### Step 3: Review Changes
- Check Data Table tab
- Compare `pixels_used` / `pixels_total` ratio
- Look at updated `mean_val`, `std_val`, percentiles
- Verify `threshold_pct` column shows new value

### Step 4: Visualize
Click "Plot Raster Time Series" to see:
- How mean changed with new threshold
- Updated variability (std ribbon)
- Subtitle shows new pixels_used/pixels_total

---

## 📁 Database Structure

Your `monitoring.duckdb` now has **4 tables**:

### 1. farm_timeseries (Main Stats)
```
farm_id, crop_type, sowing_date, variable, start_date, end_date,
mean_val, min_val, max_val,               ← Original stats
std_val, p05_val, p95_val,                ← NEW: Enhanced stats
threshold_pct, pixels_used, pixels_total  ← NEW: Filtering metadata
```

### 2. farm_rasters (Saved Rasters)
```
farm_id, variable, date_key, raster_blob,
xmin, xmax, ymin, ymax, nrow, ncol        ← NEW: Extent metadata
```
- Used for threshold recalculation
- Used for raster time series plotting
- Used for map zoom extent

### 3. farm_metadata (Farm Info)
```
farm_id, crop_type, sowing_date,
area_ha,                                   ← NEW: Accurate hectares
xmin, xmax, ymin, ymax                     ← NEW: Farm extent
```
- Auto-populated during monitoring
- Area calculated using equal-area projection (EPSG:6933)

### 4. monitoring_log (Run History)
```
run_id, started_at, finished_at, n_records, status, message
```

### Indices (for performance)
- `idx_timeseries_farm_var` on `(farm_id, variable)`
- `idx_timeseries_date` on `start_date`
- `idx_rasters_farm_var` on `(farm_id, variable)`

---

## 🧪 Testing Checklist

After updating, verify everything works:

- [ ] Shiny app starts without errors (`run_wapor()`)
- [ ] Load existing database shows 67,050 records
- [ ] Data Table tab displays (std_val may be NULL for old records)
- [ ] Run monitoring with "Save rasters" **ENABLED**
- [ ] Check farm_rasters table populated (inspect_monitoring_db.R)
- [ ] Threshold slider works (5%, 10%, etc.)
- [ ] "Recalculate Stats" button works, updates std_val/percentiles
- [ ] Data Table shows updated pixels_used/pixels_total
- [ ] "Plot Raster Time Series" opens modal with ggplot
- [ ] Plot shows mean line + ribbons correctly
- [ ] "Zoom Map to Farm Extent" zooms correctly
- [ ] Export CSV includes all new columns

---

## 💡 Tips & Best Practices

### Storage Management
- **Disable raster saving** if disk space is limited and you don't need advanced features
- **Enable selectively**: Only save rasters for key variables (e.g., AETI, NPP)
- Each farm raster: ~100-500 KB compressed
- Total for 75 farms × 5 variables × 36 dekads ≈ 1-5 GB

### Threshold Selection
- **Start with 5%**: Good balance for most fields
- **Increase to 10-15%**: Fields with significant infrastructure/bare soil
- **Use 0%**: When you need true area-weighted mean (e.g., water balance)
- **Check pixels_used**: Aim for >80% pixel retention (e.g., 656 → 623 pixels)

### Performance
- **Initial monitoring**: Slower with raster saving (+2-5 sec per variable)
- **Threshold recalculation**: Fast! No re-download needed
- **Map zoom**: Instant (uses pre-computed extents)
- **Raster plots**: Moderate (loads BLOBs from DB)

### Data Integrity
- **Backup database**: Before major threshold changes
- **Document threshold**: Note which threshold was used for reports
- **Version control**: Save database snapshots for reproducibility

---

## 🐛 Troubleshooting

### "No saved rasters found" warning
**Cause**: Database created before raster saving was enabled.
**Fix**: Run monitoring with "Also clip & save raster layers" checked.

### Std/percentiles show as NULL
**Cause**: Records created before enhanced stats were implemented.
**Fix**: Run "Recalculate Stats with Threshold" button (requires saved rasters).

### "Plot error" when clicking "Plot Raster Time Series"
**Cause**: Selected farm/variable doesn't have saved rasters.
**Fix**: Ensure monitoring was run with "Save rasters" for that variable.

### Map doesn't zoom
**Cause**: No extent metadata available.
**Fix**: Run monitoring with "Save rasters" to populate extents.

### Database file very large
**Cause**: Many rasters saved (expected behavior).
**Solution**:
- Delete old rasters: Manually remove records from farm_rasters table
- Compress database: Run `VACUUM;` in DuckDB
- Selective saving: Only enable "Save rasters" when needed

---

## 📞 Support

For questions or issues:
1. Check this guide first
2. Review MONITORING_ENHANCEMENT_SUMMARY.md for technical details
3. Check Data Table tab for data integrity
4. Run `inspect_monitoring_db.R` to diagnose database issues

---

## 🚀 What's Next?

Future enhancements could include:
- **Spatial hotspot detection**: Identify areas within farms with anomalies
- **Crop coefficient curves**: Plot Kc over season
- **Multi-season comparison**: Compare current vs. previous seasons
- **Automated alerting**: Email alerts when stress indices drop
- **Export report**: PDF with maps, plots, and summary statistics

---

**Enjoy your enhanced monitoring capabilities!** 🌾📊🗺️
