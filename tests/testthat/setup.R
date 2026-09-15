# Ensure terra's bundled PROJ/GDAL data is used, not a conflicting system install
# (e.g. PostgreSQL sets PROJ_LIB/GDAL_DATA to its own paths, which segfaults terra)
terra_proj <- system.file("proj", package = "terra")
terra_gdal <- system.file("gdal", package = "terra")

if (nzchar(terra_proj)) Sys.setenv(PROJ_LIB = terra_proj, PROJ_DATA = terra_proj)
if (nzchar(terra_gdal)) Sys.setenv(GDAL_DATA = terra_gdal)
