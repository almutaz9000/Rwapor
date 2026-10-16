# FAO WaPOR v3 Indicators & Water Accounting Catalog Reference

This document serves as the comprehensive mathematical, physical, and agronomic catalog for all performance indicators, water accounting metrics, and spatial statistics evaluated within the `Rwapor` R package.

---

## 1. Biophysical Fluxes & Fundamental Accounting

| Symbol | Parameter Name | Units | Temporal Step | Physics / Formulation |
| :--- | :--- | :--- | :--- | :--- |
| **AETI** | Actual Evapotranspiration & Interception | $mm/\text{period}$ | Dekad, Month, Season | $AETI = E + T + I$ |
| **T** | Canopy Transpiration | $mm/\text{period}$ | Dekad, Month, Season | Penman-Monteith stomatal vapor flux |
| **E** | Soil Evaporation | $mm/\text{period}$ | Dekad, Month, Season | Penman-Monteith soil capillary vapor flux |
| **I** | Canopy Rainfall Interception | $mm/\text{period}$ | Dekad, Month, Season | Evaporation of foliage-stored moisture |
| **RET** | Reference Evapotranspiration | $mm/\text{period}$ | Daily, Dekadal, Monthly | FAO-56 Penman-Monteith ($0.12\text{ m}$ grass) |
| **PCP** | Precipitation | $mm/\text{period}$ | Daily, Dekadal, Monthly | CHIRPS / IMERG gauge-adjusted rainfall |
| **NPP** | Net Primary Production | $gC/m^2/\text{period}$ | Dekadal, Seasonal | Monteith $LUE \times fAPAR \times PAR$ |
| **RSM** | Relative Root Zone Soil Moisture | $0 - 1$ | Dekadal | Available soil moisture fraction in root zone |

---

## 2. Irrigation Performance Indicators

### A. Adequacy ($A$)
Measures the degree to which crop water requirements are met by actual moisture availability:
$$A = \frac{\text{AETI}}{\text{ET}_c} = \frac{AETI}{K_c \times RET}$$
- **Good / Optimal:** $A \ge 0.80$ (Crop transpires with minimal stomatal closure).
- **Acceptable:** $0.68 \le A < 0.80$ (Slight moisture stress; yield impact mild).
- **Poor / Critical Deficit:** $A < 0.68$ (Severe moisture stress; wilting and yield loss).

### B. Relative Water Deficit ($RD$)
Quantifies the unfulfilled potential evapotranspiration demand:
$$RD = \max\left(0, 1 - \frac{\text{AETI}}{\text{ET}_c}\right)$$

### C. Beneficial Transpiration Fraction ($BF$)
The proportion of total evapotranspiration consumed beneficially through plant stomata for carbon assimilation versus non-productive evaporation:
$$BF = \frac{T}{\text{AETI}} \quad (0 \le BF \le 1)$$
- Values $> 0.80$ indicate mature, closed crop canopies with dry inter-row soil surfaces.
- Low values ($< 0.50$) indicate significant water losses via soil evaporation (e.g. open canopies or leaky surface irrigation).

### D. Effective Precipitation ($P_{\text{eff}}$)
Precipitation available to meet crop water demand, excluding deep percolation and surface runoff (USDA Soil Conservation Service method):
$$P_{\text{eff}} = \begin{cases} 
P_{\text{month}} \times \frac{125 - 0.2 \times P_{\text{month}}}{125} & \text{if } P_{\text{month}} \le 250\text{ mm} \\
125 + 0.1 \times P_{\text{month}} & \text{if } P_{\text{month}} > 250\text{ mm}
\end{cases}$$

### E. Net Irrigation Requirement (NIR)
Deficit between crop water requirement and effective rainfall:
$$\text{NIR} = \max(0, \text{ET}_c - P_{\text{eff}}) \quad [\text{mm}]$$

---

## 3. Water Accounting Plus (WA+) Framework

The `Rwapor` package implements the standard WA+ mass-balance separation of water consumption into source origins:

