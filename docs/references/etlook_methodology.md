# ETLook Methodology & Biophysical Components Reference

This document provides the foundational theoretical, mathematical, and algorithmic reference for the **ETLook model** used by the FAO WaPOR (Water Productivity through Open access of Remotely sensed derived data) monitoring system. It serves as an authoritative ground-truth reference for the **WaPOR Expert Agent** and developer agents working on the `Rwapor` R package.

---

## 1. Overview & Architectural Framework

**ETLook** is a physical two-layer energy balance and Penman-Monteith remote sensing model originally developed by **eLEAF / WaterWatch**. It solves the surface energy balance separately for two distinct components of the land surface:
1. **The Canopy Layer** (Vegetation cover transpiring water through stomata).
2. **The Soil Layer** (Bare soil surface evaporating moisture from topsoil capillaries).

In addition, ETLook explicitly accounts for **Canopy Rainfall Interception ($I$)**, yielding the core water conservation equation:

$$\mathbf{AETI = E + T + I}$$

where:
- $AETI$ = Actual Evapotranspiration and Interception [$mm/\text{day}$ or $mm/\text{period}$]
- $E$ = Soil Evaporation [$mm/\text{day}$]
- $T$ = Canopy Transpiration [$mm/\text{day}$]
- $I$ = Canopy Interception Evaporation [$mm/\text{day}$]

---

## 2. The Surface Energy Balance Formulation

The instantaneous surface energy balance states that net available radiation is consumed by soil heat conduction, sensible heat convection into the atmosphere, and latent heat of vaporization:

$$R_n - G - H - \lambda E = 0$$

where:
- $R_n$ = Net radiation flux at the surface [$W/m^2$]
- $G$ = Soil heat flux [$W/m^2$]
- $H$ = Sensible heat flux [$W/m^2$]
- $\lambda E$ = Latent heat flux [$W/m^2$] ($\lambda \approx 2.45 \times 10^6 \text{ J/kg}$, the latent heat of vaporization)

### Two-Layer Radiation Partitioning
Net radiation is partitioned between vegetation canopy ($R_{n,\text{canopy}}$) and bare soil ($R_{n,\text{soil}}$) using fractional vegetation cover ($f_{\text{cover}}$) derived from the Normalized Difference Vegetation Index ($NDVI$):

$$f_{\text{cover}} = 1 - \left( \frac{NDVI_{\max} - NDVI}{NDVI_{\max} - NDVI_{\min}} \right)^{0.6175}$$

1. **Net Canopy Radiation ($R_{n,\text{canopy}}$)**:
   $$R_{n,\text{canopy}} = (1 - \alpha_{\text{canopy}}) R_{s\downarrow} + \epsilon_{\text{canopy}} R_{l\downarrow} - R_{l\uparrow,\text{canopy}}$$
   where $\alpha_{\text{canopy}}$ is canopy surface albedo, $\epsilon_{\text{canopy}}$ is canopy emissivity, $R_{s\downarrow}$ is incoming solar shortwave radiation, and $R_{l\downarrow}, R_{l\uparrow}$ are atmospheric and surface longwave radiation.

2. **Net Soil Radiation ($R_{n,\text{soil}}$)**:
   $$R_{n,\text{soil}} = (1 - \alpha_{\text{soil}}) R_{s\downarrow} + \epsilon_{\text{soil}} R_{l\downarrow} - R_{l\uparrow,\text{soil}}$$

3. **Soil Heat Flux ($G$) Parameterization**:
   Unlike vegetation which stores negligible diurnal energy, soil conducts heat into the subsurface:
   $$G = R_{n,\text{soil}} \left[ c_{\text{bare}} + (c_{\text{full}} - c_{\text{bare}}) f_{\text{cover}} \right]$$
   During the daytime, $G / R_{n,\text{soil}}$ ranges between $0.05$ (dense canopy) and $0.35$ (completely bare desert soil).

---

## 3. Two-Layer Penman-Monteith Equations

ETLook solves Penman-Monteith equations independently for the canopy and soil layers.

### A. Canopy Transpiration ($\lambda T$)
Transpiration is governed by atmospheric demand, available canopy net radiation, and stomatal plus aerodynamic resistance:

