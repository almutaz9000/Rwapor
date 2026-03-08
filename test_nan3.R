suppressPackageStartupMessages(library(terra))
devtools::load_all('.')

urls <- wapor_generate_urls("L3-AETI-D", l3_region="JVA", period=c("2023-01-01", "2023-01-10"))
url1 <- paste0("/vsicurl/", urls[1])
url2 <- paste0("/vsicurl/", urls[2]) # Second dekad

r1 <- tryCatch(terra::rast(url1), error=function(e) NULL)
r2 <- tryCatch(terra::rast(url2), error=function(e) NULL)

if (!is.null(r1) && !is.null(r2)) {
    # Combine into stack and multiply by days
    stack <- c(r1 * 10, r2 * 10)
    
    cat("\nTesting app(stack, sum)...\n")
    s_app <- terra::app(stack, fun="sum", na.rm=TRUE)
    cat("NA count s_app:", terra::global(is.na(s_app), "sum")[[1]], "\n")
    cat("NaN count s_app:", terra::global(terra::app(s_app, is.nan), "sum")[[1]], "\n")
    
    cat("\nTesting sum(stack)...\n")
    s_sum <- sum(stack, na.rm=TRUE)
    cat("NA count s_sum:", terra::global(is.na(s_sum), "sum")[[1]], "\n")
    cat("NaN count s_sum:", terra::global(terra::app(s_sum, is.nan), "sum")[[1]], "\n")
    
    cat("\nOriginal NaN counts:\n")
    cat("r1 NaN:", terra::global(terra::app(r1, is.nan), "sum")[[1]], "\n")
    cat("r2 NaN:", terra::global(terra::app(r2, is.nan), "sum")[[1]], "\n")
}
