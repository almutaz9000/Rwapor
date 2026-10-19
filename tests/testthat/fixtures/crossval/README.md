# Cross-Implementation Golden Fixture (`Rwapor` <-> `waporbox`)

## Grid & Temporal Geometry

- **Spatial grid**: 6 rows × 6 cols (`36` cells), `EPSG:4326`, `xmin = 30.0`, `xmax = 33.0`, `ymin = 30.0`, `ymax = 33.0` (`res = 0.5° × 0.5°`).
- **Temporal coverage**: 6 dekads across January–February 2022 (`ref_year = 2022`):
  - `2022-01-01` (D1): $N_1 = 10\text{ days}$
  - `2022-01-11` (D2): $N_2 = 10\text{ days}$
  - `2022-01-21` (D3): $N_3 = 11\text{ days}$ (January has 31 days)
  - `2022-02-01` (D4): $N_4 = 10\text{ days}$
  - `2022-02-11` (D5): $N_5 = 10\text{ days}$
  - `2022-02-21` (D6): $N_6 = 8\text{ days}$ (2022 is non-leap, February has 28 days)
- **Crop classes (`crop_mask.tif`)**:
  - Rows 1–2 (cells 1–12): Class `1` (Wheat), with cell `6` set to `NA` to test NoData propagation. Season: DOY `1` to `59` (all 6 dekads, $59\text{ days}$).
  - Rows 3–4 (cells 13–24): Class `2` (Maize). Season: DOY `1` to `59` (all 6 dekads, $59\text{ days}$).
  - Rows 5–6 (cells 25–36): Class `3` (Sorghum), with cell `36` set to `NA`. Season: DOY `1` to `41` (first 4 dekads, $41\text{ days}$).

## Hand-Worked Arithmetic for Reference Cells

### Cell 1 (Row 1, Col 1 — Class 1, `32.5°N–33.0°N, 30.0°E–30.5°E`)

- **Daily input rates** (cell offset $\Delta_1 = 0.0$):
  - $\text{AETI}_d = [2.0, 2.5, 3.0, 3.2, 2.8, 2.0]\text{ mm/day}$
  - $\text{RET}_d = [4.0, 4.2, 4.5, 4.8, 5.0, 4.5]\text{ mm/day}$
  - $\text{PCP}_d = [1.5, 2.0, 1.0, 0.5, 1.0, 0.5]\text{ mm/day}$
  - $\text{NPP}_d = [3.0, 3.5, 4.0, 4.2, 3.8, 3.0]\text{ gC/m}^2\text{/day}$
  - $\text{T}_d = [1.4, 1.8, 2.2, 2.4, 2.0, 1.4]\text{ mm/day}$
- **Dekadal totals** ($\text{rate}_d \times N_d$, with $N = [10, 10, 11, 10, 10, 8]$):
  - **January (D1–D3)**:
    - $\text{AETI}_{\text{Jan}} = 2.0(10) + 2.5(10) + 3.0(11) = 20 + 25 + 33 = 78.0\text{ mm}$
    - $\text{RET}_{\text{Jan}} = 4.0(10) + 4.2(10) + 4.5(11) = 40 + 42 + 49.5 = 131.5\text{ mm}$
    - $\text{PCP}_{\text{Jan}} = 1.5(10) + 2.0(10) + 1.0(11) = 15 + 20 + 11 = 46.0\text{ mm}$
    - $\text{NPP}_{\text{Jan}} = 3.0(10) + 3.5(10) + 4.0(11) = 30 + 35 + 44 = 109.0\text{ gC/m}^2$
    - $\text{T}_{\text{Jan}} = 1.4(10) + 1.8(10) + 2.2(11) = 14 + 18 + 24.2 = 56.2\text{ mm}$
  - **February (D4–D6)**:
    - $\text{AETI}_{\text{Feb}} = 3.2(10) + 2.8(10) + 2.0(8) = 32 + 28 + 16 = 76.0\text{ mm}$
    - $\text{RET}_{\text{Feb}} = 4.8(10) + 5.0(10) + 4.5(8) = 48 + 50 + 36 = 134.0\text{ mm}$
    - $\text{PCP}_{\text{Feb}} = 0.5(10) + 1.0(10) + 0.5(8) = 5 + 10 + 4 = 19.0\text{ mm}$
    - $\text{NPP}_{\text{Feb}} = 4.2(10) + 3.8(10) + 3.0(8) = 42 + 38 + 24 = 104.0\text{ gC/m}^2$
    - $\text{T}_{\text{Feb}} = 2.4(10) + 2.0(10) + 1.4(8) = 24 + 20 + 11.2 = 55.2\text{ mm}$
