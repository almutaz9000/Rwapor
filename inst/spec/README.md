# Seasonal analysis indicators

This page is the GitHub-readable view of the same catalogue as
[indicators.yaml](indicators.yaml). The YAML file remains the machine-readable
source of truth (synced with `wapor_list_indicator_steps()`). Edit the YAML,
then run `python scripts/render_indicator_catalogue.py` so this page stays aligned.

**Package:** Rwapor 1.0.6  
**Count:** 24 built-in indicators

Canonical cross-implementation specification of seasonal agricultural water accounting, energy balance, biomass, and irrigation performance indicators shared between Rwapor (R) and waporbox (Python).

## Notation

- Subscript `d` is a dekad; subscript `m` is a calendar month.
- `w_d` is the season weight in [0, 1].
- `days_d` is the number of days in that dekad (usually 8 to 11).
- Division by a zero denominator is returned as NA.
- Green water, blue water, ET_rain, rainfall surplus, and NIR are summed from
  monthly layers. Do not compute them from seasonal totals.

## Summary

| Code | Indicator | Category | Units out |
| --- | --- | --- | --- |
| `agg_aeti` | Seasonal Actual Evapotranspiration and Interception (AETI) | Evapotranspiration | mm/season |
| `agg_t` | Seasonal Transpiration (T) | Evapotranspiration | mm/season |
| `agg_ret` | Seasonal Reference Evapotranspiration (RET) | Evapotranspiration | mm/season |
| `agg_pcp` | Seasonal Gross Precipitation (PCP) | Water supply | mm/season |
| `agg_npp` | Seasonal Net Primary Production (NPP) | Biomass and yield | gC/m2/season |
| `agg_peff` | Seasonal Effective Precipitation (Peff, USDA SCS / Brouwer & Heibloem) | Water supply | mm/season |
| `etc` | Seasonal Crop Water Requirement (ETc) | Evapotranspiration | mm/season |
| `adequacy_etc` | ETc-based Water Adequacy (Relative Evapotranspiration) | Irrigation performance | 1 |
| `adequacy_p95` | P95-based Relative Water Adequacy | Irrigation performance | 1 |
| `beneficial_fraction` | Beneficial Transpiration Fraction (T / AETI) | Irrigation performance | 1 |
| `peff_green_blue` | Effective Precipitation, Green & Blue Water Partitioning | Water supply | mm/season |
| `green_water` | Seasonal Green Water Evapotranspiration (ET_green) | Water supply | mm/season |
| `blue_water` | Seasonal Blue Water Evapotranspiration (ET_blue) | Water supply | mm/season |
| `et_rain` | Rain-fed Evapotranspiration Component (ET_rain) | Water supply | mm/season |
| `rainfall_surplus` | Seasonal Rainfall Surplus (P - ET_rain) | Water supply | mm/season |
| `nir` | Net Irrigation Requirement (NIR) | Irrigation performance | mm/season |
| `agg_biomass_kg` | Seasonal Total Biomass Production (TBP, kg/ha) | Biomass and yield | kg/ha |
| `agg_biomass_t` | Seasonal Total Biomass Production (TBP, t/ha) | Biomass and yield | t/ha |
| `yield_npp` | Fresh Crop Yield from NPP | Biomass and yield | t/ha |
| `cwp_bwp` | Crop and Biomass Water Productivity (CWP & BWP) | Water productivity | kg/m3 |
| `nbwp` | Net Biomass Water Productivity (NBWP = Biomass / T) | Water productivity | kg/m3 |
| `variability` | Spatial Uniformity and Equity (CV & Theil Index) | Irrigation performance | %, 1 |
| `cv_aeti` | Spatial Coefficient of Variation of AETI (CV) | Irrigation performance | % |
| `theil_aeti` | Theil Entropy Index of Spatial Water Equity (T) | Irrigation performance | 1 |

## Definitions, equations, and citations

### 1. `agg_aeti`

**Seasonal Actual Evapotranspiration and Interception (AETI)**

