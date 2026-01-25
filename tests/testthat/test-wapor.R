test_that("Dynamic Metadata Fetching works", {
  skip_if_offline()
  
  # L1-RET-E is likely not in static list
  meta <- get_variable_metadata("L1-RET-E")
  
  expect_type(meta, "list")
  expect_true(!is.null(meta$units))
  expect_equal(meta$units, "mm/day")
})

test_that("Zonal Statistics works with exactextractr", {
  skip_if_offline()
  skip_on_cran()
  
  # Create a dummy polygon
  poly_coords <- matrix(c(
    35.75, 33.70,
    35.82, 33.70,
    35.82, 33.75,
    35.75, 33.75,
    35.75, 33.70
  ), ncol = 2, byrow = TRUE)
  poly <- sf::st_polygon(list(poly_coords))
  sf_poly <- sf::st_sf(geometry = sf::st_sfc(poly, crs = 4326), id = 1, name="TestArea")
  
  # Temp file for polygon
  tmp_poly <- tempfile(fileext = ".geojson")
  sf::st_write(sf_poly, tmp_poly, quiet=TRUE)
  
  region <- c(35.75, 33.70, 35.82, 33.75)
  variable <- "L1-AETI-D"
  period <- c("2021-01-01", "2021-01-10")
  
  # Run wapor_ts with local parallel download
  future::plan(future::multisession, workers = 2)
  
  df <- wapor_ts(tmp_poly, variable, period, identifier="name", unit_conversion = "dekad", download_locally = TRUE)
  
  expect_s3_class(df, "data.frame")
  expect_true(nrow(df) > 0)
  expect_true("mean" %in% names(df))
})