- **Seasonal totals**:
  - $\text{AETI}_{\text{season}} = 78.0 + 76.0 = 154.0\text{ mm}$
  - $\text{RET}_{\text{season}} = 131.5 + 134.0 = 265.5\text{ mm}$
  - $\text{PCP}_{\text{season}} = 46.0 + 19.0 = 65.0\text{ mm}$
  - $\text{NPP}_{\text{season}} = 109.0 + 104.0 = 213.0\text{ gC/m}^2$
  - $\text{T}_{\text{season}} = 56.2 + 55.2 = 111.4\text{ mm}$
- **USDA SCS Monthly Effective Precipitation & Green/Blue Split**:
  - $P_{\text{eff,Jan}} = 46.0 \times (125 - 0.2 \times 46.0) / 125 = 42.6144\text{ mm}$
  - $P_{\text{eff,Feb}} = 19.0 \times (125 - 0.2 \times 19.0) / 125 = 18.4224\text{ mm}$
  - $P_{\text{eff,season}} = 42.6144 + 18.4224 = 61.0368\text{ mm}$
  - $\text{Green}_{\text{season}} = \min(78.0, 42.6144) + \min(76.0, 18.4224) = 61.0368\text{ mm}$
  - $\text{Blue}_{\text{season}} = (78.0 - 42.6144) + (76.0 - 18.4224) = 92.9632\text{ mm}$
- **Biomass, Yield & Water Productivity** (Class 1: $f_c = 0.45$, $\text{AOT} = 0.80$, $\text{HI} = 0.40$, $\text{MC} = 0.15$):
  - $\text{Biomass}_{\text{kg/ha}} = 213.0 \times (0.80 \times 10 / 0.45) = 3786.6667\text{ kg/ha}$
  - $\text{Biomass}_{\text{t/ha}} = 3.7866667\text{ t/ha}$
  - $\text{Yield}_{\text{t/ha}} = 3.7866667 \times 0.40 / (1 - 0.15) = 1.7819608\text{ t/ha}$
  - $\text{BWP} = 3786.6667 / (154.0 \times 10) = 2.4588745\text{ kg/m}^3$
  - $\text{CWP} = (1.7819608 \times 1000) / (154.0 \times 10) = 1.1571174\text{ kg/m}^3$
  - $\text{NBWP} = (3.7866667 \times 1000) / (111.4 \times 10) = 3.3991622\text{ kg/m}^3$
  - $\text{Beneficial Fraction} = 111.4 / 154.0 = 0.7233766$

### Cell 13 (Row 3, Col 1 — Class 2, `31.5°N–32.0°N, 30.0°E–30.5°E`)

- **Daily input rates** (cell offset $\Delta_{13} = 12 \times 0.02 = 0.24$, added to each dekad rate):
  - Every dekad rate is shifted by $+0.24$, so across $59\text{ days}$ each seasonal depth increases by $59 \times 0.24 = 14.16$:
  - $\text{AETI}_{\text{season}} = 154.0 + 14.16 = 168.16\text{ mm}$
  - $\text{RET}_{\text{season}} = 265.5 + 14.16 = 279.66\text{ mm}$
  - $\text{PCP}_{\text{season}} = 65.0 + 14.16 = 79.16\text{ mm}$
  - $\text{NPP}_{\text{season}} = 213.0 + 14.16 = 227.16\text{ gC/m}^2$
  - $\text{T}_{\text{season}} = 111.4 + 14.16 = 125.56\text{ mm}$
