suppressPackageStartupMessages(library(terra))
# Simulate user having PROJ_LIB set (it already is on their system)
# Initialize terra
r_dummy <- terra::rast(matrix(1:4, 2))
terra::crs(r_dummy) <- "EPSG:4326"

Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")

# Now try to project
v <- terra::vect(matrix(c(35, 32), ncol=2), type="points", crs="EPSG:4326")
v_proj <- tryCatch(terra::project(v, "EPSG:32636"), error=function(e) cat("Project error: ", e$message, "\n"))
if (!is.null(v_proj)) cat("Success!\n")
