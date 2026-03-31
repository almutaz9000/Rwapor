---
name: rwapor-aggregation-logic
description: >
  Expert knowledge of Rwapor's metadata-driven aggregation, unit conversion, and
  scaling logic. USE WHEN: debugging seasonal aggregation, unit conversion issues,
  NPP values appear incorrect, temperature units wrong, understanding multipliers,
  weighted mean vs weighted sum, dekadal defaults, scale factors, or any question
  about how the package transforms raw data into physical units. CRITICAL for
  understanding why different variables aggregate differently and how units are
  automatically converted.
version: 1.0.0
---

# Rwapor Aggregation & Unit Conversion Logic

**Core Principle**: Rwapor uses **metadata-driven decision making** to determine how variables should be aggregated and converted. The variable's metadata (units, temporal resolution) determines the aggregation rule, multipliers, and output units.

---

## 1. The Metadata Foundation

### Key Metadata Files

**[R/metadata.R](R/metadata.R)**:
- `WAPOR3_VARS`: L1, L2, L3 variable metadata
- `AGERA5_VARS`: Climate variable metadata
- Each entry contains: `long_name`, `units`, `scale`

### Critical Function

```r
wapor_variable_metadata(variable)
# Returns: list(long_name = "...", units = "...", scale = ...)
```

### Scale Factor Handling

**IMPORTANT**: The `scale` factor in metadata is **reference only**.

```r
# WaPOR GeoTIFFs contain embedded scale/offset in raster metadata
# terra::rast() AUTOMATICALLY applies this when reading:
r <- terra::rast("/vsicurl/https://...L1-AETI-D.tif")
# If raw integer = 250, scale = 0.1 → terra returns 25.0 mm/day

# The package does NOT manually apply scale factors!
```

### Example Metadata

```r
WAPOR3_VARS[["L1-AETI-D"]]
# $long_name: "Actual EvapoTranspiration and Interception"
# $units: "mm/day"
# $scale: 0.1

WAPOR3_VARS[["L1-NPP-D"]]
# $long_name: "Net Primary Production"
# $units: "gC/m²/day"
# $scale: 0.001

AGERA5_VARS[["AGERA5-TMIN-E"]]
# $long_name: "Minimum Air Temperature (2m)"
# $units: "K"  ← Note: No temporal component!
# $scale: 1.0
```

---

## 2. Temporal Unit Extraction

### The Core Helper Function

