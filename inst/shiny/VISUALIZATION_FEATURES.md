# Enhanced Visualization Tab Features

## Overview

The Visualization tab now supports advanced raster comparison and conditional query plotting capabilities, allowing users to:

1. **Compare two rasters side-by-side**
2. **Apply conditional queries** to filter pixels based on custom expressions
3. **Visualize pixel intersections** between two rasters

---

## Three Visualization Modes

### 1. Single Raster Mode (Default)
Standard single raster visualization with:
- Band/layer selection
- Customizable color palettes
- Opacity controls
- Continuous or binned color methods

### 2. Dual Raster Comparison Mode
Load and compare two rasters simultaneously with:
- **Independent color palettes** for each raster
- **Three display options:**
  - **Overlay**: Show both rasters with adjustable opacity
  - **Side-by-Side**: Visual comparison (future enhancement)
  - **Intersection Only**: Display only pixels where both rasters have values

**Use Cases:**
- Compare different time periods (e.g., AETI from 2020 vs 2021)
- Analyze different variables over the same region
- Identify spatial overlap between datasets

### 3. Conditional Query Mode
Apply logical expressions to filter and visualize pixels based on custom conditions.

**Query Expression Syntax:**
```
Raster1 [operator] [value] [logical] Raster2 [operator] [value]
```

**Supported Operators:**
- Comparison: `>=`, `<=`, `>`, `<`, `==`, `!=`
- Logical: `&` (AND), `|` (OR)

**Example Queries:**
```
# Find pixels where Raster1 is high AND Raster2 is low
Raster1 >= 150 & Raster2 <= 20

# Find pixels where either condition is true
Raster1 > 200 | Raster2 < 10

# Complex multi-condition query
Raster1 >= 100 & Raster1 <= 300 & Raster2 > 50
```

**Query Visualization:**
- **Match pixels**: Displayed in selected "Match Color" (default: red)
- **No-match pixels**: Displayed in "No Match Color" (default: gray)
- **Statistics panel**: Shows count and percentage of matching pixels

---

## User Interface Guide

### Visualization Mode Panel
Select the mode that fits your analysis:
- **Single Raster**: Standard visualization
- **Dual Raster Comparison**: Load two rasters
- **Conditional Query**: Apply logical filtering

### Raster Selection Panel
- **Raster 1**: Always visible
- **Raster 2**: Appears in Dual and Query modes
- Band/layer selection for multi-band rasters
- Rescan button to refresh available files

### Conditional Query Builder (Query Mode Only)
1. **Query Expression**: Text area for entering logical expressions
2. **Match Color**: Color for pixels that satisfy the condition
3. **No Match Color**: Color for pixels that don't satisfy the condition
4. **Query Layer Opacity**: Transparency control
5. **Apply Query**: Execute the query (shows statistics)

### Color Palette Panel
- **Raster 1 Colors**: Always available
  - Palette selection (viridis, magma, plasma, etc.)
  - Number of color classes (3-15)
  - Opacity slider
  - Reverse palette option
  - Color method (Continuous or Binned)
  
- **Raster 2 Colors**: Appears in Dual mode
  - Independent palette controls for second raster

### Map & Layers Panel
- **Basemap**: Choose background map
- **Show AOI boundary**: Overlay area of interest
- **Dual Raster Display** (Dual mode only):
  - Overlay: Show both rasters simultaneously
  - Intersection Only: Show only overlapping pixels
- **Analysis Layer Overlays**: Crop mask, season start/end

---

## Technical Implementation

### Raster Harmonization
When comparing rasters with different extents or resolutions:
- Automatic resampling to match Raster 1 geometry
- Bilinear interpolation for continuous data
- Notification when harmonization occurs

### Performance Optimizations
- **Automatic downsampling**: Large rasters (>2000 pixels) are aggregated for display
- **Memory efficiency**: Only selected bands are loaded into memory
- **Lazy evaluation**: Query computation triggered only on "Apply Query" button

