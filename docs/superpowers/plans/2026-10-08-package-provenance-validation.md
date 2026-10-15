# Rwapor Package Provenance and Compatibility Validation Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans or superpowers:subagent-driven-development to implement this plan task-by-task. Execute one milestone at a time. Steps use checkbox syntax for tracking.

**Goal:** Add a package-wide, metadata-driven validation system that prevents calculations with known incompatible temporal, spatial, unit, coverage, or lineage metadata and clearly reports when verification is incomplete.

**Architecture:** Keep existing SpatRaster return types. Add a versioned JSON-safe provenance model, a shared validator with operation contracts, and a result validation report. Populate provenance in the seasonal engine, integrate the validator at calculation boundaries, and persist provenance as a sidecar on export so it survives raster serialization.

**Tech Stack:** R >= 4.1, terra SpatRaster and `terra::time()`, existing Rwapor metadata/date parsing/processing kernel, jsonlite, testthat, existing COG/GeoTIFF export paths.

**Spec:** `docs/superpowers/specs/2026-10-08-package-provenance-validation-design.md`

## Global Constraints

- Preserve existing user-facing SpatRaster and result-list contracts.
- Known temporal, spatial, unit, coverage, or lineage incompatibilities are errors in every validation mode.
- Unknown provenance warns and continues by default; strict mode errors when required metadata cannot be established.
- Never infer dates from layer count or silently reorder input layers.
- Derive seasonal metadata from the engine's requested period and source intervals; record pixel-specific season masks separately.
- Do not write absolute local source paths, credentials, or secrets into validation messages or provenance sidecars.
- Preserve WaPOR temporal code, native resolution, units, resampling semantics, CRS, coverage and crop-mask meanings.
- Treat the existing dirty working tree as owned work. Do not reset, commit, push, or change branches.
- Keep each milestone independently testable. Do not proceed to the next milestone until its gate passes.

## Current source map

- `R/metadata.R`: WaPOR variable codes, units, scale factors, temporal resolution.
- `R/analysis.R`: `build_dekad_table()`, temporal source matching and source-file date parsing.
- `R/analysis_engine.R`: common analysis period, source resolution, kernel aggregation, derived indicators, coverage results.
- `R/processing_kernel.R`: per-source aggregation and run manifest with grid, processing, tiles, and coverage.
- `R/analysis_validation.R`: existing configuration and crop-parameter validation; extend only through shared helpers, not duplicated rules.
- `R/analysis_indicators.R`: public calculation wrappers including CWP/BWP, adequacy and water partition helpers.
- `R/analysis_utils.R`: analysis export; add safe provenance sidecar writing and monthly outputs only as specified by the milestone.
- `R/wapor_map.R`, `R/wapor_ts.R`, `R/seasonal_download.R`, `R/wapor_monitoring.R`: later integration boundaries. Trace calls and data shapes before editing.
- Existing rainfall-surplus edits are already uncommitted in the working tree. Preserve them and extend their period check through the shared validator rather than replacing that work.

## Milestone 0: Spec and plan review gate

**Objective:** Freeze the approved design and implementation gates before package changes.

**Files:**
- Review: `docs/superpowers/specs/2026-10-08-package-provenance-validation-design.md`
- Review: this plan

**Verification:** Cold-read both documents against the user's approved design. Confirm each acceptance criterion maps to at least one milestone and no package code changes occur before the spec review gate.

**Gate:** PASSED. The user approved the design and directed implementation on 2026-10-08. Task `prov-v1` is claimed; proceed to Milestone 1.

## Milestone 1: Temporal interval primitives and provenance schema

**Objective:** Normalize raster temporal metadata from explicit terra time values, layer names, source filenames, or engine request context into one ordered interval representation.

**Likely files:**
- Create `R/provenance.R` for schema constructors, date/interval parsing, JSON-safe normalization, and validators.
- Modify `R/analysis.R` only if existing parsers need a compatibility wrapper; do not duplicate existing source-date parsing.
- Create `tests/testthat/test-provenance.R`.
- Update `NAMESPACE` and generated `man/` only for intentionally public APIs.

**TDD slices:**
1. Add tests for YYYY-MM, YYYY-MM-DD, WaPOR-style filename tokens, explicit terra Date/POSIXt time, partial/NA metadata, layer-count mismatch, ordered intervals, and unknown metadata.
2. Run only `test-provenance.R`; confirm each new case fails for the missing contract.
3. Implement the smallest internal parser and schema constructor.
4. Re-run the focused test, then parse the changed R file and run the minimal package-load smoke test.

**Contract shape:**
- Layer interval record: `start`, `end`, `temporal_code`, `source`.
- Provenance record: `schema_version`, `dataset_id`, `variable`, `temporal_resolution`, `intervals`, `period`, `units`, `value_semantics`, `grid`, `coverage`, `operation`, `parents`, `season_definition`.
- Missing facts are explicit `NULL`/unknown values, never fabricated dates.

