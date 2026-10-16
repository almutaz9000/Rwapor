# WaPOR Expert Agent Architecture & Specification

## 1. Overview
The **WaPOR Expert Agent** operates as an automated domain-architect, methodology auditor, and technical reviewer during the development and maintenance of the `Rwapor` R package. It ensures complete adherence to FAO WaPOR v3 standards, remote sensing energy balance principles (specifically the two-layer **ETLook** formulation), spatial raster best practices in R, Water Accounting Plus (WA+) standards, and agronomic mathematical equations.

```
                                  ┌─────────────────────────────────────────┐
                                  │           WaPOR Expert Agent            │
                                  │   (Methodology, API, & Math Auditor)    │
                                  └────────────────────┬────────────────────┘
                                                       │
         ┌─────────────────────────────┬───────────────┴───────────────┬─────────────────────────────┐
         ▼                             ▼                               ▼                             ▼
┌──────────────────┐         ┌──────────────────┐            ┌──────────────────┐          ┌──────────────────┐
│ API & Spatial    │         │ ETLook Energy    │            │ Agronomic Math   │          │ Water Accounting │
│ Verification     │         │ Balance Audit    │            │ & Formula Check  │          │ & Code Review    │
└──────────────────┘         └──────────────────┘            └──────────────────┘          └──────────────────┘
```

---

## 2. Core Agent Skills Suite

The WaPOR Expert Agent is equipped with six specialized domain skills:

