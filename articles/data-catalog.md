# Data Catalog: WaPOR & AgERA5

This catalog provides a comprehensive overview of the geospatial
datasets accessible through the `Rwapor` package, including variables
from FAO WaPOR (Version 3) and Copernicus AgERA5.

## WaPOR Variables (Version 3)

WaPOR provides data at three levels of detail. Most variables follow a
standard scaling of **0.1** to convert integer storage to physical units
(e.g., mm).

### Level 1: Continental (300 m imagery; 5 km precipitation; 30 km reference ET)

Global coverage. `L1-PCP` and `L1-RET` are auxiliary meteorological
inputs at their own coarser native resolution (5 km and 30 km
respectively, per `inst/metadata/wapor_L1.json`) — all other Level 1
variables below are ~300 m. The **Native Resolution** column applies to
a variable across all of its listed temporal resolutions —
e.g. `L1-AETI-D`, `L1-AETI-M`, and `L1-AETI-A` are all ~300 m, and
`L1-PCP-E`/`-D`/`-M`/`-A` are all ~5 km; only the temporal frequency
changes, not the spatial resolution.

| Category | Variable Name | ID | Native Resolution | Temporal | Units | Scale | Period | Portal |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| **Water** | Precipitation | `L1-PCP` | 5 km | E, D, M, A | mm | 0.1 | 1981+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L1-PCP-E) |
| **Water** | Reference ET | `L1-RET` | 30 km | E, D | mm | 0.1 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L1-RET-E) |
| **Water** | Actual ET & Int. | `L1-AETI` | 300 m | D, M, A | mm | 0.1 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L1-AETI-D) |
| **Water** | Evaporation | `L1-E` | 300 m | D, A | mm | 0.1 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L1-E-D) |
| **Water** | Transpiration | `L1-T` | 300 m | D, A | mm | 0.1 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L1-T-D) |
| **Water** | Interception | `L1-I` | 300 m | D, A | mm | 0.1 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L1-I-D) |
| **Biomass** | Net Primary Prod. | `L1-NPP` | 300 m | D, M | gC/m² | 0.001 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L1-NPP-D) |
| **Biomass** | Total Biomass Prod. | `L1-TBP` | 300 m | A | kg/ha | 1.0 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L1-TBP-A) |
| **Moisture** | Rel. Soil Moisture | `L1-RSM` | 300 m | D | % | 0.001 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L1-RSM-D) |

### Level 2: National (100m)

Country-level monitoring for selected countries.

| Category | Variable Name | ID | Resolutions | Units | Scale | Period | Portal |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **Water** | Actual ET & Int. | `L2-AETI` | D, M, A | mm | 0.1 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L2-AETI-D) |
| **Water** | Transpiration | `L2-T` | D, A | mm | 0.1 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L2-T-D) |
| **Biomass** | Net Primary Prod. | `L2-NPP` | D, M | gC/m² | 0.001 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L2-NPP-D) |
| **Moisture** | Rel. Soil Moisture | `L2-RSM` | D | % | 0.001 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L2-RSM-D) |
| **Productivity** | Biomass Water Prod. | `L2-GBWP` | A | kg/m³ | 0.001 | 2018+ | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L2-GBWP-A) |

### Level 3: Sub-national (30m / 10m)

High-resolution data for specific irrigation schemes and river basins.