- Category: Evapotranspiration
- Status: implemented
- Equation: `sum_d(AETI_d * days_d * w_d)`
- Units in: `mm/day`
- Units out: `mm/season`
- Dekad rule: `multiply_by_dekad_days_once`
- Inputs: `aeti`
- R function: `wapor_run_seasonal_analysis`
- Python function: `run_seasonal_analysis`
- Citation: FAO (2020). WaPOR Database Methodology: Version 2 Release, April 2020. Rome, FAO.

### 2. `agg_t`

**Seasonal Transpiration (T)**

- Category: Evapotranspiration
- Status: implemented
- Equation: `sum_d(T_d * days_d * w_d)`
- Units in: `mm/day`
- Units out: `mm/season`
- Dekad rule: `multiply_by_dekad_days_once`
- Inputs: `t`
- R function: `wapor_run_seasonal_analysis`
- Python function: `run_seasonal_analysis`
- Citation: FAO (2020). WaPOR Database Methodology: Version 2 Release, April 2020. Rome, FAO.

### 3. `agg_ret`

**Seasonal Reference Evapotranspiration (RET)**

- Category: Evapotranspiration
- Status: implemented
- Equation: `sum_d(RET_d * days_d * w_d)`
- Units in: `mm/day`
- Units out: `mm/season`
- Dekad rule: `multiply_by_dekad_days_once`
- Inputs: `ret`
- R function: `wapor_run_seasonal_analysis`
- Python function: `run_seasonal_analysis`
- Citation: Allen, R. G., Pereira, L. S., Raes, D., & Smith, M. (1998). Crop evapotranspiration: Guidelines for computing crop water requirements. FAO Irrigation and Drainage Paper 56.

### 4. `agg_pcp`

**Seasonal Gross Precipitation (PCP)**

- Category: Water supply
- Status: implemented
- Equation: `sum_d(PCP_d * days_d * w_d)`
- Units in: `mm/day`
- Units out: `mm/season`
- Dekad rule: `multiply_by_dekad_days_once`
- Inputs: `pcp`
- R function: `wapor_run_seasonal_analysis`
- Python function: `run_seasonal_analysis`
- Citation: FAO (2020). WaPOR Database Methodology: Version 2 Release, April 2020. Rome, FAO.

### 5. `agg_npp`

**Seasonal Net Primary Production (NPP)**

- Category: Biomass and yield
- Status: implemented
- Equation: `sum_d(NPP_d * days_d * w_d)`
- Units in: `gC/m2/day`
- Units out: `gC/m2/season`
- Dekad rule: `multiply_by_dekad_days_once`
- Inputs: `npp`
- R function: `wapor_run_seasonal_analysis`
- Python function: `run_seasonal_analysis`
- Citation: FAO (2020). WaPOR Database Methodology: Version 2 Release, April 2020. Rome, FAO.

### 6. `agg_peff`

**Seasonal Effective Precipitation (Peff, USDA SCS / Brouwer & Heibloem)**

- Category: Water supply
- Status: implemented
- Equation: `sum_m(Peff(P_m)), where Peff(P_m) = P_m * (125 - 0.2 * P_m) / 125 for P_m <= 250 mm else 125 + 0.1 * P_m`
- Units in: `mm/month`
- Units out: `mm/season`
- Dekad rule: `aggregate_to_monthly_then_apply_peff`
- Inputs: `pcp`
- R function: `wapor_calc_monthly_precip_peff_rasters`
- Python function: `calc_monthly_peff`
- Citation: Brouwer, C., & Heibloem, M. (1986). Irrigation Water Management: Irrigation Water Needs. Training Manual No. 3, FAO, Rome.

### 7. `etc`

**Seasonal Crop Water Requirement (ETc)**

- Category: Evapotranspiration
- Status: implemented
- Equation: `sum_d(Kc(d) * RET_d * days_d * w_d)`
- Units in: `mm/day`
- Units out: `mm/season`
- Dekad rule: `stage_weighted_kc_times_dekad_ret`
- Inputs: `aeti`, `ret`
- R function: `wapor_calc_etc_by_class`
- Python function: `calc_seasonal_etc`
- Citation: Allen, R. G., Pereira, L. S., Raes, D., & Smith, M. (1998). FAO Irrigation and Drainage Paper 56, Eq. 56 & 62.

