# Implementation Plan: Shiny Batch Analysis And Script Generation (P4)

## Goal

Implement the approved design in `docs/superpowers/specs/2026-05-11-shiny-batch-analysis-design.md` so batch mode becomes a first-class Shiny analysis path for validation, execution, and reproducible script export.

## Proposed Changes

### `inst/shiny/mod_analysis.R`
- Add a single analysis-config builder used by validate, run, and script preview/export.
- Extract batch-list parsing into a dedicated helper or helper call so malformed lines fail early with clear messages.
- Replace batch-mode code paths that still assume one `period` with season-aware iteration for local coverage checks and missing-data diagnostics.
- Remove split script-preview behavior so the Ace editor is populated from one generator path only.
- Keep the existing engine call to `wapor_run_seasonal_analysis()`, but pass the normalized single-season or multi-season config directly.

### `R/analysis_utils.R`
- Extend `wapor_generate_shiny_script()` so it can emit scripts for:
  1. single-season runs
  2. multi-season batch runs
  3. local-file mode
  4. API mode
- Add reusable helpers for:
  - parsing batch input lines into a named period list
  - formatting the normalized config into R code
  - generating one canonical script string for preview and download

### `inst/shiny/mod_analysis_ui_body.R`
- Add an explicit `Download R Script` action in the reproducibility/export card.
- Keep the current preview toggle and editor, but make it reflect the same script text that gets downloaded.

### `R/analysis_validation.R`
- Add or extend shared validation helpers only where needed to support season-aware local coverage checks without forcing a redesign of the engine API.
- Keep single-season validation behavior intact.

### `tests/testthat/`
- Add regression coverage for batch parsing.
- Add regression coverage for single-season and multi-season script generation.
- Add coverage that a local multi-season config reaches the analysis engine without single-period errors.

## Implementation Order

1. Add and test the batch parsing helper.
2. Normalize Shiny config assembly around one builder.
3. Switch validation and local missing-data checks to the normalized config.
4. Extend script generation for single-season and batch configurations.
5. Wire the preview and download button to the same script string.
6. Add regression tests for the fixed paths.
7. Run focused package tests for analysis and script-generation behavior.

## Verification Plan

1. Run automated tests covering batch parsing and script generation.
2. Run automated analysis tests for `wapor_run_seasonal_analysis()` paths touched by the change.
3. Launch the dashboard and verify single-season validation, run, and script preview still behave as before.
4. Launch the dashboard in local mode with two or more seasons in batch mode and verify validation does not disconnect the Shiny session.
5. Run a batch local analysis and verify the session remains connected to the R console.
6. Download the generated `.R` script for both single-season and multi-season configurations and confirm the exported script matches the configured workflow.
