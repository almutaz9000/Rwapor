
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
}, error = function(e) {
  message("Stack failed: ", e$message)
})
end_time <- Sys.time()
time_stack <- end_time - start_time
message("Time: ", round(time_stack, 2), " ", units(time_stack))

# 2. Benchmark: wapor_map (Separate Files)
message("\n[2] Testing wapor_map (Separate Files)...")
start_time <- Sys.time()
tryCatch({
  path2 <- wapor_map(region, variable, period, folder_sep, separate_files = TRUE)
  print(head(path2))
}, error = function(e) {
  message("Separate failed: ", e$message)
})
end_time <- Sys.time()
time_sep <- end_time - start_time
message("Time: ", round(time_sep, 2), " ", units(time_sep))

# 3. Benchmark: wapor_ts
message("\n[3] Testing wapor_ts (Zonal Stats Streaming)...")
start_time <- Sys.time()
tryCatch({
  df <- wapor_ts(region, variable, period)
  print(head(df))
}, error = function(e) {
  message("Zonal Stats failed: ", e$message)
})
end_time <- Sys.time()
time_ts <- end_time - start_time
message("Time: ", round(time_ts, 2), " ", units(time_ts))

message("\n--- Verification Complete ---")
