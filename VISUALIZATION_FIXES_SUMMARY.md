# Visualization Module Fixes - Summary

## Issues Fixed

### 1. Second Raster Selector Not Appearing (CRITICAL BUG)
**Problem:** The second raster selector was not appearing when switching to "Conditional Query" or "Dual Raster Comparison" modes.

**Root Cause:** The `conditionalPanel` JavaScript condition wasn't working correctly in Shiny modules due to namespace issues. The JavaScript condition `input['viz_mode'] == 'query'` doesn't work reliably when the input is namespaced within a module.

**Solution:** Replaced all `conditionalPanel` instances with server-side  conditional rendering using `uiOutput` + `renderUI`. This is the recommended best practice for Shiny modules.

### 2. Split-Screen Slider Feature Added (NEW FEATURE)
**What it does:** Allows you to drag a vertical slider across the map to compare two rasters side-by-side, similar to before/after image comparisons.

**How to use:**
1. Select "Dual Raster Comparison" mode
2. Load Raster 1 and Raster 2
3. In "Dual Raster Display" options, choose "Split Screen Slider"
4. Drag the white vertical line on the map to compare rasters

**Implementation:** Custom JavaScript using leaflet's clipping functionality to create a draggable divider that clips each raster layer.

## Files Modified
- `inst/shiny/mod_visualisation.R`: Complete refactor of conditional UI rendering

## Changes Made

### UI Changes
- Replaced 4 `conditionalPanel` blocks with `uiOutput` placeholders:
  - `raster2_ui`: Second raster selector
  - `query_panel_ui`: Conditional query controls
  - `raster2_palette_ui`: Raster 2 color palette
  - `dual_display_ui`: Dual raster display mode options

### Server Changes
- Added 4 new `renderUI` observers for dynamic UI generation
- Added "Split Screen Slider" (`swipe`) mode to dual display options
- Implemented JavaScript-based split-screen functionality using `htmlwidgets::onRender`
- Added interactive divider with mouse drag support
- Automatic raster clipping based on divider position

## Testing

### To Test the Fixes:

```powershell
# Launch the dashboard
$rexe = 'C:/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/Rscript.exe'
& $rexe --vanilla -e "devtools::load_all(); Rwapor::run_wapor()"
```

### Test Scenarios:

1. **Conditional Query Mode:**
   - Navigate to Visualization tab
   - Select "Conditional Query" from Visualization Mode
   - **VERIFY:** Second raster selector now appears
   - Load two different rasters
   - Enter query: `Raster1 > 100 & Raster2 < 50`
   - Click "Apply Query"
   - **VERIFY:** Results show matching/non-matching pixels

2. **Split-Screen Slider Mode:**
   - Select "Dual Raster Comparison" mode
   - Load two rasters showing the same area
   - **VERIFY:** Raster 2 selector appears
   - Under "Dual Raster Display", select "Split Screen Slider"
   - **VERIFY:** Map shows a draggable vertical divider
   - Drag the divider left/right
   - **VERIFY:** Left side shows Raster 1, right side shows Raster 2

3. **Dual Overlay Mode (existing functionality):**
   - Select "Dual Raster Comparison" mode
   - Choose "Overlay" display mode
   - **VERIFY:** Both rasters display with adjustable opacity

## Technical Notes

### Why Server-Side Rendering?
`conditionalPanel` uses JavaScript conditions that reference Shiny inputs. In modules, inputs are namespaced (e.g., `visualisation-viz_mode`), but the JavaScript condition string isn't always correctly interpreted. Server-side conditional rendering (`uiOutput`/`renderUI`) is more reliable because it evaluates conditions in R after reactive values update.

### Split-Screen Implementation
The slider uses CSS clipping (`clip: rect(...)`) to show only portions of each raster layer. The JavaScript code:
- Creates a draggable divider element
- Updates clip rectangles as the divider moves
- Re-clips on map zoom/pan events
- Uses `onRender` to inject custom behavior after leaflet map renders

## Known Limitations
1. Split-screen slider requires both rasters to have overlapping extents
2. If rasters have different CRS, they are automatically resampled (may take a moment)
3. Slider position resets to center (50%) when rasters change

## Next Steps
- Test with real WaPOR data
- Consider adding horizontal slider option
- Add opacity controls for split-screen mode
- Save/restore slider position in browser session

---

**Status:** ✅ READY FOR TESTING  
**Date:** April 1, 2026  
**R Version Used:** 4.5.3
