# Dashboard Seasonal Summary Semantics

## Goal

Expose the seasonal `fun` contract in the Shiny dashboard and prevent
semantically invalid seasonal sums for non-accumulative WaPOR and AgERA5
products.

## Product semantics

The package defines a variable as seasonally summable when its existing
variable-aware aggregation rule is `weighted_sum`. Products whose existing
rule is `weighted_mean` are states or rates and cannot be explicitly summed.
This includes relative/root-zone soil moisture, temperature, humidity, wind,
and comparable products.

- `fun = NULL` retains the existing variable-aware default.
- `fun = "sum"` is accepted only for seasonally summable variables and retains
  overlap-weighted physical-total semantics.
- `mean`, `std`, `min`, `max`, and `median` are available to all variables and
  treat every overlapping planned source raster once.

The package will expose this classification through a public helper so the
dashboard and scripts use the same rule.

## Dashboard behavior

The Download and API Time Series modules display a Seasonal summary selector
only for seasonal work. It offers Automatic (variable-aware), Weighted sum,
Mean, Standard deviation, Minimum, Maximum, and Median.

When one or more selected variables are not seasonally summable, Weighted sum
is unavailable and the dashboard identifies the affected variables. The
remaining options are still applied independently to each variable.

The selector explains that sum uses temporal-overlap weights while every other
summary gives each overlapping source raster equal weight. A persistent mixed
temporal-resolution notice explains that annual, monthly, and dekadal rasters
are each one observation for non-sum functions.

Variables sharing a temporal resolution are submitted together in one
dashboard run, but their values are never combined: each variable receives its
own `wapor_map()` or `wapor_ts()` call and output.

## Data flow

1. The dashboard derives available summary choices from all selected variables.
2. It displays semantic guidance before the run starts.
3. It forwards `fun = NULL` for Automatic or the selected explicit function to
   every seasonal map/time-series call.
4. Backend validation remains authoritative, including direct script calls.

## Verification

Tests will cover the backend no-sum guard, dashboard control rendering and
function forwarding, mixed-resolution/non-summable guidance, package loading,
and existing Shiny module construction.