| Category | Variable Name | ID | Resolutions | Units | Scale | Period | Portal |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **Water** | Actual ET & Int. | `L3-AETI` | E, D, M, A | mm | 0.1 | Varies | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L3-AETI-E) |
| **Water** | Transpiration | `L3-T` | E, D, A | mm | 0.1 | Varies | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L3-T-E) |
| **Biomass** | Net Primary Prod. | `L3-NPP` | E, D, M | gC/m² | 0.001 | Varies | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L3-NPP-E) |
| **Moisture** | Rel. Soil Moisture | `L3-RSM` | E, D | % | 0.001 | Varies | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L3-RSM-E) |
| **Productivity** | Biomass Water Prod. | `L3-GBWP` | A | kg/m³ | 0.001 | Varies | [Links](https://wapor.apps.fao.org/catalog/WAPOR_3/1/L3-GBWP-A) |

------------------------------------------------------------------------

## AgERA5 Climate Variables

AgERA5 provides daily agro-meteorological indicators. Data is available
globally from **1979** to near real-time (~8 day lag).

| Category | Variable Name | ID | Resolutions | Units | Scale | Period | Documentation |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **Water** | Reference ET | `AGERA5-ET0` | E, D, M, A | mm | 1.0 | 1979+ | [CDS Link](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators?tab=overview) |
| **Water** | Precipitation | `AGERA5-PF` | E, D, M, A | mm | 1.0 | 1979+ | [CDS Link](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators?tab=overview) |
| **Temperature** | Min Temperature | `AGERA5-TMIN` | E, A\* | °C (Kelvin converted) | 1.0 | 1979+ | [CDS Link](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators?tab=overview) |
| **Temperature** | Max Temperature | `AGERA5-TMAX` | E, A\* | °C (Kelvin converted) | 1.0 | 1979+ | [CDS Link](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators?tab=overview) |
| **Energy** | Solar Radiation | `AGERA5-SRF` | E | J/m² | 1.0 | 1979+ | [CDS Link](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators?tab=overview) |
| **Atmospheric** | Wind Speed (2m) | `AGERA5-WS` | E | m/s | 1.0 | 1979+ | [CDS Link](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators?tab=overview) |
| **Atmospheric** | Rel. Humidity | `AGERA5-RHxx` | E | 0-1 | 1.0 | 1979+ | [CDS Link](https://cds.climate.copernicus.eu/cdsapp#!/dataset/sis-agrometeorological-indicators?tab=overview) |

*\* Annual Temperature products are provided as average values
(`AVG-A`).*

### Usage Note: Daily Variables

For daily AgERA5 variables, use the suffix `-E` (e.g., `AGERA5-ET0-E`).
The package internally translates this to the mapset ID `AGERA5-ET0`
required by the FAO GISMGR API.

------------------------------------------------------------------------

## Automatic Data Transformations

To keep analysis workflows simple and scientifically correct, the
`Rwapor` package performs two primary data transformations automatically
during data retrieval
([`wapor_ts()`](https://almutaz9000.github.io/Rwapor/reference/wapor_ts.md)
and
[`wapor_map()`](https://almutaz9000.github.io/Rwapor/reference/wapor_map.md)):

### 1. Kelvin to Celsius Conversion

- **Target Variables**: `AGERA5-TMIN-E`, `AGERA5-TMAX-E`
- **Details**: AgERA5 temperature variables are archived in Kelvin (`K`)
  on the server. `Rwapor` automatically subtracts `273.15` from the
  downloaded rasters and any extracted time series.
- **Output Units**: The final rasters, metadata, and tables are labeled
  in degrees Celsius (`degC` / `°C`).

### 2. Daily Rate to Dekadal Totals Conversion

- **Target Variables**: Any WaPOR `-D` (dekadal) variable (such as
  `L1-AETI-D`, `L2-AETI-D`, `L3-AETI-D`, `L1-RET-D`, `L1-PCP-D`, etc.)
- **Details**: WaPOR dekadal variables are archived as daily rates
  (e.g., `mm/day`). By default, `Rwapor` automatically scales these
  rates to 10-day totals (`mm/dekad`) based on the exact number of
  calendar days in each individual dekad (10 days for D1 and D2; 8, 9,
  10, or 11 days for D3 depending on the month and leap year).
- **Output Units**: The final data defaults to `mm/dekad` or
  `gC/m²/dekad` unless the user explicitly requests another unit (e.g.,
  `unit_conversion = "day"` to keep `mm/day`).
