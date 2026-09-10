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

## 2026-06-22 - [Vectorized Date Parsing and Metadata Extraction]
**Learning:** In R, processing large character vectors with row-wise functions like `vapply(..., strsplit)` or `lapply(..., wapor_date_info)` is a major bottleneck. Vectorizing these operations using `sub()` for regex extraction and `matrix(unlist(...), ncol=N, byrow=TRUE)` for batch part extraction provides significant speedups.
**Action:** Always prefer vectorized string functions and matrix-based unlisting over iterative R-level loops for metadata parsing.

## 2026-06-23 - [O(1) Zonal Summary Lookups in Multi-Season Comparison]
**Learning:** In multi-season comparison routines (`.compare_seasons_by_class`), evaluating per-class adequacy using `terra::ifel(mask == cls, 1L, NA)` inside nested loops triggers repeated SpatRaster allocation and C++ conditional evaluations for every crop class across seasons. Pre-computing per-class zonal means using a single `terra::zonal(adequacy, mask, fun="mean")` call per season allows O(1) hash/named-vector lookups during table row assembly.
**Action:** Replace iterative per-class `terra::ifel` conditional raster masks with upfront `terra::zonal()` calls whenever calculating class-level summary metrics.
