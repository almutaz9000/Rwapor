# Climate-Based Crop Coefficient (Kc) Adjustments

Implementation of FAO Irrigation and Drainage Paper No. 56 (Allen et
al., 1998) equations for adjusting tabulated mid-season (Kc_mid) and
late-season (Kc_end) crop coefficients to local climatic conditions
(wind speed, minimum relative humidity, and crop height). Adjust Crop
Coefficients for Local Climate (FAO-56 Eq. 62 & 65)

## Usage

``` r
wapor_adjust_kc_climate(
  kc_mid,
  kc_end = NULL,
  u2,
  rh_min,
  h = 1,
  clamp_inputs = TRUE
)
```

## Arguments

- kc_mid:

  Numeric vector. Tabulated mid-season crop coefficient (from FAO-56
  Table 12).

- kc_end:

  Numeric vector. Tabulated late-season crop coefficient (optional).

- u2:

  Numeric vector. Mean daily wind speed at 2 m height during the stage
  (m/s). Valid range in FAO-56: 1.0 to 6.0 m/s.

- rh_min:

  Numeric vector. Mean daily minimum relative humidity during the stage
  (%). Valid range in FAO-56: 20% to 80%.

- h:

  Numeric vector. Mean plant height during the stage (m). Valid range in
  FAO-56: 0.1 to 10.0 m. Default is 1.0 m.

- clamp_inputs:

  Logical. If `TRUE` (default), clamps inputs to the FAO-56 physical
  validity boundaries: \\1.0 \le u_2 \le 6.0\\, \\20 \le RH\_{min} \le
  80\\, and \\0.1 \le h \le 10.0\\.

## Value

A data.frame with:

- kc_mid_tab:

  Original tabulated Kc_mid

- kc_mid_adj:

  Climatically adjusted Kc_mid

- kc_end_tab:

  Original tabulated Kc_end (if provided)

- kc_end_adj:

  Climatically adjusted Kc_end (if provided)

- delta_kc:

  The computed climate adjustment offset

## Details

Adjusts tabulated `kc_mid` and `kc_end` values from FAO-56 Table 12 to
account for local climatic conditions where minimum relative humidity
differs from 45% or wind speed at 2 m differs from 2.0 m/s.

The tabulated values for Kc_mid and Kc_end in FAO-56 represent a
sub-humid climate with average daytime minimum relative humidity (RHmin)
approx. 45% and calm to moderate wind speeds (u2) approx. 2.0 m/s.

For other conditions, FAO-56 specifies:

**Mid-season adjustment (Eq. 62):** \$\$Kc\_{mid} = Kc\_{mid(Tab)} +
\[0.04(u_2 - 2) - 0.004(RH\_{min} - 45)\]
\left(\frac{h}{3}\right)^{0.3}\$\$

**Late-season adjustment (Eq. 65):** \$\$Kc\_{end} = Kc\_{end(Tab)} +
\[0.04(u_2 - 2) - 0.004(RH\_{min} - 45)\]
\left(\frac{h}{3}\right)^{0.3}\$\$ (Applied only when \\Kc\_{end(Tab)}
\> 0.45\\. If \\Kc\_{end(Tab)} \le 0.45\\, no adjustment is made).

## References

Allen, R. G., Pereira, L. S., Raes, D., & Smith, M. (1998). Crop
evapotranspiration: Guidelines for computing crop water requirements.
FAO Irrigation and Drainage Paper No. 56, Rome, Italy. Equations 62 &
65.

## Examples

``` r
# FAO-56 Example 26: Arid, windy climate
# u2 = 3.2 m/s, RHmin = 30%, h = 2.5 m, Kc_mid(Tab) = 1.20
wapor_adjust_kc_climate(kc_mid = 1.20, u2 = 3.2, rh_min = 30, h = 2.5)
#>   kc_mid_tab kc_mid_adj delta_kc
#> 1        1.2      1.302   0.1023

# FAO-56 Example 27: Humid, calm climate
# u2 = 1.5 m/s, RHmin = 60%, h = 2.0 m, Kc_mid(Tab) = 1.20
wapor_adjust_kc_climate(kc_mid = 1.20, u2 = 1.5, rh_min = 60, h = 2.0)
#>   kc_mid_tab kc_mid_adj delta_kc
#> 1        1.2      1.129  -0.0708

# With Kc_end (> 0.45 gets adjusted; <= 0.45 remains unadjusted)
wapor_adjust_kc_climate(kc_mid = 1.15, kc_end = 0.60, u2 = 4.0, rh_min = 25, h = 1.2)
#>   kc_mid_tab kc_mid_adj delta_kc kc_end_tab kc_end_adj
#> 1       1.15      1.272   0.1215        0.6      0.722
wapor_adjust_kc_climate(kc_mid = 1.15, kc_end = 0.30, u2 = 4.0, rh_min = 25, h = 1.2)
#>   kc_mid_tab kc_mid_adj delta_kc kc_end_tab kc_end_adj
#> 1       1.15      1.272   0.1215        0.3        0.3
```
