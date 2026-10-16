# WaPOR Expert Agent Architecture & Specification

## 1. Overview
The **WaPOR Expert Agent** operates as an automated domain-architect, methodology auditor, and technical reviewer during the development and maintenance of the `Rwapor` R package. It ensures complete adherence to FAO WaPOR v3 standards, remote sensing energy balance principles, spatial raster best practices in R, and agronomic mathematical formulations.

```
                  ┌─────────────────────────────────────────┐
                  │           WaPOR Expert Agent            │
                  │   (Methodology, API, & Math Auditor)    │
                  └────────────────────┬────────────────────┘
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         ▼                             ▼                             ▼
┌──────────────────┐         ┌──────────────────┐         ┌──────────────────┐
│ API & Spatial    │         │ Agronomic Math   │         │ R Code Review &  │
│ Verification     │         │ & Formula Check  │         │ Recommendations  │
└──────────────────┘         └──────────────────┘         └──────────────────┘
```

---

## 2. Core Agent Skills

The WaPOR Expert Agent is equipped with four specialized domain skills:

### 1. `wapor-api-layer-validator`
- **Purpose**: Validates FAO WaPOR API query constructions, endpoint parameters, catalog versions (v1.0, v2.1, v3.0), spatial resolution levels (L1 = 300m/250m, L2 = 100m, L3 = 20m/30m), temporal steps (daily, dekadal, monthly, annual), and bounding box / AOI spatial filters.
- **Checks**: Translates legacy v1/v2 layer names to v3 catalog IDs (e.g., `L2_AETI_D` $\to$ `v3.0/L2-AETI-D`), validates L3 scheme boundaries, manages token authentication, and enforces exponential backoff.

### 2. `spatial-raster-auditor`
- **Purpose**: Monitors raster processing operations in R (`terra`, `sf`, `stars`).
- **Checks**: Verifies native Coordinate Reference Systems (WGS84 / EPSG:4326), proper resampling methods (Nearest Neighbor for discrete/categorical layers like crop masks and coarse climate; Bilinear/Cubic for continuous vegetation layers like $AETI$ or $NPP$), NoData value masking, and Cloud-Optimized GeoTIFF (COG) windowed reads via `/vsicurl/`.

### 3. `agronomic-math-verifier`
- **Purpose**: Audits and enforces mathematical correctness for energy balance, biomass conversions, yield estimates, and irrigation performance indicators.
- **Checks**:
  - Exact calendar day weighting per dekad (8, 9, 10, or 11 days).
  - NPP to DMP unit conversion: $1\text{ gC/m}^2/\text{day} = 22.222\text{ kgDM/ha/day}$.
  - Above-ground biomass ($B$ in $\text{t/ha}$) and fresh crop moisture content ($m_c$) adjustment:
    $$B = \frac{\text{AOT} \times f_c \times \text{NPP}_{\text{seasonal}} \times 22.222}{1000 \times (1 - m_c)}$$
  - Crop yield ($Y = B \times \text{HI}$).
  - FAO-56 4-stage time-interpolated $K_c$ curves ($ET_c = K_c \times \text{RET}$).
  - Indicators: Adequacy, Relative Deficit, NIR, Uniformity, Equity, and Crop Water Productivity ($WP_b$, $WP^*$).

### 4. `rwapor-code-reviewer`
- **Purpose**: Inspects R function implementations, pipeline logic, memory efficiency (avoiding unnecessary in-memory raster loads), and vectorization.
- **Checks**: Vectorized raster operations (prohibiting cell-by-cell loops), strict input assertions, roxygen2 documentation, and structured evaluation reports.

---

## 3. Subagent Runtime Activation

In interactive agent environments (such as Antigravity / Gemini CLI), the subagent is registered as `wapor_expert_agent`.

To invoke the agent:
```
invoke_subagent(
  Subagents = [
    {
      TypeName: "wapor_expert_agent",
      Role: "WaPOR Methodology Auditor",
      Prompt: "Audit the implementation of R/seasonal_analysis.R for dekadal day weighting and FAO-56 Kc interpolation."
    }
  ]
)
```

---

## 4. Standard Recommendation Output Schema

When conducting formal audits or reviewing pull requests, the agent outputs recommendations in the following format:

1. **Status Overview**: PASS / WARNING / FAIL assessment.
2. **Methodology & Mathematical Audit**: Identification of formula, unit, or spatial resolution mismatches.
3. **API & Spatial Processing Audit**: Identification of projection, resampling, or API endpoint issues.
4. **Refactored R Code Snippet**: Production-ready, vectorized R code implementing the fixes.
5. **Developer Directives**: Step-by-step instructions for developer agents to integrate the solution.
