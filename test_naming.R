
tryCatch({
  library(Rwapor)
  library(future)
  library(terra)
  
  # Ensure clean slate for testing
  Sys.unsetenv("PROJ_LIB") 
  
  plan(multisession)
  
  region <- c(35.75, 33.70, 35.82, 33.75) 
  variable <- "L1-AETI-D" 
  period <- c("2021-01-01", "2021-01-10")
  folder <- "test_outputs"
  
  if(dir.exists(folder)) unlink(folder, recursive=TRUE)
  
  cat("Testing Default (Single Stack)...\n")
  out1 <- Rwapor::wapor_map(region, variable, period, folder, download_locally = FALSE, separate_files = FALSE)
  print(out1)
  
  cat("\nTesting Separate Files...\n")
  out2 <- Rwapor::wapor_map(region, variable, period, folder, download_locally = FALSE, separate_files = TRUE)
  print(out2)
  
}, error = function(e){
  cat("Error:", e$message, "\n")
})
