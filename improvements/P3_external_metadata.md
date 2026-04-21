# Implementation Plan: External Metadata Registry (P3)

## Goal
Decouple the package logic from the specific WaPOR variable list by moving the metadata (scales, units, descriptions) into an external resource file.

## Proposed Changes

### `inst/extdata/variable_registry.json` (New File)
- Store all variable definitions currently in `R/metadata.R`.
- Include fields: `code`, `long_name`, `units`, `scale_factor`, `temporal_resolution`.

### `R/metadata.R`
- Refactor `wapor_variable_metadata()` to load from the JSON file on package load.
- Implement a `wapor_register_variable()` function to allow users to add their own custom variables (e.g., local rasters) to the session's metadata.

## Verification Plan
1. Add a dummy variable to the JSON file.
2. Verify that it appears in the metadata queries.
3. Ensure that all unit conversions and scaling operations correctly use the factors from the external file.
