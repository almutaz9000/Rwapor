suppressPackageStartupMessages(library(terra))
devtools::load_all('.')

urls <- wapor_generate_urls("L3-AETI-D", l3_region="JVA", period=c("2023-01-01", "2023-01-10"))
url <- paste0("/vsicurl/", urls[1])

r <- tryCatch(terra::rast(url), error=function(e) NULL)

if (!is.null(r)) {
    cat("NA flag raw:", terra::NAflag(r), "\n")
    cat("Min/max raw:", terra::minmax(r), "\n")
    
    cat("\nMultiplying by 10...\n")
    r2 <- r * 10
    cat("NA flag r2:", terra::NAflag(r2), "\n")
    cat("Min/max r2:", terra::minmax(r2), "\n")
    
    cat("\nTrying a sum via app...\n")
    s <- terra::app(r2, fun="sum", na.rm=TRUE)
    cat("Min/max sum:", terra::minmax(s), "\n")
    
    cat("\nTrying sum via sum()...\n")
    s2 <- sum(r2, na.rm=TRUE)
    cat("Min/max sum sum():", terra::minmax(s2), "\n")
}
