# Issues Log

## Open Issues
- [ ] L3 overlap auto-detection may report no overlap for known AOI in some runs
  - ID: ISS-20260331-001
  - Discovered: 2026-03-31
  - Context: Shiny download module with uploaded `Jendouba_aoi.geojson`
  - Error signature: "No L3 regions overlap with this AOI" (intermittent before fixes)
  - Suspected root cause: fragile detection path and insufficient diagnostics around parse/API interaction
  - Owner: Rwapor-dev
  - Next action: validate end-to-end in live Shiny run and add regression tests

- [ ] Non-vanilla startup can fail while vanilla startup works
  - ID: ISS-20260331-002
  - Discovered: 2026-03-31
  - Context: terminal launch (`run_wapor()`) in default profile environment
  - Error signature: intermittent startup failure in non-vanilla execution context
  - Suspected root cause: environment/profile side effects outside module code path
  - Owner: Rwapor-dev
  - Next action: compare startup environment and isolate profile-triggered differences

## Resolved Improvements
- [x] Invalid UI tag helper for details block
  - ID: ISS-20260331-003
  - Resolved: 2026-03-31
  - Root cause: used `shiny::details` which is not exported
  - Fix applied: replaced with `shiny::tags$details`
  - Files: `inst/shiny/mod_download.R`
  - Validation: Shiny file parses without errors
  - Regression test: pending

- [x] L3 detection period type mismatch
  - ID: ISS-20260331-004
  - Resolved: 2026-03-31
  - Root cause: Date vector passed to `wapor_guess_region` requiring character dates
  - Fix applied: normalized with `as.character(period_dates)` before call
  - Files: `inst/shiny/mod_download.R`
  - Validation: error signature no longer appears after conversion
  - Regression test: pending

- [x] Raster AOI path diagnostics insufficient for OneDrive cases
  - ID: ISS-20260331-005
  - Resolved: 2026-03-31
  - Root cause: file existence failures lacked actionable diagnostics
  - Fix applied: added existence checks, directory introspection, and actionable user guidance
  - Files: `inst/shiny/mod_aoi.R`
  - Validation: enhanced error notifications show cause and next actions
  - Regression test: pending
