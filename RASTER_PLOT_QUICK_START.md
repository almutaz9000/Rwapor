# Quick Start: Enhanced Raster Time Series Plotting

## What Changed?

The "Plot Raster Time Series" button now opens an intelligent selection dialog instead of requiring you to navigate to other tabs first.

## How to Use

### 1. Click "Plot Raster Time Series" Button
Location: Sidebar → "Enhanced Analysis" panel

### 2. Selection Modal Opens
You'll see three sections:

#### **Select Farms**
- ☑ "Select All Farms" - Quick toggle to select/deselect all
- Individual checkboxes for each farm with saved rasters
- **Tip**: For comparison plots, select 2-5 farms. For overview, use "Select All"

#### **Select Variables**  
- Checkboxes for each available variable (e.g., L1-AETI-D, L1-NPP-D)
- Can select multiple to create faceted plots
- **Tip**: Select 1-2 variables for best readability

#### **Date Range**
- Start and end date pickers
- Pre-filled with full available range
- **Tip**: Leave as-is to plot all data, or narrow for specific periods

### 3. Click "Generate Plot"
- Validates your selection (need at least 1 farm and 1 variable)
- Creates the plot instantly
- Opens in larger modal window

### 4. View & Download
- **Plot Display**: Zoomable, high-quality visualization
- **Download Button**: Exports as PNG (300 DPI, publication-ready)
- **Close Button**: Returns to selection modal

## Plot Types You'll See

### Single Farm, Single Variable
- Blue line showing mean value over time
- Light blue ribbon showing ±1 standard deviation
- Subtitle includes threshold info (e.g., "5% threshold, 95% pixels retained")

### Multiple Farms, Single Variable
- Each farm gets a different colored line
- Legend on right shows farm IDs
- Easy comparison of farm performance

### Multiple Variables (Faceted)
- One panel per variable (stacked vertically)
- Each panel has independent Y-axis scale
- Colored by farm if multiple farms selected

### Multiple Farms + Multiple Variables
- Combines both: faceted panels + colored lines
- Best for comprehensive comparison
- Auto-adjusts height (300px per variable)

## Tips & Tricks

### ✅ Best Practices
- **Start small**: Try 1-2 farms and 1 variable first
- **Compare similar**: Select farms with same crop type for meaningful comparison
- **Use date range**: Zoom in on specific seasons or events
- **Download plots**: High-res PNGs perfect for reports

### ⚠️ Limitations
- Maximum 100 combinations (farms × variables) to prevent performance issues
- Very large selections might take a few seconds to render
- Legend hidden automatically if >10 farms (to prevent clutter)

### 🔍 Troubleshooting
**"No saved rasters found"**  
→ Run monitoring with "Save rasters" checkbox enabled first

**"Please select at least one farm"**  
→ Click some farm checkboxes before generating plot

**"Too many combinations"**  
→ Reduce number of selected farms or variables

## Example Workflows

### Workflow 1: Farm Performance Comparison
1. Select 3-5 farms of same crop type
2. Select "L1-AETI-D" (actual evapotranspiration)
3. Leave full date range
4. Generate plot
5. **Result**: See which farms have higher water use

### Workflow 2: Variable Relationships
1. Select single farm
2. Select "L1-AETI-D" and "L1-NPP-D"
3. Generate plot
4. **Result**: Faceted view showing AETI vs NPP trends

### Workflow 3: Seasonal Analysis
1. Select all farms
2. Select "L1-AETI-D"
3. Set date range to one season (e.g., Jan-Apr)
4. Generate plot
5. **Result**: Overlay of all farms during growing season

### Workflow 4: Anomaly Investigation
1. Select farms with suspected issues
2. Select relevant variables
3. Set date range around anomaly period
4. Generate plot
5. **Result**: Zoomed-in view of problem timeframe

## Keyboard Shortcuts

- **Enter**: Generate plot (when selection modal is open)
- **Escape**: Close modal
- **Tab**: Navigate between controls

## What the Plot Shows

### Mean Line
- Primary trend line (thick line)
- Calculated from all pixels in clipped raster
- Affected by threshold setting

### Standard Deviation Ribbon (single farm only)
- Shows variability within farm
- ±1 std around mean
- Wider ribbon = more heterogeneous

### Min-Max Ribbon (single farm only)
- Extreme values observed
- Light shading
- Helps identify outliers

### Threshold Info (subtitle)
- Shows % threshold used
- Shows % pixels retained after filtering
- Example: "5% threshold (95% pixels retained)"

## Download Options

**Filename Format**: `raster_timeseries_YYYYMMDD.png`
**Resolution**: 300 DPI (publication quality)
**Dimensions**: 12 inches wide × variable height
**Format**: PNG with transparent background

---

**Need More Help?** See [RASTER_PLOT_ENHANCEMENT.md](RASTER_PLOT_ENHANCEMENT.md) for technical details.
