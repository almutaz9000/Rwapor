## 2025-05-15 - [Optimization of Zonal Statistics in wapor_ts]
**Learning:** In R geospatial workflows using `exactextractr`, calling `exact_extract()` inside a loop for each layer of a `SpatRaster` is highly inefficient because the polygon-raster intersection (coverage fraction calculation) is recomputed for every layer. Passing the entire multi-layer stack to `exact_extract()` once and then performing matrix operations on the result is significantly faster.
**Action:** Always prefer passing multi-layer stacks to `exact_extract()` or `terra::global()` and use matrix multiplication for weighted aggregations instead of per-layer loops.

## 2025-05-20 - [Vectorized Reshaping of Zonal Statistics]
**Learning:** Reshaping wide zonal statistics (one column per layer) into long format using iterative `lapply`/`rbind` loops is a major bottleneck in R when processing many polygons and layers. Matrix-based flattening (`as.vector(as.matrix(df))`) combined with `rep` for metadata provides a massive speedup by leveraging R's internal vectorization.
**Action:** Use matrix flattening and `rep` instead of `rbind` loops when converting multi-layer extraction results to long-format data frames.