**Gate:** PASSED 2026-10-08. `test-provenance.R` passed 31 assertions; `test-wapor.R` passed 97 (5 CRAN skips); `test-analysis-indicators.R` passed 52. `R/provenance.R` parsed and `devtools::load_all(quiet = TRUE)` succeeded. No code outside the temporal primitives/schema and their focused tests was added for this milestone.

## Milestone 2: Shared compatibility validator and diagnostics

**Objective:** Validate temporal, grid, unit, coverage and lineage requirements using operation-specific contracts and stable validation reports.

**Likely files:**
- Create `R/compatibility_validation.R` for the shared validator and operation contracts, using the temporal/provenance constructors from `R/provenance.R`.
- Modify `R/analysis_validation.R` only where config validation can delegate to shared helpers without duplicating policy.
- Create or extend `tests/testthat/test-provenance-validation.R`.
- Run `devtools::document()` to update `NAMESPACE` and `man/` for the exported validator.

**TDD slices:**
1. Test known temporal overlap/mismatch, ordered-period mismatch, valid compatible aggregation, grid mismatch, convertible and incompatible units, incomplete coverage, missing metadata warning, strict-mode unknown failure, and known mismatch error in every mode.
2. Confirm red with the focused test file.
3. Implement a report with `status`, `errors`, `warnings`, and named check records containing check ID and safe input labels.
4. Confirm exact diagnostics; ensure warning emission occurs at public boundaries and is not repeated per raster cell.

**Policy:** Default is warn-and-continue only for unknown provenance. Strict mode fails if a field required by that operation is unknown. A known incompatibility always fails. Do not add an `off` policy that hides known conflicts.

**Gate:** PASSED 2026-10-08. `test-provenance-validation.R` passed 26 assertions, covering literal period/grid/ordered-interval/unit/season/coverage fixtures, raster-derived metadata, warn and strict unknown handling, and water-productivity units. `test-provenance.R` passed 31. Regression checks: analysis indicators 52, analysis engine 69, dashboard validation 11 all passed. `devtools::document()` generated `NAMESPACE` and `man/wapor_validate_compatibility.Rd`; `git diff --check` passed. The validator is available as a public diagnostic API, but calculation call paths are not yet comprehensively guarded; those integrations are later milestones.

## Milestone 3: Seasonal engine provenance and seasonal identity

**Objective:** Attach source and derived provenance to seasonal engine results, including season-mask lineage and the exact inputs used by CWP/BWP.

**Likely files:**
- Modify `R/analysis_engine.R` to create source provenance from config, resolved variables, actual source intervals, units, analysis grid, resampling methods, and coverage.
- Modify `R/processing_kernel.R` only to pass JSON-safe provenance into the existing run manifest, preserving resume/config-hash semantics.
- Modify `R/analysis_engine.R` result construction to record provenance for monthly and seasonal outputs and parent links.
- Create/extend `tests/testthat/test-analysis-provenance.R` and `tests/testthat/test-analysis-engine.R`.

**TDD slices:**
1. Add a synthetic multi-month engine test verifying source interval records and monthly-derived output intervals.
2. Add a cross-year season test proving the analysis window and per-pixel season-mask lineage remain distinct.
3. Add tests that all derived outputs have correct parent IDs, units, aggregation method, and grid signature.
4. Add tests that two engine indicators using the same configured period and shared weights pass compatibility checks.
5. Verify the manifest includes only safe source identifiers and does not change existing tile resume behavior.

**Gate:** Focused engine tests pass in memory mode; known-answer fixtures remain unchanged; manifest resume/config-hash tests pass.

## Milestone 4: Indicator calculation contracts

**Objective:** Prevent incompatible standalone raster indicator inputs from being combined, especially cross-season biomass/AETI for CWP/BWP.

**Likely files:**
- Modify `R/analysis_indicators.R` public wrappers for CWP/BWP, adequacy and green/blue/rainfall calculations to invoke operation contracts when raster provenance is available.
- Modify `R/analysis_engine.R` to pass trusted provenance from engine results into internal/public calculations without recomputing or guessing dates.
- Modify `R/analysis_registry.R` only if its extra-step path is an active consumer after tracing callers.
- Create/extend `tests/testthat/test-indicator-provenance.R` and existing indicator tests.

**TDD slices:**
1. Build two synthetic seasonal rasters with explicit, different periods; prove CWP and BWP stop with both periods in the error.
2. Prove matching periods pass and preserve prior numeric outputs.
3. Prove an unknown-period raster warns by default and strict mode errors.
4. Prove layer-count/date validation from rainfall surplus uses the shared validator without duplicate warnings.
5. Test the registry and engine callers so a fix at the public boundary does not leave an alternate unvalidated path.