### 8. `adequacy_etc`

**ETc-based Water Adequacy (Relative Evapotranspiration)**

- Category: Irrigation performance
- Status: implemented
- Equation: `AETI_seasonal / ETc_seasonal (masked where ETc <= 0)`
- Units in: `mm/season`
- Units out: `1`
- Dekad rule: `ratio_of_seasonal_totals`
- Inputs: `aeti`, `ret`
- R function: `wapor_calc_adequacy_etc`
- Python function: `calc_adequacy_etc`
- Citation: Molden, D., & Gates, T. K. (1990). Performance measures for evaluation of irrigation-water-delivery systems. Journal of Irrigation and Drainage Engineering, 116(6), 804-823; Bos, M. G., Burton, M. A., & Molden, D. J. (2005). Irrigation and Drainage Performance Assessment: Practical Guidelines. CABI.

### 9. `adequacy_p95`

**P95-based Relative Water Adequacy**

- Category: Irrigation performance
- Status: implemented
- Equation: `AETI_seasonal / P95_class(AETI_seasonal)`
- Units in: `mm/season`
- Units out: `1`
- Dekad rule: `ratio_to_global_class_p95`
- Inputs: `aeti`
- R function: `wapor_calc_adequacy_p95`
- Python function: `calc_adequacy_p95`
- Citation: Bastiaanssen, W. G. M., & Bos, M. G. (1999). Irrigation performance indicators based on remotely sensed data: a review of literature. Irrigation and Drainage Systems, 13(4), 291-311.

### 10. `beneficial_fraction`

**Beneficial Transpiration Fraction (T / AETI)**

- Category: Irrigation performance
- Status: implemented
- Equation: `pmin(1, pmax(0, T_seasonal / AETI_seasonal))`
- Units in: `mm/season`
- Units out: `1`
- Dekad rule: `ratio_of_seasonal_totals`
- Inputs: `aeti`, `t`
- R function: `wapor_calc_beneficial_fraction`
- Python function: `calc_beneficial_fraction`
- Citation: Karimi, P., Bastiaanssen, W. G. M., & Molden, D. (2013). Water Accounting Plus (WA+) - a water accounting procedure for complex river basins based on satellite measurements. Hydrology and Earth System Sciences, 17(7), 2459-2472.

### 11. `peff_green_blue`

**Effective Precipitation, Green & Blue Water Partitioning**

- Category: Water supply
- Status: implemented
- Equation: `Composite step computing seasonal_peff, green_water = sum_m(min(AETI_m, Peff_m)), and blue_water = sum_m(max(0, AETI_m - Peff_m))`
- Units in: `mm/month`
- Units out: `mm/season`
- Dekad rule: `monthly_split_then_seasonal_sum`
- Inputs: `aeti`, `pcp`
- R function: `wapor_calc_green_water`
- Python function: `calc_green_blue_water`
- Citation: Hoekstra, A. Y., Chapagain, A. K., Aldaya, M. M., & Mekonnen, M. M. (2011). The Water Footprint Assessment Manual. Earthscan; Karimi et al. (2013).

### 12. `green_water`

**Seasonal Green Water Evapotranspiration (ET_green)**

- Category: Water supply
- Status: implemented
- Equation: `sum_m(pmin(AETI_m, Peff_m))`
- Units in: `mm/month`
- Units out: `mm/season`
- Dekad rule: `monthly_split_then_seasonal_sum`
- Inputs: `aeti`, `pcp`
- R function: `wapor_calc_green_water`
- Python function: `calc_green_water`
- Citation: Hoekstra, A. Y., Chapagain, A. K., Aldaya, M. M., & Mekonnen, M. M. (2011). The Water Footprint Assessment Manual. Earthscan.

### 13. `blue_water`

**Seasonal Blue Water Evapotranspiration (ET_blue)**

