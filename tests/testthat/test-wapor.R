# Test suite for Rwapor package

# =============================================================================
# Tests for parse_region()
# =============================================================================

test_that("parse_region handles bounding box correctly", {
  # Valid bounding box
  result <- parse_region(c(35.0, 33.0, 36.0, 34.0))
  expect_equal(result$type, "bbox")
  expect_s3_class(result$value, "bbox")
  expect_equal(as.numeric(result$value["xmin"]), 35.0)
  expect_equal(as.numeric(result$value["ymax"]), 34.0)
})

test_that("parse_region rejects invalid bounding boxes", {
  # xmin >= xmax
  expect_error(
    parse_region(c(36.0, 33.0, 35.0, 34.0)),
    "xmin must be less than xmax"
  )

  # ymin >= ymax
  expect_error(
    parse_region(c(35.0, 35.0, 36.0, 34.0)),
    "ymin must be less than ymax"
  )

  # Out of range longitude
  expect_error(
    parse_region(c(-200, 33.0, 36.0, 34.0)),
    "longitude must be between"
  )

  # Out of range latitude
  expect_error(
    parse_region(c(35.0, -100, 36.0, 34.0)),
    "latitude must be between"
  )

  # Wrong number of elements
  expect_error(
    parse_region(c(35.0, 33.0, 36.0)),
    "exactly 4 elements"
  )
})

test_that("parse_region handles L3 codes correctly", {
  result <- parse_region("AWA")
  expect_equal(result$type, "l3_code")
  expect_equal(result$value, "AWA")

  result2 <- parse_region("ETH")
  expect_equal(result2$type, "l3_code")
})

test_that("parse_region rejects invalid inputs", {
  expect_error(parse_region(NULL), "cannot be NULL")
  expect_error(parse_region(list(a = 1)), "Invalid 'region' type")
  expect_error(parse_region("nonexistent_file.shp"), "neither a valid file path")
})

# =============================================================================
# Tests for get_date_info()
# =============================================================================

test_that("get_date_info parses dekadal dates correctly", {
  # WaPOR URL format: WAPOR-3.L1-AETI-D.YYYY-MM-DX.tif
  # First dekad
  result <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-01-D1.tif", "D")
  expect_equal(result$start_date, "2023-01-01")
  expect_equal(result$end_date, "2023-01-10")
  expect_equal(result$number_of_days, 10)

  # Second dekad
  result2 <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-01-D2.tif", "D")
  expect_equal(result2$start_date, "2023-01-11")
  expect_equal(result2$end_date, "2023-01-20")
  expect_equal(result2$number_of_days, 10)

  # Third dekad (variable length)
  result3 <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-01-D3.tif", "D")
  expect_equal(result3$start_date, "2023-01-21")
  expect_equal(result3$end_date, "2023-01-31")
  expect_equal(result3$number_of_days, 11)

  # February third dekad (shorter month)
  result4 <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-D/WAPOR-3.L1-AETI-D.2023-02-D3.tif", "D")
  expect_equal(result4$end_date, "2023-02-28")
  expect_equal(result4$number_of_days, 8)
})

test_that("get_date_info parses monthly dates correctly", {
  # WaPOR URL format: WAPOR-3.L1-AETI-M.YYYY-MM.tif
  result <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-M/WAPOR-3.L1-AETI-M.2023-06.tif", "M")
  expect_equal(result$start_date, "2023-06-01")
  expect_equal(result$end_date, "2023-06-30")
  expect_equal(result$number_of_days, 30)

  # 31-day month
  result2 <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-M/WAPOR-3.L1-AETI-M.2023-07.tif", "M")
  expect_equal(result2$end_date, "2023-07-31")
  expect_equal(result2$number_of_days, 31)
})

test_that("get_date_info parses annual dates correctly", {
  # WaPOR URL format: WAPOR-3.L1-AETI-A.YYYY.tif
  result <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MAPSET/L1-AETI-A/WAPOR-3.L1-AETI-A.2023.tif", "A")
  expect_equal(result$start_date, "2023-01-01")
  expect_equal(result$end_date, "2023-12-31")
  expect_equal(result$number_of_days, 365)
})