**Gate:** Focused indicator, registry, and engine tests pass; known-answer seasonal values unchanged.

## Milestone 5: Sidecar persistence and round-trip validation

**Objective:** Preserve provenance through export and supported reload paths without replacing raster outputs or leaking paths.

**Likely files:**
- Modify `R/analysis_utils.R` to write a versioned `<analysis>.provenance.json` sidecar next to the output set.
- Modify existing local-raster/read helpers in `R/analysis.R` only where they can reliably associate an output raster with its sidecar.
- Modify `R/processing_kernel.R` manifest helpers only if a shared safe JSON serializer is justified.
- Create/extend `tests/testthat/test-provenance-export.R` and existing export tests.

**TDD slices:**
1. Test sidecar schema and JSON serialization, including unknown values and multi-period results.
2. Test export then reload restores provenance and verifies raster count/grid signature.
3. Test stale or mismatched sidecar is rejected or reported, not silently attached.
4. Test legacy raster with no sidecar loads with provenance status `unknown` and a warning only where the operation needs temporal compatibility.
5. Scan sidecar contents for absolute local paths, credentials, and tokens.

**Gate:** Round-trip tests pass; existing export tests pass; sidecar data is JSON-valid and safe.

## Milestone 6: Package-wide entry-point integration

**Objective:** Apply the same report and known-conflict policy to remaining supported multi-variable and temporal workflows.

**Likely files, after tracing call paths:**
- `R/wapor_ts.R` and related helpers.
- `R/seasonal_download.R` and temporal planner integration.
- `R/wapor_monitoring.R` for persisted timeseries joins.
- `R/zonal_stats.R` to preserve units/time metadata where statistics retain a temporal axis.
- `inst/shiny/mod_analysis.R` and UI validation output only after core public APIs stabilize.
- Corresponding focused tests in existing files or new `test-provenance-*.R` files.

**TDD slices:**
1. Test each workflow's source-period matching and explicit reporting of incomplete metadata.
2. Test join/aggregation alignment for monthly, dekadal, annual, and daily data.
3. Test monitoring cannot join different seasons under the same variable/farm key.
4. Test Shiny shows actionable warnings/errors from the same validation report, not a second implementation.

**Gate:** Focused workflow tests pass; no parallel, inconsistent validation logic remains for these call paths.

## Milestone 7: Release-level regression and documentation

**Objective:** Prove the validation framework works across the package and document caller responsibilities and limitations.

**Files:**
- Update `README.md`, `NEWS.md`, function roxygen docs, generated `man/`, and a vignette or validation guide.
- Extend `tests/testthat/test-known-answer.R` only for provenance shape/check status; do not alter golden numerical fixtures unless a separately approved scientific correction requires it.

**Verification:**
1. Run every focused new test file independently.
2. Run `devtools::test()` with test output captured and inspect skips.
3. Run `devtools::document()` and inspect generated diffs for scope.
4. Run `devtools::load_all(quiet = TRUE)` and the package parse/smoke checks.
5. Run `git diff --check` and review the full diff, confirming prior user changes remain intact.
6. Run package check to completion when the environment permits; report warnings, notes, skips, live integrations, and any unverified paths honestly.

**Final acceptance:** Every acceptance criterion in the spec maps to an automated test or an explicitly documented limitation; known incompatible periods fail before arithmetic; exported outputs preserve provenance; legacy unannotated inputs continue with clearly surfaced unknown status in default mode.

## Orchestration and milestone control

- Use one implementation stream for the shared provenance schema and validator. Do not parallelize edits to `R/provenance.R` or the engine's shared result contract.
- After Milestone 1, independent reviewers may audit the schema/interval semantics and test sufficiency without editing the same files.
- Later independent reviews can inspect export privacy and engine compatibility in parallel after their implementation tasks finish.
- Each milestone follows RED, GREEN, focused regression, and independent review before the next milestone begins.
- Do not commit or push unless the user explicitly asks.

## Risks and mitigations

- **Raster metadata loss:** structured result metadata and sidecars are canonical; terra metadata is an interoperable supplement.
- **Variable-length crop seasons:** store analysis period and per-pixel season-mask lineage separately.
- **Legacy sources:** warn on unknown metadata by default and support strict validation when users require guarantees.
- **False date matching:** only parse documented date forms; never infer chronology from layer count.
- **Unit ambiguity:** validate dimension and temporal semantics, not only string equality; reject uncertain conversions rather than assume.
- **Large outputs and performance:** store compact lineage and grid signatures, not raster arrays; avoid per-cell provenance checks.
- **Scope creep:** land a working validation foundation first, then integrate one class of workflow at a time with its own acceptance gate.