- Category: Water supply
- Status: implemented
- Equation: `sum_m(pmax(0, AETI_m - Peff_m))`
- Units in: `mm/month`
- Units out: `mm/season`
- Dekad rule: `monthly_split_then_seasonal_sum`
- Inputs: `aeti`, `pcp`
- R function: `wapor_calc_blue_water`
- Python function: `calc_blue_water`
- Citation: Hoekstra, A. Y., Chapagain, A. K., Aldaya, M. M., & Mekonnen, M. M. (2011). The Water Footprint Assessment Manual. Earthscan.

### 14. `et_rain`

**Rain-fed Evapotranspiration Component (ET_rain)**

- Category: Water supply
- Status: implemented
- Equation: `sum_m(pmin(AETI_m, P_m))`
- Units in: `mm/month`
- Units out: `mm/season`
- Dekad rule: `monthly_split_then_seasonal_sum`
- Inputs: `aeti`, `pcp`
- R function: `wapor_calc_et_rain`
- Python function: `calc_et_rain`
- Citation: Karimi, P., Bastiaanssen, W. G. M., & Molden, D. (2013). Water Accounting Plus (WA+). Hydrology and Earth System Sciences, 17(7), 2459-2472.

### 15. `rainfall_surplus`

**Seasonal Rainfall Surplus (P - ET_rain)**

- Category: Water supply
- Status: implemented
- Equation: `sum_m(pmax(0, P_m - pmin(AETI_m, P_m)))`
- Units in: `mm/month`
- Units out: `mm/season`
- Dekad rule: `monthly_split_then_seasonal_sum`
- Inputs: `aeti`, `pcp`
- R function: `wapor_calc_rainfall_surplus`
- Python function: `calc_rainfall_surplus`
- Citation: Karimi, P., Bastiaanssen, W. G. M., & Molden, D. (2013). Water Accounting Plus (WA+). Hydrology and Earth System Sciences, 17(7), 2459-2472.

### 16. `nir`

**Net Irrigation Requirement (NIR)**

- Category: Irrigation performance
- Status: implemented
- Equation: `sum_m(pmax(0, ETc_m - Peff_m))`
- Units in: `mm/month`
- Units out: `mm/season`
- Dekad rule: `monthly_deficit_then_seasonal_sum`
- Inputs: `ret`, `pcp`
- R function: `wapor_calc_nir_et`
- Python function: `calc_nir`
- Citation: Allen, R. G., Pereira, L. S., Raes, D., & Smith, M. (1998). FAO Irrigation and Drainage Paper 56; Brouwer & Heibloem (1986).

### 17. `agg_biomass_kg`

**Seasonal Total Biomass Production (TBP, kg/ha)**

- Category: Biomass and yield
- Status: implemented
- Equation: `NPP_seasonal * 22.222 (where 22.222 = 10 / 0.45 gC/gDM)`
- Units in: `gC/m2/season`
- Units out: `kg/ha`
- Dekad rule: `scale_seasonal_npp_by_22_222`
- Inputs: `npp`
- R function: `wapor_calc_biomass_from_npp`
- Python function: `calc_biomass_kg_ha`
- Citation: FAO (2020). WaPOR Database Methodology: Version 2 Release, April 2020. Rome, FAO.

### 18. `agg_biomass_t`

**Seasonal Total Biomass Production (TBP, t/ha)**

- Category: Biomass and yield
- Status: implemented
- Equation: `(NPP_seasonal * 22.222) / 1000`
- Units in: `gC/m2/season`
- Units out: `t/ha`
- Dekad rule: `scale_seasonal_npp_by_0_022222`
- Inputs: `npp`
- R function: `wapor_calc_biomass_from_npp`
- Python function: `calc_biomass_t_ha`
- Citation: FAO (2020). WaPOR Database Methodology: Version 2 Release, April 2020. Rome, FAO.

### 19. `yield_npp`

**Fresh Crop Yield from NPP**

