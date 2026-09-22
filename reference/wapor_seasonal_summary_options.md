# Get Available Seasonal Summary Options

Returns the seasonal summary choices that are valid for every supplied
variable. A weighted sum is available only when all variables represent
accumulations; equal-step summaries are always available.

## Usage

``` r
wapor_seasonal_summary_options(variable)
```

## Arguments

- variable:

  Character vector of WaPOR or AgERA5 variable codes.

## Value

A list containing named `choices` suitable for a user interface and
`non_summable`, the supplied variables that cannot be seasonally summed.
