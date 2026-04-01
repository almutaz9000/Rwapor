# Task Status Ledger

## 2026-03-31

### Success
- [x] Added L3 AOI-first workflow in Shiny download module.
- [x] Added L3 overlap detection messaging and diagnostics in download UI.
- [x] Fixed `shiny::details` usage by switching to `shiny::tags$details`.
- [x] Fixed `wapor_guess_region` period type by converting to character.
- [x] Added repository memory agent and initialized memory files.

### Pending
- [ ] Validate JEN auto-detection end-to-end using uploaded Jendouba AOI in live Shiny run.
- [ ] Add test coverage for L3 detection path (period coercion and status mapping).
- [ ] Add regression test for AOI raster upload diagnostics on OneDrive/local paths.

### Failed/Blocked
- [ ] Direct non-vanilla run path intermittently fails in some sessions.
  - Blocker: Environment/profile startup behavior outside module code path.
  - Next action: Reproduce with startup diagnostics and compare `--vanilla` vs default session.
