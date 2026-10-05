# Is CPL_VSIL_CURL_CHUNK_SIZE honoured when changed after the first remote read?
a <- commandArgs(trailingOnly = TRUE)   # start value ("" = GDAL default), value set later
Sys.setenv(RWAPOR_AUTO_CONFIG = "false", CPL_CURL_VERBOSE = "YES", GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")
pj <- system.file("proj", package = "sf"); Sys.setenv(PROJ_LIB = pj, PROJ_DATA = pj)
if (nzchar(a[1])) Sys.setenv(CPL_VSIL_CURL_CHUNK_SIZE = a[1])
suppressMessages(pkgload::load_all(".", quiet = TRUE))
u <- paste0("/vsicurl/", sub("^/vsicurl/", "", wapor_generate_urls("L2-AETI-D", period = c("2023-01-01", "2023-01-31"))))
e <- terra::ext(35.55, 35.56, 32.40, 32.41)
invisible(terra::values(terra::crop(terra::rast(u[1]), e)))
terra::setGDALconfig("CPL_VSIL_CURL_CHUNK_SIZE", a[2]); Sys.setenv(CPL_VSIL_CURL_CHUNK_SIZE = a[2])
message("MARK-SECOND-FILE getGDALconfig=", terra::getGDALconfig("CPL_VSIL_CURL_CHUNK_SIZE"))
invisible(terra::values(terra::crop(terra::rast(u[2]), e)))
