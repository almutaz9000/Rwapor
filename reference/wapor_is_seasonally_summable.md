# Check Whether a Variable Can Be Seasonally Summed

A seasonal sum is meaningful only for products whose source values
represent accumulations. State and rate products (for example root-zone
soil moisture) use the package's weighted-mean seasonal rule and cannot
be explicitly summed.

## Usage

``` r
wapor_is_seasonally_summable(variable)
```

## Arguments

- variable:

  Character vector of WaPOR or AgERA5 variable codes.

## Value

A logical vector, `TRUE` for variables that can be seasonally summed.
