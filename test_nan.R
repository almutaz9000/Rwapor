suppressPackageStartupMessages(library(terra))

# Load the generated raster
out_folder <- "C:/Users/almut/Desktop/WaPOR_Seasonal_L3"
tif_path <- file.path(out_folder, "L3-AETI-D", "WAPOR-3.L3-AETI-D.seasonal.2023-01-01_2023-03-31.tif")

r <- tryCatch(terra::rast(tif_path), error=function(e) NULL)

if (!is.null(r)) {
    cat("Raster loaded.\n")
    cat("NA flag:", terra::NAflag(r), "\n")
    cat("Min/Max:", terra::minmax(r), "\n")
    cat("Global sum with NA rm:", terra::global(r, "sum", na.rm=TRUE)[[1]], "\n")
    cat("Global sum without NA rm:", terra::global(r, "sum", na.rm=FALSE)[[1]], "\n")
    cat("Number of NAs:", terra::global(is.na(r), "sum")[[1]], "\n")
    cat("Number of NaNs:", terra::global(terra::app(r, is.nan), "sum")[[1]], "\n")
} else {
    cat("Could not load raster.\n")
}