### 1. `wapor-api-layer-validator`
- **Purpose**: Validates FAO WaPOR API query constructions, endpoint parameters, catalog versions (v1.0, v2.1, v3.0), spatial resolution levels (L1 = 300m/250m, L2 = 100m, L3 = 20m/30m), temporal frequency codes (`-D`, `-M`, `-A`, `-E`), and bounding box / AOI spatial filters.
- **Checks**: Translates legacy layer codes to v3 catalog IDs (e.g., `L2_AETI_D` $\to$ `L2-AETI-D`), validates L3 scheme boundaries, manages token authentication, and enforces `httr2` exponential backoff.
- **Skill Doc**: [`.agent/skills/wapor-api-layer-validator/SKILL.md`](file:///C:/Users/Mohammedal/OneDrive%20-%20Food%20and%20Agriculture%20Organization/Documents/GitHub/Rwapor/.agent/skills/wapor-api-layer-validator/SKILL.md)

### 2. `spatial-raster-auditor`
- **Purpose**: Monitors raster processing operations in R (`terra`, `sf`, `stars`).
- **Checks**: Verifies native Coordinate Reference Systems (WGS84 / EPSG:4326), proper resampling methods (Nearest Neighbor for discrete/categorical layers like crop masks and coarse climate; Bilinear/Cubic for continuous vegetation layers like $AETI$ or $NPP$), NoData value masking, and Cloud-Optimized GeoTIFF (COG) windowed reads via `/vsicurl/`.
- **Skill Doc**: [`.agent/skills/spatial-raster-auditor/SKILL.md`](file:///C:/Users/Mohammedal/OneDrive%20-%20Food%20and%20Agriculture%20Organization/Documents/GitHub/Rwapor/.agent/skills/spatial-raster-auditor/SKILL.md)

### 3. `etlook-energy-balance-auditor`
- **Purpose**: Audits the physical two-layer Penman-Monteith energy balance underlying FAO WaPOR.
- **Checks**:
  - Mass balance conservation:
    $$\mathbf{AETI \equiv E + T + I}$$
  - Net radiation partitioning between canopy ($R_{n,\text{canopy}}$) and bare soil ($R_{n,\text{soil}}$).
  - Soil heat flux ($G$) parameterized by fractional vegetation cover ($f_{\text{cover}}$).
  - Bulk canopy stomatal resistance ($r_{s,\text{canopy}}$) with root-zone soil moisture stress ($S_t$).
  - Soil surface resistance ($r_{s,\text{soil}}$) driven by topsoil degree of saturation ($S_e$).
  - Canopy precipitation interception ($I$) storage capacity.
- **Skill Doc**: [`.agent/skills/etlook-energy-balance-auditor/SKILL.md`](file:///C:/Users/Mohammedal/OneDrive%20-%20Food%20and%20Agriculture%20Organization/Documents/GitHub/Rwapor/.agent/skills/etlook-energy-balance-auditor/SKILL.md)

### 4. `agronomic-math-verifier`
- **Purpose**: Audits and enforces mathematical correctness for biomass conversions, yield estimates, and agricultural performance indicators.
- **Checks**:
  - Exact calendar day weighting per dekad (8, 9, 10, or 11 days).
  - NPP to DMP unit conversion: $1\text{ gC/m}^2/\text{day} = 22.222\text{ kgDM/ha/day}$.
  - Above-ground biomass ($B$ in $\text{t/ha}$) and fresh crop moisture content ($m_c$) adjustment:
    $$B = \frac{\text{AOT} \times f_c \times \text{NPP}_{\text{seasonal}} \times 22.222}{1000 \times (1 - m_c)}$$
  - Crop yield ($Y = B \times \text{HI}$).
  - FAO-56 4-stage time-interpolated $K_c$ curves ($ET_c = K_c \times \text{RET}$).
  - Adequacy ($AETI / ET_c$), Relative Deficit, NIR, Uniformity ($1 - CV$), and Equity ($CV$, Theil).
- **Skill Doc**: [`.agent/skills/agronomic-math-verifier/SKILL.md`](file:///C:/Users/Mohammedal/OneDrive%20-%20Food%20and%20Agriculture%20Organization/Documents/GitHub/Rwapor/.agent/skills/agronomic-math-verifier/SKILL.md)

### 5. `water-accounting-provenance-guardian`
- **Purpose**: Enforces Water Accounting Plus (WA+) standards, data lineage, and computational scalability.
- **Checks**:
  - Green vs. Blue water partitioning ($AETI_{\text{green}} = \min(AETI, P_{\text{eff}})$, $AETI_{\text{blue}} = \max(0, AETI - P_{\text{eff}})$).
  - Consumptive rainfed ET and rainfall surplus calculations.
  - Biomass and Crop Water Productivity ($WP_b, CWP$ in $\text{kg/m}^3$) and climate normalization ($WP^*$).
  - Reproducibility metadata sidecar generation (`.json`) with SHA-256 hashes of all input rasters (`R/provenance.R`).
  - Memory-safe spatial tiling (`R/tiled_processing.R`) and DuckDB time series parcel storage (`R/monitoring.R`).
- **Skill Doc**: [`.agent/skills/water-accounting-provenance-guardian/SKILL.md`](file:///C:/Users/Mohammedal/OneDrive%20-%20Food%20and%20Agriculture%20Organization/Documents/GitHub/Rwapor/.agent/skills/water-accounting-provenance-guardian/SKILL.md)

### 6. `rwapor-code-reviewer`
- **Purpose**: Inspects R function implementations, pipeline logic, memory efficiency, and vectorization.
- **Checks**: Prohibits pixel-by-pixel nested R loops in favor of `terra::app()` and `terra::lapp()`, validates argument assertions using `rlang` / `checkmate`, ensures clean roxygen2 documentation, and validates test coverage.
- **Skill Doc**: [`.agent/skills/rwapor-code-reviewer/SKILL.md`](file:///C:/Users/Mohammedal/OneDrive%20-%20Food%20and%20Agriculture%20Organization/Documents/GitHub/Rwapor/.agent/skills/rwapor-code-reviewer/SKILL.md)

---

## 3. Authoritative Domain References

The agent consults in-depth documentation stored under `docs/references/`:

1. **[`docs/references/etlook_methodology.md`](file:///C:/Users/Mohammedal/OneDrive%20-%20Food%20and%20Agriculture%20Organization/Documents/GitHub/Rwapor/docs/references/etlook_methodology.md)**:
   - Full theoretical and algorithmic formulation of the ETLook model.
   - Two-layer Penman-Monteith canopy and soil equations.
   - Jarvis-Stewart stomatal stress response functions ($f(R_s), f(VPD), f(T_{\text{air}}), S_t$).
   - Aerodynamic resistance ($r_a$) with Monin-Obukhov atmospheric stability corrections.
   - Canopy rainfall interception capacity ($S_{\max} = c_{\text{int}} \times LAI$) and throughfall dynamics.
   - Monteith Light Use Efficiency ($LUE$) carbon assimilation to dry matter production.

2. **[`docs/references/wapor_v3_indicators_catalog.md`](file:///C:/Users/Mohammedal/OneDrive%20-%20Food%20and%20Agriculture%20Organization/Documents/GitHub/Rwapor/docs/references/wapor_v3_indicators_catalog.md)**:
   - Full catalog of FAO WaPOR v3 indicators, units, and physical formulas.
   - USDA SCS effective precipitation equations ($P_{\text{eff}}$).
   - Water Accounting Plus (WA+) mass-balance partitioning (Green vs. Blue water).
   - Irrigation Adequacy thresholds: Good ($\ge 0.80$), Acceptable ($0.68 - 0.80$), Stressed ($< 0.68$).
   - Physical and climate-normalized water productivity ($WP_b, CWP, WP^*$).
   - Uniformity ($1 - CV$) and Equity ($CV$ and Theil inequality index).

---

## 4. Subagent Runtime Activation

In interactive agent environments (Antigravity / Gemini CLI), invoke either `wapor_expert` or `wapor_expert_agent`:

```r
invoke_subagent(
  Subagents = list(
    list(
      TypeName = "wapor_expert",
      Role = "WaPOR Methodology Auditor",
      Prompt = "Audit R/analysis_indicators.R to verify ETLook mass balance conservation (AETI = E + T + I) and WA+ Green/Blue water separation."
    )
  )
)
```

---

## 5. Standard Recommendation Output Schema

When auditing pull requests or reviewing code, the agent outputs recommendations in the following format:

1. **Status Overview**: PASS / WARNING / FAIL assessment.
2. **Methodology & Mathematical Audit**: Identification of formula, unit, or spatial resolution mismatches.
3. **API & Spatial Processing Audit**: Identification of projection, resampling, or API endpoint issues.
4. **Refactored R Code Snippet**: Production-ready, vectorized R code implementing the fixes.
5. **Developer Directives**: Step-by-step instructions for developer agents to integrate the solution.
