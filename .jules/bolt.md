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

## 2026-06-23 - [Reducing Persistent Cache Disk I/O and Vectorizing Date Offsets]
**Learning:** Calling `load_l3_extent_cache()` and `save_l3_extent_cache()` inside a loop of URLs / regions triggers redundant slow RDS read/write disk I/O. Passing an in-memory `cache` list to an internal helper and saving it exactly once at the end of the loop reduces disk operations to O(1). Additionally, R-level date arithmetic inside a loop can be fully vectorized upfront using vectorized subtraction and `pmax`/`pmin`.
**Action:** Use memory-resident lists to batch operations across iterative loops before writing changes to disk, and pre-compute date offsets/clamping as vectorized operations prior to loops.

## 2026-08-01 - [Vectorizing Class Masking and Avoiding Iterative ifel Loops]
**Learning:** Performing spatial masking or filtering of multiple crop/land-cover classes iteratively using R-level `for` loops that repeatedly call `terra::ifel()` on a `SpatRaster` causes severe memory allocation overhead and redundant read/write operations. Vectorizing class-membership checks using `%in%` or `terra::classify()` evaluates the entire condition in the C++ backend in a single optimized pass.
**Action:** Always prefer using `%in%` or `terra::classify()` to perform multi-class membership operations or conditional masking instead of R-level iterative `for` loops with `ifel()`.