$$\lambda T = \frac{\Delta \cdot R_{n,\text{canopy}} + \frac{\rho_a c_p (e_s - e_a)}{r_{a,\text{canopy}}}}{\Delta + \gamma \left( 1 + \frac{r_{s,\text{canopy}}}{r_{a,\text{canopy}}} \right)}$$

where:
- $\Delta = \frac{d e_s}{d T}$ = Slope of the saturated vapor pressure-temperature curve [$kPa/^\circ C$]
- $\rho_a$ = Atmospheric air density [$\approx 1.225 \text{ kg/m}^3$]
- $c_p$ = Specific heat capacity of dry air [$\approx 1013 \text{ J}/(\text{kg}\cdot^\circ C)$]
- $(e_s - e_a)$ = Vapor Pressure Deficit ($VPD$) of the atmosphere [$kPa$]
- $\gamma$ = Psychrometric constant [$\approx 0.066 \text{ kPa}/^\circ C$ at sea level]
- $r_{a,\text{canopy}}$ = Aerodynamic resistance to vapor transport from canopy to reference height [$s/m$]
- $r_{s,\text{canopy}}$ = Bulk stomatal canopy resistance [$s/m$]

### B. Soil Evaporation ($\lambda E$)
Soil evaporation is governed by available energy ($R_{n,\text{soil}} - G$) and soil capillary resistance:

$$\lambda E = \frac{\Delta \cdot (R_{n,\text{soil}} - G) + \frac{\rho_a c_p (e_s - e_a)}{r_{a,\text{soil}}}}{\Delta + \gamma \left( 1 + \frac{r_{s,\text{soil}}}{r_{a,\text{soil}}} \right)}$$

where:
- $r_{a,\text{soil}}$ = Aerodynamic resistance between soil surface and reference height [$s/m$]
- $r_{s,\text{soil}}$ = Dry soil surface resistance [$s/m$]

---

## 4. Resistance Formulations & Environmental Stress Functions

### A. Canopy Stomatal Resistance ($r_{s,\text{canopy}}$)
Bulk canopy resistance is modeled via the Jarvis-Stewart multiplicative stress framework:

$$r_{s,\text{canopy}} = \frac{r_{s,\min}}{LAI_{\text{eff}} \times f(R_s) \times f(VPD) \times f(T_{\text{air}}) \times S_t}$$

where:
- $r_{s,\min}$ = Minimum unstressed stomatal resistance for the crop/biome [typical range: $50 - 150 \text{ s/m}$].
- $LAI_{\text{eff}} = \frac{LAI}{0.5 \times LAI + 1}$ = Effective Leaf Area Index intercepting active solar radiation.
- $f(R_s)$ = Solar radiation stress response factor ($0 \le f(R_s) \le 1$).
- $f(VPD)$ = Vapor pressure deficit stress response factor ($0 \le f(VPD) \le 1$).
- $f(T_{\text{air}})$ = Air temperature response factor ($0 \le f(T_{\text{air}}) \le 1$).
- $\mathbf{S_t}$ = **Root Zone Soil Moisture Stress Factor** ($0 \le S_t \le 1$).
  - Derived from WaPOR Relative Root Zone Soil Moisture ($RSM$):
    $$S_t = \max\left( 0, \min\left( 1, \frac{RSM - RSM_{\text{wilt}}}{RSM_{\text{crit}} - RSM_{\text{wilt}}} \right) \right)$$
  - When $RSM > RSM_{\text{crit}}$, vegetation transpires unstressed ($S_t = 1$).
  - When $RSM \le RSM_{\text{wilt}}$, stomata close completely ($S_t = 0 \Rightarrow r_{s,\text{canopy}} \to \infty$).

### B. Soil Surface Resistance ($r_{s,\text{soil}}$)
Soil evaporation resistance depends exponentially on topsoil moisture saturation ($S_e$):

$$r_{s,\text{soil}} = r_{\text{soil},\min} \times \exp\left( c_{\text{soil}} \times (1 - S_e) \right)$$

where:
- $S_e$ is the topsoil relative moisture saturation (derived from microwave brightness temperature / soil moisture indices).
- When the soil surface is saturated ($S_e = 1$), $r_{s,\text{soil}} = r_{\text{soil},\min} \approx 50 \text{ s/m}$ (evaporation proceeds near potential rate).
- When the soil dries out ($S_e \to 0$), $r_{s,\text{soil}}$ rises into thousands of $s/m$, choking off soil evaporation.

