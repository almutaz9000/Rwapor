options(error = function() traceback(2))
suppressPackageStartupMessages(library(terra))
suppressPackageStartupMessages(library(sf))
devtools::load_all('.')

# Clean PROJ vars for this session
citrus_farms <- sf::st_read("C:/Users/almut/OneDrive/Documents/GitHub/Classification/Data/Vectors/Citrus_farms_final.geojson", quiet=TRUE)

# Test the high-level function
ts_citrus <- wapor_ts(
    region = citrus_farms,
    variable = "L3-AETI-D",             
    period = c("2023-01-01", "2023-01-10"),
    unit_conversion = "dekad"
)

print(head(ts_citrus))