**[R/utils.R](R/utils.R#L232-L246)**: `extract_temporal_unit()`

```r
extract_temporal_unit <- function(units) {
  # Looks for pattern: "/(day|dekad|month|year)$"
  # Returns: "day", "dekad", "month", "year", or NULL
  
  # Examples:
  extract_temporal_unit("mm/day")    → "day"
  extract_temporal_unit("gC/m²/day") → "day"
  extract_temporal_unit("K")         → NULL  (no temporal unit!)
  extract_temporal_unit("mm/month")  → "month"
}
```

**Why This Matters**: Variables without temporal units (like temperature in "K") are treated as **intensive properties** that should be averaged, not summed.

---

## 3. Seasonal Aggregation Rule Decision

### The Decision Function

**[R/utils.R](R/utils.R#L276-L286)**: `get_seasonal_aggregation_rule()`

```r
get_seasonal_aggregation_rule <- function(variable) {
  parts <- strsplit(variable, "-", fixed = TRUE)[[1]]
  tres <- parts[length(parts)]  # "D", "E", "M", "A"
  
  meta <- wapor_variable_metadata(variable)
  unit_time <- extract_temporal_unit(meta$units)

  # KEY DECISION:
  # If temporal resolution is D or E, but NO temporal unit in metadata
  if (tres %in% c("D", "E") && is.null(unit_time)) {
    return("weighted_mean")  # For temperature, RSM, etc.
  }

  "weighted_sum"  # Default for flux variables
}
```

### Decision Table

| Variable | Units | Suffix | `unit_time` | Rule | Reason |
|----------|-------|--------|-------------|------|--------|
| AGERA5-TMIN-E | K | E | NULL | **weighted_mean** | Intensity - should be averaged |
| AGERA5-TMAX-E | K | E | NULL | **weighted_mean** | Intensity - should be averaged |
| L1-AETI-D | mm/day | D | "day" | **weighted_sum** | Flux - should be accumulated |
| L1-NPP-D | gC/m²/day | D | "day" | **weighted_sum** | Flux - should be accumulated |
| L1-PCP-E | mm/day | E | "day" | **weighted_sum** | Flux - should be accumulated |
| L3-RSM-D | % | D | NULL | **weighted_mean** | Ratio - should be averaged |
| L2-AETI-M | mm/month | M | "month" | **weighted_sum** | Already monthly total |

### How It's Applied

**[R/wapor_map.R](R/wapor_map.R#L246-L250)**: Seasonal aggregation

```r
seasonal_sum <- if (identical(aggregation_rule, "weighted_mean")) {
  # For temperature: value / weight
  terra::ifel(running_weight > 0, running_value / running_weight, NA)
} else {
  # For flux: sum of weighted values
  terra::mask(running_value, valid_count, maskvalue = 0)
}
```

---

## 4. Seasonal Multiplier Calculation

### The Multiplier Function

**[R/utils.R](R/utils.R#L297-L319)**: `get_seasonal_multiplier_values()`

```r
get_seasonal_multiplier_values <- function(variable, plan_rows, aggregation_rule) {
  # For weighted_mean (temperature, RSM), use overlap_days as weights
  if (identical(aggregation_rule, "weighted_mean")) {
    return(plan_rows$overlap_days)  # Just for weighting
  }

  # For flux variables, check if unit conversion needed
  parts <- strsplit(variable, "-", fixed = TRUE)[[1]]
  tres <- parts[length(parts)]
  meta <- wapor_variable_metadata(variable)
  unit_time <- extract_temporal_unit(meta$units)

  # If dekadal/daily with "/day" units → multiply by days
  if (tres %in% c("D", "E") && identical(unit_time, "day")) {
    return(plan_rows$overlap_days)  # Convert day → period
  }

  plan_rows$weight  # Default = 1 for monthly data
}
```

### Multiplier Examples

**Dekadal AETI (L1-AETI-D)** - units: "mm/day"
```
Dekad 1 (Jan 1-10):  2.5 mm/day × 10 days = 25 mm
Dekad 2 (Jan 11-20): 2.8 mm/day × 10 days = 28 mm
Dekad 3 (Jan 21-31): 3.0 mm/day × 11 days = 33 mm
Seasonal sum: 25 + 28 + 33 = 86 mm
```

**Daily Temperature (AGERA5-TMIN-E)** - units: "K"
```
Day 1: 280 K × 1 (weight) = 280
Day 2: 285 K × 1 (weight) = 285
Day 3: 283 K × 1 (weight) = 283
Seasonal mean: (280 + 285 + 283) / (1 + 1 + 1) = 282.67 K
```

**Monthly NPP (L2-NPP-M)** - units: "gC/m²/month"
```
January:  45 gC/m²/month × 1 = 45
February: 50 gC/m²/month × 1 = 50
March:    55 gC/m²/month × 1 = 55
Seasonal sum: 45 + 50 + 55 = 150 gC/m²
```

---

## 5. Default Unit Conversion Logic

### The Default Resolver

**[R/utils.R](R/utils.R#L250-L267)**: `resolve_output_unit_conversion()`

```r
resolve_output_unit_conversion <- function(variable, unit_conversion = NULL) {
  # If user explicitly provides a conversion, use it
  if (!is.null(unit_conversion)) {
    return(unit_conversion)
  }

  # Extract temporal resolution
  parts <- strsplit(variable, "-", fixed = TRUE)[[1]]
  tres <- parts[length(parts)]
  
  meta <- wapor_variable_metadata(variable)
  unit_time <- extract_temporal_unit(meta$units)

  # KEY DEFAULT: Dekadal with "/day" → convert to dekadal totals
  if (identical(tres, "D") && identical(unit_time, "day")) {
    return("dekad")
  }

  "none"  # No conversion for other cases
}
```

### Default Behavior Table

| Variable | Metadata Units | Default Conversion | Output Units | Rationale |
|----------|----------------|-------------------|--------------|-----------|
| L1-AETI-D | mm/day | **"dekad"** | mm/dekad | Files store daily rates, users want dekadal totals |
| L1-NPP-D | gC/m²/day | **"dekad"** | gC/m²/dekad | Files store daily rates, users want dekadal totals |
| L3-AETI-E | mm/day | **"none"** | mm/day | Daily data, keep as rates |
| L2-AETI-M | mm/month | **"none"** | mm/month | Already monthly totals |
| AGERA5-TMIN-E | K | **"none"** | degC (after temp conversion) | No temporal conversion |

### User Override Example

```r
# Default: dekadal totals
wapor_map(variable = "L1-AETI-D", ...)
# Output: mm/dekad (values like 25, 28, 33)

# Override: daily rates
wapor_map(variable = "L1-AETI-D", unit_conversion = "day", ...)
# Output: mm/day (values like 2.5, 2.8, 3.0)
```

---

## 6. Temperature Conversion (New in v0.9.2)

### Automatic Kelvin to Celsius

**[R/unit_convertor.R](R/unit_convertor.R)**: `wapor_convert_temperature()`

```r
wapor_convert_temperature <- function(r, variable) {
  if (!grepl("^AGERA5-(TMIN|TMAX)-", variable)) {
    return(r)  # Not a temperature variable
  }
  
  # Convert K to °C: subtract 273.15
  r <- r - 273.15
  return(r)
}
```

### Integration Points

1. **[R/wapor_map.R](R/wapor_map.R#L372)**: After unit conversion, before saving
2. **[R/wapor_ts.R](R/wapor_ts.R#L365)**: After cropping, before zonal stats
3. **[R/seasonal_download.R](R/seasonal_download.R#L128)**: After cropping seasonal data

### Metadata Updates

**[R/utils.R](R/utils.R#L847-L850)**: Units changed from "K" to "degC"

```r
# In assign_raster_metadata():
if (grepl("^AGERA5-(TMIN|TMAX)-", variable)) {
  res_units <- sub("^K$", "degC", res_units)
}
```

### Example Conversion

```r
# Raw raster value from source: 298.15 K
# After wapor_convert_temperature(): 25.0 °C
# Metadata units: "degC"

# Seasonal mean temperature
tmax_seasonal <- wapor_map(
  variable = "AGERA5-TMAX-E",
  seasonal = TRUE,
  ...
)
# Output: weighted mean in °C (e.g., 28.5 °C for summer)
```

---

## 7. Common Pitfalls and Solutions

### Pitfall 1: "NPP values are too low"

**Problem**: User expects 450 gC/m² for a growing season but sees 4.5 gC/m²/day.

**Diagnosis**:
```r
# Check if default conversion was applied
wapor_map(variable = "L1-NPP-D", ...)

# Default converts to dekad (4.5 → 45 per dekad)
# For seasonal: sum of all dekads (e.g., 9 dekads × 45 = 405 gC/m²)
```

**Solution**: Use `seasonal = TRUE` for automatic aggregation:
```r
wapor_map(variable = "L1-NPP-D", seasonal = TRUE, ...)
# Output: ~400-600 gC/m² for 90-day season
```

### Pitfall 2: "Temperature is in Kelvin, not Celsius"

**Problem**: In versions < 0.9.2, temperature was not converted.

**Solution**: Update to v0.9.2+. Conversion is now automatic.

### Pitfall 3: "Seasonal precipitation is much lower than expected"

**Diagnosis**: Check if variable has multiple temporal resolutions.

```r
# If plan uses daily (E) instead of dekadal (D):
wapor_temporal_codes("L1-PCP-D")  # Returns c("A", "M", "D", "E")

# plan_wapor_time_slices() might prefer daily if available
# Each daily value × 1 day multiplier → correct sum
```

**Solution**: Trust the plan! The package optimally selects resolutions.

### Pitfall 4: "Why are my seasonal temperature values so cold/hot?"

**Problem**: Using sum instead of mean for temperature.

**Diagnosis**: Check aggregation rule:
```r
get_seasonal_aggregation_rule("AGERA5-TMIN-E")
# Should return "weighted_mean"
```

**If returns "weighted_sum"**: Metadata might be corrupt. Check:
```r
extract_temporal_unit(AGERA5_VARS[["AGERA5-TMIN-E"]]$units)
# Should return NULL (since units = "K", no "/day")
```

---

## 8. Key Functions Quick Reference

### Metadata & Decision Making

| Function | File | Purpose |
|----------|------|---------|
| `wapor_variable_metadata()` | metadata.R | Get units, long_name, scale for variable |
| `extract_temporal_unit()` | utils.R | Parse "day", "month", etc. from units |
| `get_seasonal_aggregation_rule()` | utils.R | Decide: weighted_mean or weighted_sum |
| `resolve_output_unit_conversion()` | utils.R | Set default unit conversion |
| `get_seasonal_output_units()` | utils.R | Determine output units after aggregation |

### Multipliers & Conversion

| Function | File | Purpose |
|----------|------|---------|
| `get_seasonal_multiplier_values()` | utils.R | Compute per-layer multipliers for seasonal |
| `get_analysis_layer_multipliers()` | utils.R | Compute multipliers for analysis mode |
| `wapor_convert_raster()` | unit_convertor.R | Apply temporal unit conversion |
| `wapor_convert_temperature()` | unit_convertor.R | Convert K to °C |
| `wapor_convert_units()` | unit_convertor.R | Convert dataframe/time series units |

### Metadata Assignment

| Function | File | Purpose |
|----------|------|---------|
| `assign_raster_metadata()` | utils.R | Set units, long_name on output rasters |

---

## 9. Debugging Checklist

When debugging aggregation or unit issues:

1. **Check variable metadata**:
   ```r
   meta <- wapor_variable_metadata(variable)
   print(meta)
   ```

2. **Check temporal unit extraction**:
   ```r
   unit_time <- extract_temporal_unit(meta$units)
   print(unit_time)  # Should be "day", "month", or NULL
   ```

3. **Check aggregation rule**:
   ```r
   rule <- get_seasonal_aggregation_rule(variable)
   print(rule)  # Should be "weighted_mean" or "weighted_sum"
   ```

4. **Check default unit conversion**:
   ```r
   conv <- resolve_output_unit_conversion(variable, NULL)
   print(conv)  # Should be "dekad", "none", etc.
   ```

5. **Check multipliers in seasonal plan**:
   ```r
   plan <- wapor_plan_time_slices(start, end, avail = c("D", "E"))
   mults <- get_seasonal_multiplier_values(variable, plan, rule)
   print(data.frame(period = plan$period_id, multiplier = mults))
   ```

6. **Verify terra is applying scale automatically**:
   ```r
   # Load raw raster
   r <- terra::rast(url)
   print(range(terra::values(r), na.rm = TRUE))
   # Values should be in physical units already (e.g., 0-5 mm/day)
   # NOT raw integers (e.g., 0-50)
   ```

---

## 10. When to Use This Skill

**Invoke this skill when**:
- Debugging why seasonal aggregation produces unexpected values
- Explaining why temperature uses mean while NPP uses sum
- Understanding dekadal default conversions
- Investigating NPP scaling issues
- Adding new variables with different aggregation needs
- Modifying temporal unit conversion logic
- Explaining how multipliers are computed
- Troubleshooting metadata-related bugs

**This skill is CRITICAL** for anyone modifying:
- `R/utils.R` (aggregation logic)
- `R/seasonal_download.R` (seasonal mode)
- `R/wapor_map.R` (download and aggregate)
- `R/wapor_ts.R` (time series extraction)
- `R/unit_convertor.R` (conversions)
- `R/metadata.R` (variable definitions)

**Example trigger phrases**:
- "Why is my seasonal ET lower than expected?"
- "How does the package decide to use mean vs sum?"
- "Why are dekadal values automatically converted?"
- "Explain the multipliers in seasonal mode"
- "How does NPP scaling work?"
- "Temperature conversion from Kelvin"
- "What determines the output units?"