### C. Aerodynamic Resistances ($r_{a,\text{canopy}}$ and $r_{a,\text{soil}}$)
Aerodynamic resistance represents turbulent transport resistance driven by wind speed and surface roughness:

$$r_a = \frac{\ln\left( \frac{z_m - d}{z_{0m}} - \Psi_m \right) \ln\left( \frac{z_h - d}{z_{0h}} - \Psi_h \right)}{k^2 u_z}$$

where:
- $k = 0.41$ (von Kármán's constant)
- $u_z$ = Wind speed measured at reference height $z_m$ [$m/s$]
- $d = \frac{2}{3} h_{\text{veg}}$ = Zero plane displacement height [$m$]
- $z_{0m} = 0.123 \times h_{\text{veg}}$ = Roughness length for momentum [$m$]
- $z_{0h} = 0.1 \times z_{0m}$ = Roughness length for heat and vapor [$m$]
- $\Psi_m, \Psi_h$ = Monin-Obukhov atmospheric stability correction functions.

---

## 5. Canopy Rainfall Interception ($I$)

Water intercepted by vegetative foliage evaporates directly back into the atmosphere at potential rates before reaching the ground. In ETLook, daily interception is parameterized as:

$$I = \min\left( PCP, S_{\max} \left[ 1 - \exp\left( -\frac{k_{\text{int}} \times PCP}{S_{\max}} \right) \right] \right)$$

where:
- $PCP$ = Precipitation depth [$mm/\text{day}$]
- $S_{\max} = c_{\text{int}} \times LAI$ = Maximum canopy water storage capacity [$mm$] ($c_{\text{int}} \approx 0.2 - 0.25 \text{ mm}$ per unit $LAI$)
- $k_{\text{int}}$ = Canopy extinction coefficient for precipitation ($\approx 0.5$).

---

## 6. Net Primary Production ($NPP$) & Biomass Conversion

ETLook couples water consumption directly to carbon assimilation via the Monteith Light Use Efficiency ($LUE$) model:

$$NPP = fAPAR \times PAR \times LUE_{\max} \times f(T_{\text{air}}) \times f(W) \times f(\text{CO}_2)$$

where:
- $fAPAR$ = Fraction of Absorbed Photosynthetically Active Radiation (modeled from $NDVI$)
- $PAR$ = Photosynthetically Active Radiation [$\approx 0.48 \times R_{s\downarrow}$, $MJ/m^2/day$]
- $LUE_{\max}$ = Maximum biome light use efficiency [$gC / MJ$]
- $f(W)$ = Moisture availability factor (linked to Transpiration ratio $T / T_{\text{pot}}$)

### Dry Matter Production (DMP) Scaling:
$$1 \text{ gC/m}^2/\text{day} = 22.222 \text{ kgDM/ha/day}$$
$$\text{Conversion derivation: } \frac{10,000 \text{ m}^2/\text{ha}}{1,000 \text{ g/kg} \times 0.45 \text{ gC/gDM}} = 22.222$$

---

## 7. Critical Audit Checks for `Rwapor` Implementations

When auditing or reviewing `Rwapor` packages and seasonal engines:

1. **Mass Balance Identity**:
   - $AETI$ must always equal the sum of its constituents:
     $$\mathbf{AETI \equiv E + T + I}$$
   - Any analytical workflow where $E + T + I \neq AETI$ (beyond floating-point precision $< 10^{-4}$) indicates corrupted raster extraction or mismatched layer versions.
2. **Transpiration Fraction ($T / AETI$)**:
   - The beneficial transpiration fraction must be bounded:
     $$0.0 \le \frac{T}{AETI} \le 1.0$$
   - Over fully vegetated mid-season crops with dry soil surface, $T/AETI \to 0.85 - 0.95$.
   - Over flooded paddy rice or post-irrigation bare fields, $T/AETI$ drops as soil/water evaporation dominates.
3. **Dekadal Duration Weighting**:
   - Because ETLook outputs mean daily flux ($mm/\text{day}$), seasonal summation must strictly multiply each dekad by its exact calendar duration ($8, 9, 10, 11\text{ days}$).
