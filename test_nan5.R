suppressPackageStartupMessages(library(terra))
devtools::load_all('.')
urls <- wapor_generate_urls("L3-AETI-D", l3_region="JVA", period=c("2023-01-01", "2023-01-20"))

# Check a sum again
r1 <- terra::rast(paste0("/vsicurl/", urls[1]))
r2 <- terra::rast(paste0("/vsicurl/", urls[2]))

# Test sum with NaN
stack_nan <- c(r1 * 10, r2 * 10)
sum_nan <- terra::app(stack_nan, fun="sum", na.rm=TRUE)
cat("Sum NaN max:", terra::global(sum_nan, "max", na.rm=TRUE)[[1]], "\n")

# Test sum with NA
r1_na <- terra::classify(r1, cbind(NaN, NA))
r2_na <- terra::classify(r2, cbind(NaN, NA))
stack_na <- c(r1_na * 10, r2_na * 10)
sum_na <- terra::app(stack_na, fun="sum", na.rm=TRUE)
cat("Sum NA max:", terra::global(sum_na, "max", na.rm=TRUE)[[1]], "\n")
