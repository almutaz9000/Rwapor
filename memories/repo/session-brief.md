# Session Brief (Rolling)

## Active Focus
- Stabilize Shiny download AOI/L3 overlap detection path.
- Improve startup reliability differences between default and --vanilla runs.

## Top Open Issues
- ISS-20260331-001: L3 overlap auto-detection may report no overlap for known AOI.
- ISS-20260331-002: Non-vanilla startup can fail while vanilla startup works.

## Recently Resolved
- ISS-20260331-003: Invalid details helper in Shiny UI fixed via tags$details.
- ISS-20260331-004: `wapor_guess_region` period type mismatch fixed via character coercion.
- ISS-20260331-005: OneDrive raster AOI diagnostics improved with actionable checks.

## Pending Tasks (Top 5)
- [ ] Validate JEN auto-detection end-to-end in live Shiny run.
- [ ] Add regression tests for L3 detection status mapping.
- [ ] Add regression tests for OneDrive/local raster AOI upload diagnostics.
- [ ] Reproduce non-vanilla startup failure with startup diagnostics.

## Guardrails
- Always use R 4.5.3 executable path.
- Read memory digest before implementation.
- Move solved issues from Open Issues to Resolved Improvements.