test_that("get_date_info parses daily dates correctly", {
  # AgERA5 URL format: C3S.AGERA5-ET0-E.YYYY-MM-DD.tif
  result <- get_date_info("https://gismgr.fao.org/DATA/C3S/MAPSET/AGERA5-ET0-E/C3S.AGERA5-ET0-E.2023-06-15.tif", "E")
  expect_equal(result$start_date, "2023-06-15")
  expect_equal(result$end_date, "2023-06-15")
  expect_equal(result$number_of_days, 1)
})

test_that("get_date_info parses L3 URLs with region code correctly", {
  # L3 URL format includes region code: WAPOR-3.L3-AETI-D.AWA.YYYY-MM-DX.tif
  # Dekadal L3

  result <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MOSAICSET/L3-AETI-D/WAPOR-3.L3-AETI-D.AWA.2018-01-D1.tif", "D")
  expect_equal(result$start_date, "2018-01-01")
  expect_equal(result$end_date, "2018-01-10")
  expect_equal(result$number_of_days, 10)

  # Second dekad L3
  result2 <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MOSAICSET/L3-AETI-D/WAPOR-3.L3-AETI-D.ETH.2023-06-D2.tif", "D")
  expect_equal(result2$start_date, "2023-06-11")
  expect_equal(result2$end_date, "2023-06-20")

  # Monthly L3
  result3 <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MOSAICSET/L3-AETI-M/WAPOR-3.L3-AETI-M.AWA.2023-06.tif", "M")
  expect_equal(result3$start_date, "2023-06-01")
  expect_equal(result3$end_date, "2023-06-30")
  expect_equal(result3$number_of_days, 30)

  # Annual L3
  result4 <- get_date_info("https://gismgr.fao.org/DATA/WAPOR-3/MOSAICSET/L3-AETI-A/WAPOR-3.L3-AETI-A.AWA.2022.tif", "A")
  expect_equal(result4$start_date, "2022-01-01")
  expect_equal(result4$end_date, "2022-12-31")
  expect_equal(result4$number_of_days, 365)
})

test_that("get_date_info validates inputs", {
  expect_error(get_date_info(123, "D"), "must be a single character")
  expect_error(get_date_info("test.tif", "X"), "Must be one of: D, M, A, E")
})

# =============================================================================
# Tests for get_variable_metadata()
# =============================================================================

test_that("get_variable_metadata returns static WaPOR metadata", {
  meta <- get_variable_metadata("L1-AETI-D")
  expect_type(meta, "list")
  expect_equal(meta$long_name, "Actual EvapoTranspiration and Interception")
  expect_equal(meta$units, "mm/day")
  expect_equal(meta$scale, 0.1)
})

test_that("get_variable_metadata returns static AgERA5 metadata", {
  meta <- get_variable_metadata("AGERA5-ET0-E")
  expect_type(meta, "list")
  expect_equal(meta$long_name, "Reference Evapotranspiration")
  expect_equal(meta$units, "mm/day")
  expect_equal(meta$scale, 1.0)
})

test_that("get_variable_metadata validates input", {
  expect_error(get_variable_metadata(123), "must be a single character")
  expect_error(get_variable_metadata(c("L1-AETI-D", "L2-AETI-D")), "must be a single character")
})

test_that("Dynamic Metadata Fetching works", {
  skip_if_offline()

  # L1-RET-E is not in static list, should fetch from API
  meta <- get_variable_metadata("L1-RET-E")

  expect_type(meta, "list")
  expect_true(!is.null(meta$units))
})

# =============================================================================
# Tests for wapor_generate_urls()
# =============================================================================

test_that("wapor_generate_urls validates inputs", {
  expect_error(
    wapor_generate_urls(123),
    "must be a single character"
  )

  expect_error(
    wapor_generate_urls("INVALID"),
    "Invalid variable format"
  )

  expect_error(
    wapor_generate_urls("X1-AETI-D"),
    "Invalid level"
  )

  expect_error(
    wapor_generate_urls("L1-AETI-D", period = c("2023-01-01")),
    "length 2"
  )

  expect_error(
    wapor_generate_urls("L1-AETI-D", period = c("2023-12-31", "2023-01-01")),
    "Start date must be before"
  )
})

