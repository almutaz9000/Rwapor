---
name: cog-api-streaming
description: >
  Procedural patterns for the FAO GIS Manager API client (httr2), Cloud-
  Optimized GeoTIFF (COG) reading and writing, and GDAL virtual-file-system
  (/vsicurl/) range-read streaming in Rwapor. Use when implementing or
  reviewing R/api_client.R, R/gdal_config.R, or any windowed/remote raster
  read. Primarily used by api-cog-streaming-engineer.
---

# COG & API Streaming Patterns

## 1. httr2 API client conventions

- All HTTP calls go through `httr2`, never legacy `httr`/raw `curl` — this
  is the existing house convention in `R/api_client.R`.
- Paginate defensively: `collect_responses()` must handle a short/partial
  final page and a server error mid-pagination without corrupting
  already-collected results — return what was successfully collected plus
  a clear indication of where it stopped, rather than either silently
  truncating or throwing away partial progress.
- Wrap retryable failures (timeouts, 5xx) with `httr2::req_retry()`
  (exponential backoff), and make failures *identifiable*: a raised
  condition should carry which variable/period/region the failing request
  was for — a bare "HTTP 500" three frames removed from the loop that
  built the URL is not debuggable in production use.
- Reproduce before fixing: `dev-tools/scripts/debug/repro_api_failure.R`
  exists specifically to reproduce a known class of API failure — read
  and, where relevant, extend it rather than guessing at a fix from a
  user's error report alone.

## 2. Writing COGs

Target pattern (Improvement Plan §2.2):

```r
write_raster_cog <- function(r, path) {
  gdal_version <- as.numeric_version(terra::gdal())
  if (gdal_version >= "3.1") {
    terra::writeRaster(
      r, path,
      filetype = "COG",
      gdal = c("COMPRESS=LZW", "COPY_SRC_OVERVIEWS=YES"),
      overwrite = TRUE
    )
  } else {
    # Fallback: standard tiled GeoTIFF — still usable, just not a true COG
    terra::writeRaster(
      r, path,
      gdal = c("TILED=YES", "COMPRESS=LZW"),
      overwrite = TRUE
    )
  }
}
```

Verify the fallback branch is actually reachable in CI (or test it with a
mocked `gdal_version`) — a fallback that's never exercised is a fallback
that silently breaks.

## 3. Reading COGs via windowed/range reads

The entire point of COG is: a client can fetch only the bytes for a
requested spatial window (plus the relevant overview level), not the
whole file, provided (a) the source is truly a COG — internally tiled with
overviews — and (b) the server supports HTTP range requests.

```r
# Configure HTTP behavior once (wapor_configure_gdal() equivalent)
Sys.setenv(
  GDAL_HTTP_MULTIPLEX = "YES",
  GDAL_HTTP_VERSION = "2",
  CPL_VSIL_CURL_ALLOWED_EXTENSIONS = ".tif"
)
r <- terra::rast("/vsicurl/https://example.org/path/to.tif")
window <- terra::crop(r, aoi_extent)  # triggers only the needed range reads
```

Before relying on this for performance, confirm the remote file is
actually COG-structured (internal tiling + overviews) — a plain GeoTIFF
served over HTTP with `/vsicurl/` still "works" but GDAL will end up
fetching most of the file anyway, silently defeating the optimization.
`gdalinfo` (or `terra::describe()`) on the remote URL shows whether
`LAYOUT=COG` / overviews are present.

## 4. Caching boundary

This skill covers the transport call itself. Where the *result* is cached
(in-session `memoise` vs. on-disk TTL cache) is `bigdata-engineer`'s scope
— see that agent and the disk-cache design notes in
`IMPROVEMENT_PLAN.md` §2.1. Don't duplicate caching logic inside the API
client layer; keep transport and caching as separate concerns so either
can be tested independently.

## 5. CRAN-safe network code

- Any example or test that reaches the live API or a remote COG must be
  skippable offline: `\donttest{}` in Rd examples,
  `testthat::skip_if_offline()` (or the package's existing skip helper in
  `tests/testthat/helper-skip.R`) in tests.
- Never make package load (`.onLoad`, `.onAttach`) or `R CMD check`
  itself perform a network call.
