# Test Script for Rwandan Fixes
library(Rwapor)
library(terra)

# 1. Test Season Weights (Rate vs Total)
print("Testing wapor_build_season_weights...")
start_r <- rast(nrows=10, ncols=10, vals=280) # Season start DOY 280 (Oct 7)
end_r   <- rast(nrows=10, ncols=10, vals=30)  # Season end DOY 30 (Jan 30) (cross-year)
ref_year <- 2023

# Period covering Oct to Dec
period <- c("2023-10-01", "2023-12-31")
sw <- wapor_build_season_weights(period[1], period[2], start_r, end_r, ref_year)

# Check first dekad (2023-10-01 to 2023-10-10)
# DOYs are 274 to 283.
# Season starts at 280.
# Overlap: 280, 281, 282, 283 (4 days)
# Dekad length: 10 days.
# Expected days: 4. Expected fraction: 0.4.

d1_days <- terra::global(sw$days[[1]], "mean")$mean
d1_frac <- terra::global(sw$weights[[1]], "mean")$mean

print(paste("First dekad overlap days:", d1_days))
print(paste("First dekad overlap fraction:", d1_frac))

if (abs(d1_days - 4) < 0.1 && abs(d1_frac - 0.4) < 0.01) {
  print("SUCCESS: Season weights correctly return days and fractions.")
} else {
  stop("FAILURE: Season weights calculation is wrong.")
}

# 2. Test Peff Pro-rating
print("Testing Peff pro-rating...")
peff_monthly <- data.frame(
  year = c(2023, 2023),
  month = c(10, 11),
  peff_mm = c(100, 100)
)

# Season: Oct 21 to Nov 10
# Oct: 31 days. Start 21. Overlap: 21, 22, ..., 31 (11 days).
# Nov: 30 days. End 10. Overlap: 1, 2, ..., 10 (10 days).
# Expected: 100 * (11/31) + 100 * (10/30) = 32.25 + 33.33 = 65.58

val_peff <- wapor_calc_peff(peff_monthly, "2023-10-21", "2023-11-10")
print(paste("Pro-rated Peff:", val_peff))

expected_peff <- 100 * (11/31) + 100 * (10/30)
if (abs(val_peff - expected_peff) < 0.1) {
  print("SUCCESS: Peff is correctly pro-rated.")
} else {
  stop(paste("FAILURE: Peff calculation error. Expected", expected_peff, "got", val_peff))
}

print("All logic tests passed!")
