suppressPackageStartupMessages(library(terra))
devtools::load_all('.')
url <- wapor_generate_urls("L3-AETI-D", l3_region="JVA", period=c("2023-01-01", "2023-01-10"))[1]

# Load virtual
r <- terra::rast(paste0("/vsicurl/", url))

# Check initial state
cat("Initial NA:", terra::global(is.na(r), "sum")[[1]], "\n")
cat("Initial NaN:", terra::global(terra::app(r, is.nan), "sum")[[1]], "\n")

# Replace NaN with pure NA
r_clean <- terra::classify(r, cbind(NaN, NA))

cat("\nClean NA:", terra::global(is.na(r_clean), "sum")[[1]], "\n")
cat("Clean NaN:", terra::global(terra::app(r_clean, is.nan), "sum")[[1]], "\n")
