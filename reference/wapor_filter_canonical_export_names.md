# Canonical analysis export allow-list

FAO-56 Kc is used internally to compute ETc. Canonical raster and table
exports must not include `kc_*` products.

## Usage

``` r
wapor_filter_canonical_export_names(names)
```

## Arguments

- names:

  Character vector of file names, column names, or result keys.

## Value

The input names that are allowed in canonical exports.
