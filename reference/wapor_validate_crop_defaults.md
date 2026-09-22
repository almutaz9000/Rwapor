# Validate Crop Default Parameters

Checks that a crop defaults data.frame has valid structure and values.

## Usage

``` r
wapor_validate_crop_defaults(df)
```

## Arguments

- df:

  A data.frame with crop parameters (same columns as FAO_CROP_DEFAULTS).

## Value

TRUE invisibly if valid; stops with an error otherwise.

## Examples

``` r
if (FALSE) { # \dontrun{
wapor_validate_crop_defaults(FAO_CROP_DEFAULTS)
} # }
```
