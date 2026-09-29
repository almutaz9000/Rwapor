# Known-answer fixture

Real WaPOR v3 data (open data, FAO) cut from the 2026-09 training case studies,
used by `test-known-answer.R` to pin the numbers of `wapor_run_seasonal_analysis()`.

| Case | Period | Grid | Variables (one multi-band stack each, band names = dekad start) |
|---|---|---|---|
| `citrus/` | 2024-03-01 to 2025-02-28 (36 dekads) | 20 x 20 L3 pixels, North Jordan Valley (JVA) | L3-AETI-D, L3-T-D, L1-RET-D, L1-PCP-D |
| `wheat/` | 2023-11-01 to 2024-05-31 (21 dekads) | 20 x 20 L3 pixels, Jendouba (JEN) | L3-AETI-D, L3-T-D, L3-NPP-D, L1-RET-D, L1-PCP-D |

- Values are physical mm/day (NPP gC/m2/day), Float32, as saved by the training
  notebook's download step. `crop_mask.tif`: 1 = crop, NA elsewhere.
- The 20 x 20 window is the block with the most crop pixels (every pixel is crop).
- Seasons deliberately start on 1 March and 1 November, not 1 January: the
  1.0.4/1.0.5 ETc bug (ISS-20260929-017) only showed for such seasons.

## golden.csv

Mean, min and max over the crop mask of every single-layer raster the analysis
returns (236 rows), for the configuration in `test-known-answer.R`.

- Generated with Rwapor **v1.0.3** (last release before ISS-20260929-017), memory mode.
- The current code reproduces all rows: memory exactly, stream and tiled within
  1.1e-7 relative (Float32 outputs).
- Independently checked against plain formulas on these stacks (sum of mm/day x days,
  FAO-56 daily Kc x RET, USDA-SCS monthly Peff, monthly green/blue split,
  yield = HI x AOT x fc x NPP x 22.222 / 1000 / (1 - MC)): citrus AETI 446.32,
  ETc 1050.93, green 121.45, blue 324.87 mm; wheat AETI 328.08, ETc 466.89 mm,
  biomass 13.274 t/ha, yield 5.036 t/ha. All agree to 4 decimals.

## Changing the numbers

A golden value may only change when the methodology changes on purpose. Then:
regenerate `golden.csv`, explain the change in NEWS.md, and cite the method.
A failing known-answer test without such a decision is a bug.