### Query Evaluation Process
1. Load selected bands from both rasters
2. Harmonize geometries if needed
3. Extract pixel values as vectors
4. Parse query expression (replace Raster1/Raster2 with actual values)
5. Evaluate expression to create binary mask
6. Apply mask to create result raster
7. Calculate statistics (count, percentage)
8. Display on map with custom colors

---

## Example Workflows

### Workflow 1: Identify High Productivity + Low Water Use Areas
**Objective**: Find areas with high NPP but low water consumption

1. Set mode to "Conditional Query"
2. Load `NPP_annual.tif` as Raster 1
3. Load `AETI_annual.tif` as Raster 2
4. Enter query: `Raster1 >= 3000 & Raster2 <= 500`
5. Set Match Color to "green" (productive areas)
6. Click "Apply Query"
7. Review statistics and map

### Workflow 2: Compare Seasonal AETI Between Years
**Objective**: Visual comparison of water consumption across years

1. Set mode to "Dual Raster Comparison"
2. Load `AETI_2020_seasonal.tif` as Raster 1
3. Load `AETI_2021_seasonal.tif` as Raster 2
4. Select "Overlay" display mode
5. Adjust opacity for both layers (e.g., 0.7 and 0.5)
6. Use different palettes (e.g., viridis vs plasma)
7. Compare spatial patterns

### Workflow 3: Find Spatial Overlap Between Crop Mask and High NDVI
**Objective**: Identify crop areas with healthy vegetation

1. Set mode to "Dual Raster Comparison"
2. Load crop mask as Raster 1
3. Load NDVI raster as Raster 2
4. Select "Intersection Only" display mode
5. View areas where both datasets have values

---

## Limitations and Considerations

### Current Limitations
- Side-by-side display mode not yet implemented (uses overlay instead)
- Query expressions must use exact syntax (Raster1/Raster2)
- Maximum complexity: Two rasters per query
- Large rasters may take time to process

### Best Practices
- **Start simple**: Test queries with basic conditions first
- **Check statistics**: Review match percentage before interpreting results
- **Use appropriate colors**: High contrast for query results
- **Consider resolution**: Harmonization may affect precision
- **Memory awareness**: Close other applications when working with large rasters

### Performance Tips
- Use aggregated/seasonal rasters instead of daily time series
- Apply spatial subsets before comparison when possible
- Start with lower opacity to see both layers clearly
- Use the raster info table to verify data ranges before writing queries

---

## Future Enhancements

Planned features for future versions:
- [ ] Side-by-side map panels for true comparison view
- [ ] Query builder UI with dropdown operators
- [ ] Support for more than 2 rasters in queries
- [ ] Export query results as new GeoTIFF
- [ ] Statistical difference maps (Raster1 - Raster2)
- [ ] Histogram comparison plots
- [ ] Scatter plot of Raster1 vs Raster2 values
- [ ] Saved query templates
- [ ] Batch query execution

---

## Troubleshooting

**Problem**: "Could not load Raster 2"
- **Solution**: Ensure file exists in the selected folder

**Problem**: "Query error: object 'vals1' not found"
- **Solution**: Check query syntax - use "Raster1" and "Raster2" (case-sensitive)

**Problem**: "Rasters have different geometries. Harmonizing..."
- **Solution**: Normal notification - rasters are being resampled automatically

**Problem**: Query returns 0% matches
- **Solution**: Check value ranges in raster info table, adjust thresholds

**Problem**: Map is blank after applying query
- **Solution**: Adjust opacity slider, check if any pixels match the condition

**Problem**: Very slow performance
- **Solution**: Rasters may be too large - consider spatial subsetting first

---

## Contact & Support

For questions or issues with the enhanced visualization features:
- Check this documentation first
- Review example workflows
- Verify data ranges before creating queries
- Report bugs through the package issue tracker
