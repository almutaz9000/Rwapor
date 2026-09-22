# Calculate per-pixel temporal linear trend

Calculate per-pixel temporal linear trend

## Usage

``` r
linear_trend(stack, times = NULL)
```

## Arguments

- stack:

  Multi-layer SpatRaster ordered in time.

- times:

  Optional numeric time values, defaulting to layer sequence.

## Value

A list containing SpatRaster layers `slope`, `intercept`, and `r2`.
