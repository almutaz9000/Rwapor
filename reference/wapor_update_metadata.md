# Update WaPOR Metadata Cache from the Live API

Re-fetches dataset metadata from the FAO GISMGR API and writes JSON
cache files to `dest`. This is intended to be run periodically to keep
the local cache up to date when FAO adds new datasets.

## Usage

``` r
wapor_update_metadata(level = "all", dest = NULL)
```

## Arguments

- level:

  Character. One of `"L1"`, `"L2"`, `"L3"`, or `"all"`. Defaults to
  `"all"`.

- dest:

  Character. Directory to write JSON files to. Defaults to the writable
  user cache. Set this explicitly to `inst/metadata/` only when
  refreshing package-bundled snapshots during development.

## Value

Invisibly, a named character vector of file paths that were written (or
would have been written). On network error the function warns and
returns `NULL` invisibly without overwriting existing files.

## Details

**API endpoints used:**

- L1/L2:
  `https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets`

- L3:
  `https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets`

Pagination is handled automatically via the `links[rel="next"]` field in
each response.

## Examples

``` r
if (FALSE) { # \dontrun{
# Update all levels in the default writable user cache
wapor_update_metadata()

# Update only L1 and write to a custom directory
wapor_update_metadata("L1", dest = tempdir())
} # }
```
