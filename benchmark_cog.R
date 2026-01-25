
library(Rwapor)
library(terra)
library(sf)
library(future)

# Ensure clean slate
Sys.unsetenv("PROJ_LIB") 
plan(multisession)

# Test Parameters
region <- c(35.75, 33.70, 35.82, 33.75) 
variable <- "L1-AETI-D" 
period <- c("2021-01-01", "2021-02-20") 
folder_stack <- "bench_stack"
folder_sep <- "bench_sep"

message("--- Starting Verification & Benchmark ---")

# 1. Benchmark: wapor_map (Single Stack)
message("\n[1] Testing wapor_map (Single Stack)...")
start_time <- Sys.time()
tryCatch({
  path1 <- wapor_map(region, variable, period, folder_stack, separate_files = FALSE)
  print(path1)
  
  # Verify Band Names
  r_stack <- terra::rast(path1)
  message("Band Names: ", paste(names(r_stack), collapse = ", "))
  if (grepl("2021-01-01", names(r_stack)[1])) {
    message("SUCCESS: Band names are standardized dates.")
  } else {
    message("FAILURE: Band names still use original format.")
  }
}, error = function(e) {
  message("Stack failed: ", e$message)
})
end_time <- Sys.time()
time_stack <- end_time - start_time
message("Time: ", round(time_stack, 2), " ", units(time_stack))

# 2. Benchmark: wapor_map (Separate Files + Unit Conversion)
message("\n[2] Testing wapor_map (Separate Files + unit_conversion='day')...")
start_time <- Sys.time()
tryCatch({
  path2 <- wapor_map(region, variable, period, folder_sep, separate_files = TRUE, unit_conversion = "day")
  print(head(path2))
  
  # Check one file to ensure units look correct (sanity check)
  r_check <- terra::rast(path2[1])
  val <- terra::global(r_check, "mean", na.rm=TRUE)
  message("Mean value (day units): ", round(val[1,1], 2))
  
  # Check default (dekad)
  path2b <- wapor_map(region, variable, period, folder_sep, separate_files = TRUE) # Default should be dekad
  r_check_def <- terra::rast(path2b[1])
  val_def <- terra::global(r_check_def, "mean", na.rm=TRUE)
  message("Mean value (default/dekad units): ", round(val_def[1,1], 2))
  
  if (val_def > val) message("SUCCESS: Default (dekad) values are larger than daily values as expected.")
  
}, error = function(e) {
  message("Separate failed: ", e$message)
})
end_time <- Sys.time()
time_sep <- end_time - start_time
message("Time: ", round(time_sep, 2), " ", units(time_sep))

# 3. Benchmark: wapor_map (Multi-Variable)
message("\n[3] Testing wapor_map (Multi-Variable)...")
start_time <- Sys.time()
tryCatch({
  vars <- c("L1-AETI-D", "L1-T-D") # Example: ET and Transpiration
  # Note: L1-T-D might not exist for the exact same period/region, checking availability first or using reliable ones. 
  # Let's use vars that are definitely there. L1-NPP-D is good.
  vars <- c("L1-AETI-D", "L1-NPP-D")
  
  paths_multi <- wapor_map(region, vars, period, "bench_multi")
  print(paths_multi)
  
  # Verify folders
  if (dir.exists("bench_multi/L1-AETI-D") && dir.exists("bench_multi/L1-NPP-D")) {
    message("SUCCESS: Variable subdirectories created.")
  } else {
    message("FAILURE: Subdirectories missing.")
  }
}, error = function(e) {
  message("Multi-Var failed: ", e$message)
})
end_time <- Sys.time()
time_multi <- end_time - start_time
message("Time: ", round(time_multi, 2), " ", units(time_multi))

# 4. Benchmark: wapor_ts (Zonal Stats Streaming)
message("\n[4] Testing wapor_ts (Zonal Stats Streaming)...")
start_time <- Sys.time()
tryCatch({
  # Should default to "dekad" units for L1-AETI-D
  df <- wapor_ts(region, variable, period)
  print(head(df))
  message("Expected Mean (Dekad): ~5-10 mm/dekad")
  
  # Test explicit "day" units
  df_day <- wapor_ts(region, variable, period, unit_conversion = "day")
  print(head(df_day))
  message("Expected Mean (Day): ~0.5-1.0 mm/day")
  
}, error = function(e) {
  message("Zonal Stats failed: ", e$message)
})
end_time <- Sys.time()
time_ts <- end_time - start_time
message("Time: ", round(time_ts, 2), " ", units(time_ts))

message("\n--- Verification Complete ---")
