# Split a multi-band wapor_map() stack into one file per date

`wapor_map(separate_files = FALSE)` (the default) writes one multi-band
GeoTIFF named `<product>.<first date>_<last date>.tif`, with one band
per time step named by its start date. Local analysis
(`data_source = "local"`) needs one file per time step. This writes
`<product>.<date>.tif` next to the stack (or into `folder`), the same
layout as `wapor_map(separate_files = TRUE)`, and skips files that
already exist.

## Usage

``` r
wapor_unstack_map(
  path,
  folder = dirname(path),
  overwrite = FALSE,
  remove_stack = FALSE
)
```

## Arguments

- path:

  Character. Path to the multi-band GeoTIFF.

- folder:

  Character. Output folder. Defaults to the stack's folder.

- overwrite:

  Logical. Overwrite existing per-date files. Default `FALSE`.

- remove_stack:

  Logical. Delete the stack after a successful split, so local readers
  do not see both. Default `FALSE`.

## Value

Character vector of per-date file paths, invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
stack <- wapor_map(c(35, 33, 36, 34), "L1-AETI-D",
                   c("2023-01-01", "2023-03-31"), folder = "wapor_data")
wapor_unstack_map(stack)
} # }
```
