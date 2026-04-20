library(terra)
devtools::load_all()

# Create mock data
r_mask <- rast(nrows=100, ncols=100, vals=1)
r_start <- rast(nrows=100, ncols=100, vals=100)
r_end <- rast(nrows=100, ncols=100, vals=200)

# Add some variation
r_start[10:20, 10:20] <- 281

# Run the optimized function
profiles <- wapor_build_season_profile_table(r_mask, r_start, r_end, c(1, 2))

print("Extracted Profiles:")
print(profiles)

# Verify counts
stopifnot("pixel_count" %in% names(profiles))
stopifnot(nrow(profiles) == 2)
print("Verification successful!")
