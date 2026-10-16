# Audit ETLook Mass Balance Conservation

Verifies that actual evapotranspiration and interception (AETI) equals
the sum of its constituent components: soil evaporation (E), crop
transpiration (T), and rainfall interception (I), such that AETI = E +
T + I within a given tolerance.

## Usage

``` r
wapor_audit_etlook_mass_balance(aeti, e, t, i, tolerance = 1e-04)
```

## Arguments

- aeti:

  SpatRaster or numeric. Actual evapotranspiration and interception.

- e:

  SpatRaster or numeric. Soil evaporation.

- t:

  SpatRaster or numeric. Canopy transpiration.

- i:

  SpatRaster or numeric. Canopy interception.

- tolerance:

  Numeric. Maximum allowable absolute discrepancy (default 1e-4).

## Value

A list containing:

- is_conserved:

  Logical indicating whether the mass balance is satisfied within
  tolerance everywhere.

- max_absolute_error:

  Maximum absolute error observed.

- mean_absolute_error:

  Mean absolute error observed.

- discrepancy:

  Numeric or SpatRaster of residual discrepancies (AETI - (E + T + I)).

## References

Bastiaanssen, W. G. M., Menenti, M., Feddes, R. A., & Holtslag, A. A. M.
(1998). A remote sensing surface energy balance algorithm for land
(SEBAL).

1.  Formulation. Journal of Hydrology, 212-213, 198-212.

## Examples

``` r
wapor_audit_etlook_mass_balance(aeti = 100, e = 30, t = 65, i = 5)
#> $is_conserved
#> [1] TRUE
#> 
#> $max_absolute_error
#> [1] 0
#> 
#> $mean_absolute_error
#> [1] 0
#> 
#> $discrepancy
#> [1] 0
#> 
```
