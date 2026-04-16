# Visualization Tab - Quick Reference Card

## 🎯 Three Modes Available

### 🔵 Single Raster
**Use when:** Viewing one dataset
**Controls:** Standard palette, opacity, color method

---

### 🟣 Dual Raster Comparison  
**Use when:** Comparing two datasets spatially

**Steps:**
1. Select Mode: "Dual Raster Comparison"
2. Choose Raster 1 and Raster 2
3. Select display mode:
   - **Overlay**: See both rasters (adjust opacity)
   - **Intersection Only**: Show only overlapping pixels
4. Customize colors independently for each raster

**Example Use Cases:**
- Compare AETI between years
- Overlay precipitation and temperature
- Validate crop mask against NDVI

---

### 🟢 Conditional Query
**Use when:** Finding pixels meeting specific criteria

**Steps:**
1. Select Mode: "Conditional Query"
2. Choose Raster 1 and Raster 2
3. Write query expression in text box
4. Select match/no-match colors
5. Click "Apply Query"
6. Review statistics

**Query Syntax:**
```
Raster1 [operator] [value] [&|] Raster2 [operator] [value]
```

**Operators:**
- `>=` greater than or equal
- `<=` less than or equal  
- `>` greater than
- `<` less than
- `==` equal to
- `!=` not equal
- `&` AND (both conditions must be true)
- `|` OR (either condition can be true)

**Example Queries:**
```
# High productivity, low water use
Raster1 >= 150 & Raster2 <= 20

# Either very high or very low
Raster1 > 300 | Raster1 < 50

# Within a range
Raster1 >= 100 & Raster1 <= 200 & Raster2 > 30
```

---

## ⚡ Quick Tips

### Before Writing Queries:
1. Check raster value ranges in the info table (bottom of map)
2. Use realistic thresholds based on your data
3. Start simple (one condition) then add complexity

### Performance:
- Large rasters auto-downsample for display
- Different extents/resolutions auto-harmonize
- Close unused modes to free memory

### Troubleshooting:
- **"Query error"**: Check syntax (case-sensitive: Raster1, Raster2)
- **"0% matches"**: Review thresholds in info table
- **Blank map**: Increase opacity or check layer visibility
- **Slow performance**: Rasters may be large, wait for processing

---

## 📊 Reading the Info Table

**Single Mode:**
Shows: resolution, bands, min/max/mean for selected raster

**Dual Mode:**  
Shows: side-by-side comparison of both rasters

**Query Mode:**
Shows: query expression, match count, percentage

---

## 🎨 Color Strategy

**Dual Mode:**
- Raster 1: Use cool colors (blues, viridis)
- Raster 2: Use warm colors (reds, magma)
- Adjust opacity so both visible

**Query Mode:**
- Match: Bright color (red, green, blue)
- No-match: Neutral (gray, light gray)
- High opacity (0.7-0.9) for clear distinction

---

## 💡 Real-World Examples

### Example 1: Drought Detection
```
Query: Raster1 <= 200 & Raster2 >= 800
(Low rainfall AND high evapotranspiration)
Match Color: Red (drought-stressed areas)
```

### Example 2: Optimal Growing Conditions
```
Query: Raster1 >= 400 & Raster1 <= 800 & Raster2 >= 0.6
(Moderate water + good vegetation)
Match Color: Green (ideal zones)
```

### Example 3: Irrigation Verification
```
Mode: Dual Comparison
Raster 1: Irrigation map (1=irrigated)
Raster 2: AETI (high values)
Display: Intersection Only
(Verify irrigated areas show high water use)
```

---

## 🚀 Getting Started

1. Launch Rwapor Shiny app:
   ```r
   Rwapor::run_wapor()
   ```

2. Navigate to "Visualisation" tab

3. Select visualization mode at top of sidebar

4. Follow mode-specific controls

5. Review results in info table

---

## 📖 Full Documentation

See `inst/shiny/VISUALIZATION_FEATURES.md` for:
- Detailed workflows
- Technical implementation
- Troubleshooting guide
- Future enhancements
