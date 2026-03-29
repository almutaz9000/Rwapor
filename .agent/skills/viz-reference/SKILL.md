---
name: viz-reference
description: >
  R and Python visualization patterns for WaPOR/geospatial outputs. Load when creating
  maps (tmap, ggplot2, matplotlib, cartopy), time series plots, interactive Leaflet/folium
  dashboards, or publication-quality figures from rasters, vectors, AETI, NDVI, or WP results.
---

# Viz Reference — WaPOR Outputs

## Language Selection
| Output | R | Python |
|---|---|---|
| Static map | `tmap`, `ggplot2 + tidyterra` | `matplotlib + rasterio`, `cartopy` |
| Interactive | `leaflet`, `mapview` | `folium`, `geemap`, `plotly` |
| Shiny map | `leaflet + renderLeaflet` | — |
| Time series | `ggplot2`, `dygraphs` | `plotly`, `hvplot` |
| Export PNG/PDF | `tmap_save()`, `ggsave()` | `plt.savefig()` |
| Export HTML | `tmap_save(filename=".html")` | `folium.save()`, `plotly.write_html()` |

## R Patterns

### Raster map (tmap)
```r
library(tmap); library(terra)
r <- rast("aeti_2022.tif")
tm_shape(r) +
  tm_raster(col="AETI", palette="Blues", style="quantile", n=7, title="AETI (mm/dekad)") +
  tm_compass(position=c("right","top")) + tm_scale_bar(position=c("left","bottom")) +
  tm_layout(main.title="WaPOR AETI 2022", legend.outside=TRUE, frame=FALSE)
tmap_save(filename="aeti_map.png", width=10, height=8, dpi=300)
```

### Leaflet (Shiny-ready)
```r
pal <- colorNumeric("YlOrRd", values(r), na.color="transparent")
leaflet() |> addTiles() |>
  addRasterImage(raster::raster(r), colors=pal, opacity=0.8) |>
  addLegend(pal=pal, values=values(r), title="AETI (mm)", position="bottomright")
```

### Time series (ggplot2)
```r
ts_data |> ggplot(aes(x=date, y=value, color=variable)) +
  geom_line(linewidth=0.8) + geom_point(size=1.5) +
  scale_x_date(date_breaks="3 months", date_labels="%b %Y") +
  labs(title="WaPOR ET Time Series", x=NULL, y="mm/dekad") +
  theme_minimal(base_size=12) + theme(legend.position="bottom")
ggsave("ts_plot.png", width=10, height=5, dpi=300)
```

## Python Patterns

### Static map (matplotlib)
```python
import rasterio, matplotlib.pyplot as plt, numpy as np
with rasterio.open("aeti_2022.tif") as src:
    data = src.read(1).astype(float)
    data[data == src.nodata] = np.nan
    extent = [src.bounds.left, src.bounds.right, src.bounds.bottom, src.bounds.top]
fig, ax = plt.subplots(figsize=(10, 8))
im = ax.imshow(data, cmap="Blues", extent=extent, origin="upper")
plt.colorbar(im, ax=ax, label="AETI (mm/dekad)", shrink=0.7)
plt.savefig("aeti_map.png", dpi=300, bbox_inches="tight")
```

### Interactive (folium)
```python
import folium, branca.colormap as cm
colormap = cm.LinearColormap(["#ffffcc","#41b6c4","#0c2c84"], vmin=0, vmax=100, caption="AETI (mm)")
m = folium.Map(location=[lat, lon], zoom_start=8, tiles="CartoDB positron")
colormap.add_to(m); m.save("aeti_map.html")
```

## WaPOR Color Palettes
```r
aeti_pal  <- c("#f7fbff","#c6dbef","#6baed6","#2171b5","#08306b")   # blue
ndvi_pal  <- c("#d73027","#fee08b","#1a9850")                         # red-yellow-green
cwp_pal   <- c("#d73027","#fc8d59","#fee090","#91cf60","#1a9850")     # diverging
lc_pal    <- c(Cropland="#a8d08d", Irrigated="#2196f3", Bare="#d4a36a", Urban="#ff5252", Water="#00bcd4")
```

## Publication Standards
- DPI: 300 print / 150 web
- Always include: north arrow, scale bar, legend, title, data source note
- CRS: state projection in caption if not WGS84
- Color accessibility: ColorBrewer palettes; avoid red-green
