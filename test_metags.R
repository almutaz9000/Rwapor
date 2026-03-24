library(terra)
r <- terra::rast(matrix(1:9, 3, 3))
cat("\n--- Setting metags with numeric value ---\n")
tryCatch({
  terra::metags(r) <- c(long_name = 123)
  cat("Success\n")
}, error = function(e) cat("Error: ", e$message, "\n"))

cat("\n--- Setting metags with character value ---\n")
tryCatch({
  terra::metags(r) <- c(long_name = "test")
  cat("Success\n")
}, error = function(e) cat("Error: ", e$message, "\n"))

cat("\n--- Setting metags with NULL value ---\n")
tryCatch({
  terra::metags(r) <- c(long_name = NULL)
  cat("Success\n")
}, error = function(e) cat("Error: ", e$message, "\n"))
