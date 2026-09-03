---
name: wapor-etlook-methodology
description: >
  Reference and verification discipline for WaPOR v3 data products, the
  ET-Look/PyWaPOR model chain, and FAO-56 crop-water methodology used
  throughout Rwapor. Use whenever answering a question about what a WaPOR
  variable represents, how ET-Look derives AETI/RET/NPP, or how FAO-56
  Kc/Peff/adequacy/CWP formulas are defined. Primarily used by
  wapor-data-expert and agronomy-expert, but any agent should load this before
  stating a methodological claim as fact.
---

# WaPOR / ET-Look / FAO-56 Methodology Reference

## The core rule: this domain moves under you

WaPOR product versions, variable definitions, and even unit conventions
have changed across major versions (v1 → v2 → v3), and the underlying
ET-Look/PyWaPOR model is under active development. Rwapor's own
`NEWS.md` (0.9.7) records a real historical instance of user-facing
naming instability. Treat any methodological claim more specific than
"WaPOR estimates evapotranspiration and biomass production from remote
sensing" as something to verify this session, not recall from training.

**Before stating a specific number, threshold, formula coefficient, or
"WaPOR currently does X":**
1. Check whether `R/metadata.R` or `R/analysis_indicators.R` /
   `R/indicators_math.R` already encodes the answer as implemented —
   that's the package's operative truth even if a newer WaPOR version
   changed something upstream.
2. If the question is about the live API/model rather than what's
   implemented, fetch the current source (list below) with
   WebFetch/WebSearch before answering.
3. If package behavior and current upstream methodology disagree, say so
   explicitly — don't silently harmonize them without flagging the
   discrepancy to the user, since matching upstream might be a breaking
   change.

## Primary sources (fetch current content, don't rely on cached summaries)

| Topic | Source |
|---|---|
| ET-Look model chain (soil moisture, land surface energy balance → AETI/RET/NPP) | https://bitbucket.org/cioapps/wapor-et-look/wiki/Home |
| PyWaPOR (the Python reference implementation of the processing chain) | https://bitbucket.org/cioapps/pywapor/src/master/ |
| WaPOR portal, product catalog, download/API docs | https://www.fao.org/in-action/remote-sensing-for-water-productivity/ |
| FAO-56 (Allen, Pereira, Raes, Smith, 1998) — Kc, ETc, Peff, crop growth stages | Standard reference; verify specific table values (Table 11: stage lengths, Table 12: Kc values) against the published tables rather than approximating |

## Product/variable structure as currently encoded in Rwapor

- **Levels**: L1 (continental, ~250 m), L2 (national, ~100 m), L3
  (project/scheme, ~30 m, only where a region code exists in
  `L3_REGIONS`).
- **Temporal codes**: `E` daily, `D` dekadal (~10-day), `M` monthly, `A`
  annual.
- **Variable code format**: `"{level}-{variable}-{temporal_code}"`, e.g.
  `"L1-AETI-D"`, `"L2-NPP-A"`, `"L3-AETI-D"`, `"AGERA5-ET0-D"`.
- **Core variables used by the analysis engine**: AETI (actual
  evapotranspiration and interception), RET (reference
  evapotranspiration), NPP (net primary production), PCP (precipitation,
  via AgERA5).

## FAO-56 formula skeleton (verify coefficients, not the structure, per crop/source)

- Kc curve: piecewise linear across `L_ini` (constant `Kc_ini`),
  `L_dev` (linear ramp `Kc_ini` → `Kc_mid`), `L_mid` (constant `Kc_mid`),
  `L_late` (linear ramp `Kc_mid` → `Kc_end`).
- `ETc = RET × Kc` (dekadal or daily, depending on the temporal
  resolution of the inputs — do not mix temporal resolutions without an
  explicit aggregation step).
- `Adequacy = AETI / ETc` — values near 1.0 indicate the crop received
  its estimated water requirement; <1 indicates deficit, >1 indicates
  potential over-irrigation (interpretation, not a hard threshold —
  don't assert a universal "adequate" cutoff without the user's own
  agronomic context for the crop/region).
- `Peff` (USDA SCS method): a monthly, non-linear function of total
  monthly precipitation — do not approximate this as a flat fraction of
  gross precipitation; the SCS method's whole point is that effectiveness
  drops off at both very low and very high monthly totals.
- `CWP = yield / AETI`, `BWP = biomass / AETI`, both in kg/m³ once units
  are reconciled (yield/biomass mass unit over AETI depth-as-volume-per-area).
- `NPP → yield`: `TBP` (total biomass production) from NPP via a
  standard conversion factor, then yield via harvest index (`HI`),
  moisture content (`MC`), and above-ground fraction (`fc`)/aboveground
  over total (`AOT`) — the exact conversion chain is implemented in
  `R/indicators_math.R` (`wapor_math_npp_to_biomass`,
  `wapor_math_yield_from_npp`); treat that implementation as
  authoritative for what Rwapor computes, and diff it against WaPOR's own
  published methodology notes if asked to validate correctness.

## Answering a methodology question — required shape

1. State what Rwapor currently implements (cite the file/function).
2. If asked whether that matches current WaPOR/FAO-56 methodology, fetch
   and cite the current source before answering yes/no.
3. Flag any discrepancy found, with enough detail for the user to decide
   whether to update the implementation (this is a product decision, not
   something to silently "fix").