test_that("wapor_generate_urls generates correct URLs", {
  skip_if_offline()

  urls <- wapor_generate_urls(
    variable = "L1-AETI-D",
    period = c("2023-01-01", "2023-01-10")
  )

  expect_type(urls, "character")
  expect_true(length(urls) > 0)
  expect_true(all(grepl("^https://", urls)))
})

# =============================================================================
# Tests for df_unit_convertor()
# =============================================================================

test_that("df_unit_convertor returns unchanged for 'none'", {
  df <- data.frame(
    mean = c(2.5, 3.0),
    start_date = c("2023-01-01", "2023-01-11"),
    number_of_days = c(10, 10)
  )
  attr(df, "units") <- "mm/day"

  result <- df_unit_convertor(df, "none")
  expect_equal(result$mean, df$mean)
})

test_that("df_unit_convertor converts day to month", {
  df <- data.frame(
    mean = c(1.0, 1.0),
    min = c(0.5, 0.5),
    max = c(1.5, 1.5),
    start_date = c("2023-01-01", "2023-02-01"),
    number_of_days = c(1, 1)
  )
  attr(df, "units") <- "mm/day"

  result <- df_unit_convertor(df, "month")

  # January has 31 days, February has 28 days
  expect_equal(result$mean[1], 31)
  expect_equal(result$mean[2], 28)
  expect_equal(attr(result, "units"), "mm/month")
  expect_equal(attr(result, "original_units"), "mm/day")
})

test_that("df_unit_convertor validates inputs", {
  expect_error(df_unit_convertor("not a df", "day"), "must be a data.frame")
  expect_error(
    df_unit_convertor(data.frame(x = 1), "invalid"),
    "must be one of"
  )
})

# =============================================================================
# Tests for calculate_conversion_factor()
# =============================================================================

test_that("calculate_conversion_factor returns correct values", {
  # Same units
  expect_equal(calculate_conversion_factor("day", "day", 10, 30), 1)

  # Day to month
  expect_equal(calculate_conversion_factor("day", "month", 10, 31), 31)

  # Day to year
  expect_equal(calculate_conversion_factor("day", "year", 10, 30), 365)

  # Dekad to day
  expect_equal(calculate_conversion_factor("dekad", "day", 10, 30), 0.1)

  # Month to year
  expect_equal(calculate_conversion_factor("month", "year", 30, 30), 12)
})

# =============================================================================
# Integration Tests (require network)
# =============================================================================

test_that("Zonal Statistics works with exactextractr", {
  skip_if_offline()
  skip_on_cran()

  # Create a small polygon for fast testing
  poly_coords <- matrix(c(
    35.75, 33.70,
    35.82, 33.70,
    35.82, 33.75,
    35.75, 33.75,
    35.75, 33.70
  ), ncol = 2, byrow = TRUE)
  poly <- sf::st_polygon(list(poly_coords))
  sf_poly <- sf::st_sf(
    geometry = sf::st_sfc(poly, crs = 4326),
    id = 1,
    name = "TestArea"
  )

  tmp_poly <- tempfile(fileext = ".geojson")
  sf::st_write(sf_poly, tmp_poly, quiet = TRUE)

  variable <- "L1-AETI-D"
  period   <- c("2021-01-01", "2021-01-10")

  df <- wapor_ts(
    tmp_poly,
    variable,
    period,
    identifier     = "name",
    unit_conversion = "dekad"
  )

  expect_s3_class(df, "data.frame")
  expect_true(nrow(df) > 0)
  expect_true("mean"       %in% names(df))
  expect_true("min"        %in% names(df))
  expect_true("max"        %in% names(df))
  expect_true("start_date" %in% names(df))

  unlink(tmp_poly)
})

test_that("wapor_ts works with bounding box", {
  skip_if_offline()
  skip_on_cran()

  region   <- c(35.75, 33.70, 35.82, 33.75)
  variable <- "L1-AETI-D"
  period   <- c("2021-01-01", "2021-01-10")

  df <- wapor_ts(region, variable, period)

  expect_s3_class(df, "data.frame")
  expect_true(nrow(df) > 0)
  expect_false(is.null(attr(df, "units")))
})
