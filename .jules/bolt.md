## 2025-05-15 - [Optimization of Zonal Statistics in wapor_ts]
**Learning:** In R geospatial workflows using `exactextractr`, calling `exact_extract()` inside a loop for each layer of a `SpatRaster` is highly inefficient because the polygon-raster intersection (coverage fraction calculation) is recomputed for every layer. Passing the entire multi-layer stack to `exact_extract()` once and then performing matrix operations on the result is significantly faster.
**Action:** Always prefer passing multi-layer stacks to `exact_extract()` or `terra::global()` and use matrix multiplication for weighted aggregations instead of per-layer loops.

## 2024-05-16 - [Vectorization of Zonal Stats Reshaping]
**Learning:** Reshaping large zonal statistics from wide to long format using iterative `rbind` or `lapply` is an $O(N^2)$ operation in R due to memory reallocation. Converting the wide result into a matrix and then to a vector allows for a fully vectorized $O(N)$ transformation.
**Action:** Use matrix-to-vector flattening and index-based metadata replication instead of per-layer loops for data reshaping.

## 2024-05-16 - [Specialized terra::sum for Aggregation]
**Learning:** `terra::sum()` is significantly faster than `terra::app(..., fun="sum")` because it bypasses R's generic application layer and uses a specialized C++ implementation for layer summation.
**Action:** Prefer specialized `terra` functions (sum, mean, min, max) over `app()` whenever possible.

## 2025-05-17 - [Vectorized Seasonal Aggregation]
**Learning:** In seasonal workflows, R-level loops that iteratively update rasters using `terra::ifel()` or `+` are slow because they trigger multiple read/write passes and overhead for each layer. Vectorizing the operation by multiplying the entire `SpatRaster` stack by a numeric weight vector and then using `terra::sum(..., na.rm=TRUE)` executes the entire operation in the C++ backend in a single pass.
**Action:** Replace iterative raster accumulation loops with stack-based vectorized operations.

## 2025-05-18 - [Optimization of Season Profile Table Building]
**Learning:** Extracting pixel values from multiple rasters into R vectors and creating a massive data frame for aggregation (one row per pixel) is extremely slow and memory-intensive. `terra::crosstab(..., long = TRUE)` provides the same result by counting unique value combinations in the C++ backend, which is orders of magnitude faster and avoids memory exhaustion for large rasters.
**Action:** Use `terra::crosstab(long = TRUE)` to build unique combination tables from multiple rasters instead of `terra::values()` followed by R-level aggregation.
