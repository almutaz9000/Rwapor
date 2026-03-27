---
name: wapor-api-reference
description: >
  FAO GIS Manager API reference for the Rwapor package. Trigger when the user
  asks about WaPOR API endpoints, variable codes (e.g. L1-AETI-D, AGERA5-ET0-E),
  L3 region codes (AWA, BKA, ETH, etc.), API filter syntax, pagination, download
  URLs, /vsicurl/ streaming, memoised URL generation, API response structure,
  collect_responses(), wapor_generate_urls(), get_variable_metadata(), or when
  diagnosing "empty API results", "wrong variable code", "API timeout", or any
  issue in R/api_client.R or R/metadata.R. Use alongside rwapor-developer for
  broader project context.
---

# WaPOR API Reference - Rwapor Context

## Endpoints
```
WAPOR L1/L2: https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mapsets
WAPOR L3:    https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/WAPOR-3/mosaicsets
AgERA5:      https://data.apps.fao.org/gismgr/api/v2/catalog/workspaces/C3S/mapsets
```

## Filter Syntax
```
?filter=code:CONTAINS:{pattern};time:OVERLAPS:{start}:{end};
```

| Operator | Use |
|----------|-----|
| `CONTAINS` | Substring match (L3 regions) |
| `OVERLAPS` | Time range filter |
| `EQ` | Exact match |

## Response Structure
```json
{
  "items": [{"code": "...", "downloadUrl": "..."}],
  "links": [{"rel": "next", "href": "..."}]
}
```

## Implementation in Rwapor
| File | Function |
|------|----------|
| `R/api_client.R` | `wapor_generate_urls()`, `collect_responses()` |
| `R/metadata.R` | `get_variable_metadata()`, `WAPOR3_VARS`, `AGERA5_VARS` |

## Caching
All URL generation is memoized. To clear:
```r
memoise::forget(wapor_generate_urls)
```

## GDAL Virtual File System
URLs are streamed via `/vsicurl/`:
```r
terra::rast(paste0("/vsicurl/", url))
```
Configured in `R/gdal_config.R` via `wapor_configure_gdal()`.

## Variable Naming Convention
```
{Level}-{Indicator}-{Temporal}
L1-AETI-D  = Level 1, Actual ET, Dekadal
L3-NPP-M   = Level 3, Net Primary Production, Monthly
AGERA5-ET0-E = AgERA5, Reference ET, Daily (E = Every day)
```

## L3 Region Codes (subset)
AWA, BKA, GEZ, KOG, ZAN (see `L3_REGIONS` export)