### A. Green Water Consumption ($ET_{\text{green}}$)
The portion of actual evapotranspiration sustained by infiltrated rainwater stored in the unsaturated root zone:
$$\text{AETI}_{\text{green}} = \min(\text{AETI}_{\text{seasonal}}, P_{\text{eff, seasonal}}) \quad [\text{mm}]$$

### B. Blue Water Consumption ($ET_{\text{blue}}$)
The portion of actual evapotranspiration withdrawn from managed surface water bodies, canals, groundwater pumping, or storage reservoirs:
$$\text{AETI}_{\text{blue}} = \max(0, \text{AETI}_{\text{seasonal}} - P_{\text{eff, seasonal}}) \quad [\text{mm}]$$

### C. Rainfed ET & Rainfall Surplus
- **Rainfed Consumptive ET:** $ET_{\text{rain}} = \min(AETI, PCP)$
- **Rainfall Surplus (Potential Groundwater Recharge / Runoff):**
  $$\text{Surplus} = \max(0, PCP - AETI)$$

---

## 4. Agricultural Water Productivity ($WP$)

Water productivity measures the physical or financial yield output per unit of water consumed ($AETI$).

### A. Biomass Water Productivity ($WP_b$)
$$WP_b = \frac{B \times 1,000}{\text{AETI} \times 10} = \frac{B \times 100}{\text{AETI}} \quad \left[\text{kgDM/m}^3\right]$$
where:
- $B$ is Above-Ground Biomass in $\text{t/ha}$:
  $$B = \frac{\text{AOT} \times f_c \times \text{NPP}_{\text{seasonal}} \times 22.222}{1000 \times (1 - m_c)}$$
- $AETI$ is seasonal actual evapotranspiration in $mm$.

### B. Crop Water Productivity ($CWP$)
$$CWP = \frac{Y \times 1,000}{\text{AETI} \times 10} = \frac{Y \times 100}{\text{AETI}} \quad \left[\text{kg/m}^3\right]$$
where $Y = B \times \text{HI}$ is marketable crop yield in $\text{t/ha}$.

### C. Climate-Normalized Water Productivity ($WP^*$)
Removes the confounding influence of atmospheric evaporative demand ($RET$) to allow fair benchmarking across different climates or seasons:
$$WP^* = WP \times \frac{\text{RET}_{\text{local}}}{\text{RET}_{\text{regional\_mean}}}$$

---

## 5. Spatial Uniformity & Equity Statistics

### A. Within-Field Uniformity ($U$)
Evaluates whether water is distributed evenly across a cultivated field:
$$U = 1 - \text{CV}_{\text{within}}(\text{AETI}) = 1 - \frac{\sigma_{\text{field}}}{\mu_{\text{field}}}$$
- Excellent: $U \ge 0.85$
- Acceptable: $0.70 \le U < 0.85$
- Poor (Non-uniform application): $U < 0.70$

### B. Between-Fields Equity ($E_{\text{equity}}$)
Measures fairness of water access across upstream vs. downstream irrigation parcels:
$$E_{\text{equity}} = \text{CV}_{\text{between}}(\text{AETI}_{\text{parcels}}) = \frac{\sigma_{\text{scheme}}}{\mu_{\text{scheme}}}$$
- Good: $E_{\text{equity}} < 10\%$
- Fair: $10\% \le E_{\text{equity}} \le 25\%$
- Poor (Severe head-to-tail inequity): $E_{\text{equity}} > 25\%$

### C. Theil Inequality Index ($T_{\text{Theil}}$)
Entropy-based equity metric sensitive to outliers at the tails of the distribution:
$$T_{\text{Theil}} = \frac{1}{N} \sum_{i=1}^N \frac{x_i}{\bar{x}} \ln\left( \frac{x_i}{\bar{x}} \right)$$
where $x_i$ is $AETI$ in parcel $i$ and $\bar{x}$ is scheme-wide mean $AETI$. Values near $0$ indicate perfect spatial equality.
