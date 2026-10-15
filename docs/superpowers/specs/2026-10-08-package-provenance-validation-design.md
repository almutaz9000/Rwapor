# Rwapor Data Provenance and Compatibility Validation Design

Status: Approved by the user on 2026-10-08; implementation proceeds in gated milestones.

## Goal

Make Rwapor's supported raster workflows carry enough temporal, spatial, unit, coverage, and lineage metadata to detect known-incompatible inputs before calculation, report missing provenance honestly, and preserve the record with exported outputs.

## Current context

Rwapor already has WaPOR variable metadata, temporal product codes, dekad-table generation, source date parsing, processing coverage, a kernel manifest, configuration validation, and a rainfall helper that checks paired raster layer counts and dates. These pieces are separate. The seasonal engine uses a shared configured analysis period and common processing grid, but its returned seasonal indicators do not have a common machine-readable provenance record. Standalone CWP/BWP helpers accept rasters or numeric values without knowing whether their inputs refer to the same period. Raster attributes alone are not a durable provenance store because raster operations, writing, and reloading can discard or change them.

## Design decisions

### 1. Provenance is structured data, not only raster attributes

Add an internal JSON-safe provenance model and public inspection/validation entry points. Keep existing SpatRaster return types and result-list contracts. Analysis results gain a `provenance` record and a `validation` report. Exported analysis outputs gain a versioned JSON sidecar. `terra::time()`, layer names, and units remain useful interoperable metadata, but are not the sole source of truth.

The schema is versioned and uses only JSON-safe values. It records:

- schema version and stable dataset/result identifier;
- source variable code and temporal code when known;
- ordered layer intervals, each with start and end dates;
- run-level requested period and temporal resolution;
- value units and temporal semantics (for example depth per interval, rate, state, or dimensionless ratio);
- spatial CRS and grid signature sufficient to compare geometry without embedding raster cell data;
- source identity represented without leaking absolute local paths or credentials;
- operation name, aggregation method, and parent identifiers;
- spatial coverage / missing-data summary where available;
- season definition: analysis window plus season-mask or start/end-raster lineage when pixel-specific crop seasons were used.

Do not claim that a run-level period equals every pixel's crop-season period. A season mask may represent pixel-specific dates; provenance must identify it as a distinct input to the seasonal aggregation.

### 2. Deterministic metadata resolution

For temporal metadata, use the following precedence:

1. Explicit, complete `terra::time()` values.
2. Parseable per-layer names or source filenames, including WaPOR-style `YYYY-MM` and `YYYY-MM-DD` tokens.
3. The validated engine request period and known source temporal code, for data loaded by that engine invocation.
4. Unknown, when none of the above provide adequate evidence.

Preserve interval boundaries, not just a single timestamp. Monthly intervals represent calendar months; annual intervals represent the defined product year; dekadal intervals use the actual dekad start/end; daily intervals represent the day. Do not infer missing dates from layer count or position.

### 3. Shared compatibility validator

Create one validator that accepts provenance records and an operation contract. Operation contracts specify which properties must agree or be compatible. At minimum, validate:

- layer count and ordered layer intervals for pairwise time-series operations;
- time-window compatibility for seasonal ratios such as CWP/BWP and adequacy;
- unit dimension and temporal semantics before arithmetic or ratios;
- CRS/grid compatibility or an explicit alignment policy;
- required data coverage and missing intervals when the operation needs complete coverage;
- parent lineage and season-definition compatibility for derived results.

A known conflict is an error and calculation must stop. Missing/unparseable metadata is a warning and processing may continue in the default mode, with a clear report that verification was incomplete. An opt-in strict mode turns required-but-unknown provenance into errors. No `off` mode should suppress known conflicts. Single-layer raster pairs without temporal sequence metadata do not produce a meaningless layer-sequence warning; temporal compatibility for their associated analysis period still uses result provenance when available.

### 4. Validation report

Use a stable result shape with `status` (`passed`, `warning`, or `failed`), `errors`, `warnings`, and named check records containing the check identifier, inputs, and relevant observed values. Error messages identify the input/result names and the first conflicting periods or properties. Avoid absolute local paths in user-facing messages and sidecars.

The engine places the report on `results$validation`. Warnings are emitted once per issue at a public boundary, not once per raster cell or inner-loop operation.

### 5. Integration boundaries

Apply validation at reusable boundaries, not by copy-pasting checks into every arithmetic expression:

- input discovery/loading and source-period alignment;
- the seasonal analysis engine before combining source layers and before deriving indicators;
- public raster helpers that accept multiple time-dependent inputs, including CWP/BWP, adequacy, green/blue water, rainfall surplus, and stack arithmetic;
- analysis output export and supported import/reload paths;
- temporal-series workflows such as `wapor_ts()` and monitoring where multiple variables or periods are joined.

Pure numeric helpers remain usable without provenance. Their mathematical results cannot establish time consistency. Public raster wrappers consult attached or explicitly supplied provenance; with unavailable provenance they follow the warn-and-continue policy. The seasonal engine, which has request context and source files, must populate provenance automatically.

### 6. Persistence and compatibility

Do not replace existing SpatRaster returns with a wrapper class in this release. Preserve existing public function positional arguments and append optional validation/provenance arguments only where direct callers need an override. Use schema-versioned sidecars for durable provenance. On reload, read a recognized sidecar and validate that it describes the raster geometry/layer count; reject a mismatched sidecar rather than attaching it silently. Legacy rasters without sidecars remain readable and are marked as provenance-incomplete.

Sidecar source references must not expose secrets, credentials, or absolute user paths. Use source variable codes and safe basenames or stable hashes instead.

## Acceptance criteria

1. AETI and biomass known to cover different seasons cannot be combined for CWP/BWP; the error names both periods.
2. Equal layer counts with different ordered periods fail; equal periods pass, including matching dates represented through supported metadata sources.
3. Monthly products and dekadal products can be recognized as different temporal resolutions; they are compatible only when an explicit aggregation/alignment step produces equivalent required intervals.
4. Derived seasonal results carry analysis window, source intervals, aggregation method, units, grid signature, coverage summary, parent lineage, and season-mask lineage where relevant.
5. Unknown provenance warns and continues by default; strict mode fails when a required metadata field is unknown; known mismatches fail in every mode.
6. Export writes a valid, schema-versioned sidecar; reload validates and restores it; legacy outputs load with an explicit unknown-provenance status.
7. Existing return types and default numeric outputs remain unchanged where inputs are compatible.
8. Tests cover API/local fixtures, monthly/dekadal/annual periods, cross-year seasons, missing/partial dates, reordered layers, unit mismatch, grid mismatch, missing coverage, sidecar round trips, and CWP/BWP cross-season rejection.

## Non-goals

- Inferring true dates for arbitrary numeric arrays or rasters with no dates, names, source record, or caller-supplied provenance.
- Silently reordering input stacks to make them match. Validation reports the mismatch; a separate explicit alignment operation may reorder only when it can uniquely match all intervals.
- Replacing the seasonal hydrology or crop-calendar model.
- Treating rainfall surplus as FAO AQUASTAT IRWR.
- A forced global breaking change to public result object types.

## Implementation staging

Implementation proceeds as independently tested milestones in the companion plan. Do not start a later milestone until the current milestone's focused tests, contract review, and package smoke gate pass. Preserve current uncommitted work and do not commit or change branches unless requested.