- Category: Biomass and yield
- Status: implemented
- Equation: `(NPP_seasonal * 22.222 * fc * AOT * HI) / ((1 - MC) * 1000)`
- Units in: `gC/m2/season`
- Units out: `t/ha`
- Dekad rule: `from_seasonal_npp`
- Inputs: `npp`
- R function: `wapor_calc_yield_npp`
- Python function: `calc_yield_npp`
- Citation: Villalobos, F. J., & Fereres, E. (2016). Principles of Agronomy for Sustainable Agriculture. Springer; FAO (2020) WaPOR v2 Methodology.

### 20. `cwp_bwp`

**Crop and Biomass Water Productivity (CWP & BWP)**

- Category: Water productivity
- Status: implemented
- Equation: `CWP = (Yield_t_ha * 1000) / (AETI_mm * 10); BWP = (Biomass_t_ha * 1000) / (AETI_mm * 10)`
- Units in: `t/ha, mm/season`
- Units out: `kg/m3`
- Dekad rule: `ratio_of_seasonal_totals`
- Inputs: `aeti`, `npp`
- R function: `wapor_calc_cwp`
- Python function: `calc_cwp_bwp`
- Citation: Molden, D. (1997). Accounting for Water Use and Productivity. SWIM Paper 1, IWMI; Zwart, S. J., & Bastiaanssen, W. G. M. (2004). Agricultural Water Management, 69(2), 115-133.

### 21. `nbwp`

**Net Biomass Water Productivity (NBWP = Biomass / T)**

- Category: Water productivity
- Status: implemented
- Equation: `(Biomass_t_ha * 1000) / (T_mm * 10)`
- Units in: `t/ha, mm/season`
- Units out: `kg/m3`
- Dekad rule: `ratio_of_seasonal_totals`
- Inputs: `npp`, `t`
- R function: `wapor_calc_nbwp`
- Python function: `calc_nbwp`
- Citation: FAO (2020). WaPOR Database Methodology: Version 2 Release, April 2020. Rome, FAO; Steduto, P., Hsiao, T. C., Raes, D., & Fereres, E. (2009). AquaCrop. Agronomy Journal, 101(3), 426-437.

### 22. `variability`

**Spatial Uniformity and Equity (CV & Theil Index)**

- Category: Irrigation performance
- Status: implemented
- Equation: `Composite step computing cv_aeti (100 * sd / mean) and theil_aeti (mean((x_i / mu) * ln(x_i / mu)))`
- Units in: `mm/season`
- Units out: `%, 1`
- Dekad rule: `spatial_statistics_on_seasonal_aeti`
- Inputs: `aeti`
- R function: `wapor_calc_cv`
- Python function: `calc_variability`
- Citation: Bos, M. G., Burton, M. A., & Molden, D. J. (2005). Irrigation and Drainage Performance Assessment. CABI; Theil, H. (1967). Economics and Information Theory. North-Holland.

### 23. `cv_aeti`

**Spatial Coefficient of Variation of AETI (CV)**

- Category: Irrigation performance
- Status: implemented
- Equation: `100 * sd(AETI_class) / mean(AETI_class)`
- Units in: `mm/season`
- Units out: `%`
- Dekad rule: `spatial_statistics_on_seasonal_aeti`
- Inputs: `aeti`
- R function: `wapor_calc_cv`
- Python function: `calc_cv`
- Citation: Bos, M. G., Burton, M. A., & Molden, D. J. (2005). Irrigation and Drainage Performance Assessment: Practical Guidelines. CABI.

### 24. `theil_aeti`

**Theil Entropy Index of Spatial Water Equity (T)**

- Category: Irrigation performance
- Status: implemented
- Equation: `(1 / N) * sum_i((AETI_i / mean(AETI)) * ln(AETI_i / mean(AETI)))`
- Units in: `mm/season`
- Units out: `1`
- Dekad rule: `spatial_statistics_on_seasonal_aeti`
- Inputs: `aeti`
- R function: `wapor_calc_theil`
- Python function: `calc_theil`
- Citation: Theil, H. (1967). Economics and Information Theory. North-Holland; Bastiaanssen & Bos (1999).

## Machine-readable source

```r
system.file("spec", "indicators.yaml", package = "Rwapor")
```
