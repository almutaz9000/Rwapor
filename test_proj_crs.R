suppressPackageStartupMessages(library(terra))
devtools::load_all('.')
Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")

urls <- wapor_generate_urls("L3-AETI-D", l3_region="JVA", period=c("2023-01-01", "2023-01-10"))
url <- paste0("/vsicurl/", urls[1])

r <- tryCatch(terra::rast(url), error=function(e) NULL)

if (!is.null(r)) {
    crs_str <- terra::crs(r)
    cat("Loaded Raster. CRS:\n")
    
    # Try creating a dummy WGS84 point and projecting it to r's CRS
    v <- terra::vect(matrix(c(35, 32), ncol=2), type="points", crs="EPSG:4326")
    v_proj <- tryCatch(terra::project(v, crs_str), error=function(e) cat("Project error with crs_str: ", e$message, "\n"))
    
    # Extract EPSG code
    epsg <- ""
    m <- regmatches(crs_str, regexpr("ID\\[\"EPSG\",(\\d+)\\]\\]$", crs_str))
    if (length(m) > 0) {
        epsg_num <- gsub("[^0-9]", "", m)
        epsg <- paste0("EPSG:", epsg_num)
        cat("Extracted EPSG: ", epsg, "\n")
        v_proj2 <- tryCatch(terra::project(v, epsg), error=function(e) cat("Project error with epsg: ", e$message, "\n"))
        if (!is.null(v_proj2)) {
            cat("Projection to EPSG String succeeded!\n")
        }
    } else {
        cat("No EPSG match\n")
    }
}
