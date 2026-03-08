suppressPackageStartupMessages(library(terra))
devtools::load_all('.')
urls <- wapor_generate_urls("L3-AETI-D", l3_region="JVA", period=c("2023-01-01", "2023-01-20"))

r1 <- terra::rast(paste0("/vsicurl/", urls[1]))
r2 <- terra::rast(paste0("/vsicurl/", urls[2]))

stack <- c(r1, r2)
sum_bad <- terra::app(stack, fun="sum", na.rm=TRUE)

# If BOTH layers are NA, sum_bad will be 0 instead of NA!
cat("Bad sum NA count:", terra::global(is.na(sum_bad), "sum")[[1]], "\n")
cat("Bad sum 0 count:", terra::global(sum_bad == 0, "sum", na.rm=TRUE)[[1]], "\n")

# Correct way using sum() directly from terra which handles all-NA correctly
sum_good <- sum(stack, na.rm=TRUE)
cat("Good sum NA count:", terra::global(is.na(sum_good), "sum")[[1]], "\n")
cat("Good sum 0 count:", terra::global(sum_good == 0, "sum", na.rm=TRUE)[[1]], "\n")
