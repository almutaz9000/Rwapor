# Tests for wapor_plan_time_slices()
# ==============================================================================

# --- Input validation ---------------------------------------------------------

test_that("wapor_plan_time_slices() validates inputs", {
  expect_error(wapor_plan_time_slices("not-a-date", "2023-01-01"),
               "start_date")
  expect_error(wapor_plan_time_slices("2023-01-01", "not-a-date"),
               "end_date")
  expect_error(wapor_plan_time_slices("2023-06-01", "2023-01-01"),
               "start_date.*before")
  expect_error(wapor_plan_time_slices("2023-01-01", "2023-06-01", avail = c("X")),
               "Invalid temporal codes")
  expect_error(wapor_plan_time_slices("2023-01-01", "2023-06-01", avail = character(0)),
               "non-empty")
  expect_error(wapor_plan_time_slices("2023-01-01", "2023-06-01", inclusive = "yes"),
               "inclusive")
})

# --- Test 1: Partial season with M and D available ---------------------------

test_that("Test 1: 2022-10-13 to 2023-04-17 with avail = c('M', 'D')", {
  plan <- wapor_plan_time_slices("2022-10-13", "2023-04-17", avail = c("M", "D"))

  # Should have 9 rows total
  expect_equal(nrow(plan), 9L)

  # 5 full months: 2022-11, 2022-12, 2023-01, 2023-02, 2023-03
  monthly <- plan[plan$code == "M", ]
  expect_equal(nrow(monthly), 5L)
  expect_equal(monthly$period_id,
               c("2022-11", "2022-12", "2023-01", "2023-02", "2023-03"))
  expect_true(all(monthly$weight == 1))

  # 4 dekadal slices for edges

  dekadal <- plan[plan$code == "D", ]
  expect_equal(nrow(dekadal), 4L)

  # 2022-10-D2: Oct 11-20, overlap Oct 13-20 = 8 days, weight = 8/10
  d_oct2 <- dekadal[dekadal$period_id == "2022-10-D2", ]
  expect_equal(nrow(d_oct2), 1L)
  expect_equal(d_oct2$overlap_days, 8L)
  expect_equal(d_oct2$slice_days, 10L)
  expect_equal(d_oct2$weight, 8 / 10)

  # 2022-10-D3: Oct 21-31, fully within range, weight = 1
  d_oct3 <- dekadal[dekadal$period_id == "2022-10-D3", ]
  expect_equal(nrow(d_oct3), 1L)
  expect_equal(d_oct3$weight, 1)
  expect_equal(d_oct3$slice_days, 11L)  # Oct 21-31 = 11 days

  # 2023-04-D1: Apr 1-10, fully within range, weight = 1
  d_apr1 <- dekadal[dekadal$period_id == "2023-04-D1", ]
  expect_equal(nrow(d_apr1), 1L)
  expect_equal(d_apr1$weight, 1)

  # 2023-04-D2: Apr 11-20, overlap Apr 11-17 = 7 days, weight = 7/10
  d_apr2 <- dekadal[dekadal$period_id == "2023-04-D2", ]
  expect_equal(nrow(d_apr2), 1L)
  expect_equal(d_apr2$overlap_days, 7L)
  expect_equal(d_apr2$weight, 7 / 10)

  # Total overlap days should equal requested days (inclusive)
  total_days <- as.integer(as.Date("2023-04-17") - as.Date("2022-10-13")) + 1L
  expect_equal(sum(plan$overlap_days), total_days)
})

# --- Test 2: No full years available ------------------------------------------

test_that("Test 2: 2019-10-15 to 2020-05-25 with avail = c('A', 'M', 'D')", {
  plan <- wapor_plan_time_slices("2019-10-15", "2020-05-25", avail = c("A", "M", "D"))

  # No full annual slices
  annual <- plan[plan$code == "A", ]
  expect_equal(nrow(annual), 0L)

  # Full months: 2019-11, 2019-12, 2020-01, 2020-02, 2020-03, 2020-04 (6)
  monthly <- plan[plan$code == "M", ]
  expect_equal(nrow(monthly), 6L)
  expect_true(all(monthly$weight == 1))

  # Dekadal at edges
  dekadal <- plan[plan$code == "D", ]
  expect_true(nrow(dekadal) > 0)

  # Coverage check
  total_days <- as.integer(as.Date("2020-05-25") - as.Date("2019-10-15")) + 1L
  expect_equal(sum(plan$overlap_days), total_days)
})

# --- Test 3: Multi-year with full years ---------------------------------------

test_that("Test 3: 2018-01-01 to 2023-06-22 with avail = c('A', 'M', 'D')", {
  plan <- wapor_plan_time_slices("2018-01-01", "2023-06-22", avail = c("A", "M", "D"))

  # Full years: 2018, 2019, 2020, 2021, 2022 (start is Jan 1 so 2018 is full)
  annual <- plan[plan$code == "A", ]
  expect_equal(nrow(annual), 5L)
  expect_equal(annual$period_id, c("2018", "2019", "2020", "2021", "2022"))
  expect_true(all(annual$weight == 1))

  # 2023 partial: full months Jan-May (5 months)
  monthly <- plan[plan$code == "M", ]
  expect_equal(nrow(monthly), 5L)
  expect_equal(monthly$period_id,
               c("2023-01", "2023-02", "2023-03", "2023-04", "2023-05"))

  # June dekads
  dekadal <- plan[plan$code == "D", ]
  expect_true(nrow(dekadal) >= 2L)  # D1 full, D2 full, D3 partial (or just D1+D2 if 22nd is in D3)

  # June D1: Jun 1-10, weight = 1
  d_jun1 <- dekadal[dekadal$period_id == "2023-06-D1", ]
  expect_equal(nrow(d_jun1), 1L)
  expect_equal(d_jun1$weight, 1)

  # June D2: Jun 11-20, weight = 1
  d_jun2 <- dekadal[dekadal$period_id == "2023-06-D2", ]
  expect_equal(nrow(d_jun2), 1L)
  expect_equal(d_jun2$weight, 1)

  # June D3: Jun 21-30, overlap Jun 21-22 = 2 days, weight = 2/10
  d_jun3 <- dekadal[dekadal$period_id == "2023-06-D3", ]
  expect_equal(nrow(d_jun3), 1L)
  expect_equal(d_jun3$overlap_days, 2L)
  expect_equal(d_jun3$weight, 2 / 10)

  # Coverage check
  total_days <- as.integer(as.Date("2023-06-22") - as.Date("2018-01-01")) + 1L
  expect_equal(sum(plan$overlap_days), total_days)
})

# --- Test 4: No D available, fractional months --------------------------------

test_that("Test 4: 2022-10-13 to 2023-04-17 with avail = c('M', 'A')", {
  plan <- wapor_plan_time_slices("2022-10-13", "2023-04-17", avail = c("M", "A"))

  # No annual slices (no full year)
  annual <- plan[plan$code == "A", ]
  expect_equal(nrow(annual), 0L)

  # 7 monthly rows: 5 full + 2 partial
  monthly <- plan[plan$code == "M", ]
  expect_equal(nrow(monthly), 7L)

  # October 2022: Oct 13-31 = 19 days, weight = 19/31
  oct <- monthly[monthly$period_id == "2022-10", ]
  expect_equal(oct$overlap_days, 19L)
  expect_equal(oct$slice_days, 31L)
  expect_equal(oct$weight, 19 / 31)

  # April 2023: Apr 1-17 = 17 days, weight = 17/30
  apr <- monthly[monthly$period_id == "2023-04", ]
  expect_equal(apr$overlap_days, 17L)
  expect_equal(apr$slice_days, 30L)
  expect_equal(apr$weight, 17 / 30)

  # Full months have weight 1
  full <- monthly[monthly$weight == 1, ]
  expect_equal(nrow(full), 5L)

  # Coverage check
  total_days <- as.integer(as.Date("2023-04-17") - as.Date("2022-10-13")) + 1L
  expect_equal(sum(plan$overlap_days), total_days)
})

# --- Additional edge cases ----------------------------------------------------

test_that("Single day range works", {
  plan <- wapor_plan_time_slices("2023-06-15", "2023-06-15", avail = c("D"))
  expect_equal(nrow(plan), 1L)
  expect_equal(plan$code, "D")
  expect_equal(plan$period_id, "2023-06-D2")
  expect_equal(plan$overlap_days, 1L)
  expect_equal(plan$weight, 1 / 10)
})

test_that("Exact full year", {
  plan <- wapor_plan_time_slices("2022-01-01", "2022-12-31", avail = c("A", "M", "D"))
  expect_equal(nrow(plan), 1L)
  expect_equal(plan$code, "A")
  expect_equal(plan$period_id, "2022")
  expect_equal(plan$weight, 1)
  expect_equal(plan$slice_days, 365L)
})

test_that("Exact full month", {
  plan <- wapor_plan_time_slices("2023-02-01", "2023-02-28", avail = c("M", "D"))
  expect_equal(nrow(plan), 1L)
  expect_equal(plan$code, "M")
  expect_equal(plan$period_id, "2023-02")
  expect_equal(plan$weight, 1)
})

test_that("Leap year February handled correctly", {
  # 2024 is a leap year
  plan <- wapor_plan_time_slices("2024-02-01", "2024-02-29", avail = c("M", "D"))
  expect_equal(nrow(plan), 1L)
  expect_equal(plan$code, "M")
  expect_equal(plan$slice_days, 29L)

  # Full leap year
  plan_y <- wapor_plan_time_slices("2024-01-01", "2024-12-31", avail = c("A"))
  expect_equal(plan_y$slice_days, 366L)
})

test_that("inclusive = FALSE works (half-open range)", {
  # [2023-01-01, 2023-02-01) = entire January
  plan <- wapor_plan_time_slices("2023-01-01", "2023-02-01",
                                  avail = c("M"), inclusive = FALSE)
  expect_equal(nrow(plan), 1L)
  expect_equal(plan$period_id, "2023-01")
  expect_equal(plan$weight, 1)
})

test_that("Daily-only variable uses E slices", {
  plan <- wapor_plan_time_slices("2023-03-28", "2023-04-02", avail = c("E"))
  expect_equal(nrow(plan), 6L)
  expect_true(all(plan$code == "E"))
  expect_true(all(plan$weight == 1))
  expect_true(all(plan$slice_days == 1L))
})

test_that("Within single dekad", {
  plan <- wapor_plan_time_slices("2023-01-03", "2023-01-08", avail = c("D"))
  expect_equal(nrow(plan), 1L)
  expect_equal(plan$period_id, "2023-01-D1")
  expect_equal(plan$overlap_days, 6L)
  expect_equal(plan$weight, 6 / 10)
})

# --- wapor_temporal_codes() -------------------------------------------

test_that("wapor_temporal_codes() returns correct codes", {
  # L1-AETI has A, D, M
  codes <- wapor_temporal_codes("L1-AETI-D")
  expect_true("A" %in% codes)
  expect_true("M" %in% codes)
  expect_true("D" %in% codes)
  expect_false("E" %in% codes)

  # L2-NPP has D and M only (no A, no E)
  codes <- wapor_temporal_codes("L2-NPP-D")
  expect_true("D" %in% codes)
  expect_true("M" %in% codes)
  expect_false("A" %in% codes)
  expect_false("E" %in% codes)

  # L1-PCP has A, D, E, M
  codes <- wapor_temporal_codes("L1-PCP-E")
  expect_true("A" %in% codes)
  expect_true("D" %in% codes)
  expect_true("E" %in% codes)
  expect_true("M" %in% codes)

  # AgERA5-ET0 has A, D, E, M
  codes <- wapor_temporal_codes("AGERA5-ET0-E")
  expect_true(length(codes) == 4)
})

test_that("wapor_temporal_codes() handles L3 fallback", {
  # L3-AETI-D doesn't exist in metadata, but L2-AETI does
  codes <- wapor_temporal_codes("L3-AETI-D")
  expect_true(length(codes) > 0)
  expect_true("D" %in% codes)
})

test_that("wapor_temporal_codes() validates input", {
  expect_error(wapor_temporal_codes(123), "character")
  expect_error(wapor_temporal_codes("INVALID"), "Invalid variable format")
})

test_that("seasonal helper semantics use metadata rather than suffix alone", {
  plan <- wapor_plan_time_slices("2023-01-03", "2023-01-08", avail = c("D"))

  expect_equal(resolve_output_unit_conversion("L1-AETI-D"), "dekad")
  expect_equal(resolve_output_unit_conversion("L1-AETI-D", "unit_conversion"), "dekad")
  expect_equal(resolve_output_unit_conversion("AGERA5-ET0-D"), "none")
  expect_equal(resolve_output_unit_conversion("L3-RSM-D"), "none")
  expect_equal(resolve_output_unit_conversion("L3-AETI-M", "unit_conversion"), "none")

  expect_equal(get_seasonal_aggregation_rule("L1-AETI-D"), "weighted_sum")
  expect_equal(get_seasonal_aggregation_rule("AGERA5-ET0-D"), "weighted_sum")
  expect_equal(get_seasonal_aggregation_rule("L3-RSM-D"), "weighted_mean")
  expect_equal(get_seasonal_aggregation_rule("AGERA5-TMIN-E"), "weighted_mean")

  expect_equal(get_seasonal_multiplier_values("L1-AETI-D", plan), plan$overlap_days)
  expect_equal(get_seasonal_multiplier_values("AGERA5-ET0-D", plan), plan$weight)
  expect_equal(
    get_seasonal_multiplier_values("L3-RSM-D", plan, aggregation_rule = "weighted_mean"),
    plan$overlap_days
  )

  expect_equal(get_seasonal_output_units("L1-AETI-D"), "mm")
  expect_equal(get_seasonal_output_units("AGERA5-ET0-D"), "mm")
  expect_equal(get_seasonal_output_units("L3-RSM-D"), "%")
})

# --- Seasonal multiplier logic ------------------------------------------------

test_that("Seasonal multipliers are correct for mixed D/M plan", {
  # This verifies the logic that wapor_map/wapor_ts use for weighting
  plan <- wapor_plan_time_slices("2022-10-13", "2023-04-17", avail = c("M", "D"))

  # D rows: daily rate variables -> multiplier = overlap_days
  d_rows <- plan[plan$code == "D", ]
  # 2022-10-D2: overlap Oct 13-20 = 8 days
  expect_equal(d_rows[d_rows$period_id == "2022-10-D2", "overlap_days"], 8L)
  # 2022-10-D3: full dekad, overlap = 11 days (Oct 21-31)
  expect_equal(d_rows[d_rows$period_id == "2022-10-D3", "overlap_days"], 11L)
  # 2023-04-D1: full dekad, overlap = 10 days
  expect_equal(d_rows[d_rows$period_id == "2023-04-D1", "overlap_days"], 10L)
  # 2023-04-D2: overlap Apr 11-17 = 7 days
  expect_equal(d_rows[d_rows$period_id == "2023-04-D2", "overlap_days"], 7L)

  # M rows: period total variables -> multiplier = weight
  m_rows <- plan[plan$code == "M", ]
  # All full months have weight = 1
  expect_true(all(m_rows$weight == 1))
})

test_that("Seasonal multiplier for fractional monthly (no D)", {
  plan <- wapor_plan_time_slices("2022-10-13", "2023-04-17", avail = c("M"))

  # October 2022: 19 days overlap out of 31 -> weight = 19/31
  oct <- plan[plan$period_id == "2022-10", ]
  expect_equal(oct$weight, 19 / 31)

  # April 2023: 17 days overlap out of 30 -> weight = 17/30
  apr <- plan[plan$period_id == "2023-04", ]
  expect_equal(apr$weight, 17 / 30)
})

test_that("Seasonal sum arithmetic is correct for D variable", {
  # Simulate: L2-NPP-D from 2023-01-05 to 2023-01-25
  # avail = c("D")
  plan <- wapor_plan_time_slices("2023-01-05", "2023-01-25", avail = c("D"))

  # D1: Jan 1-10, overlap 5-10 = 6 days. Rate raster: multiply by 6.
  # D2: Jan 11-20, overlap 11-20 = 10 days. Rate raster: multiply by 10.
  # D3: Jan 21-31, overlap 21-25 = 5 days. Rate raster: multiply by 5.

  d1 <- plan[plan$period_id == "2023-01-D1", ]
  d2 <- plan[plan$period_id == "2023-01-D2", ]
  d3 <- plan[plan$period_id == "2023-01-D3", ]

  expect_equal(d1$overlap_days, 6L)
  expect_equal(d2$overlap_days, 10L)
  expect_equal(d3$overlap_days, 5L)

  # Simulated raster values (daily rate in mm/day): 2.0, 3.0, 1.5
  # Seasonal sum = 2.0*6 + 3.0*10 + 1.5*5 = 12 + 30 + 7.5 = 49.5
  simulated_rates <- c(2.0, 3.0, 1.5)
  seasonal_sum <- sum(simulated_rates * c(d1$overlap_days, d2$overlap_days, d3$overlap_days))
  expect_equal(seasonal_sum, 49.5)
})

test_that("Seasonal sum arithmetic is correct for mixed M+D", {
  # Simulate: L2-AETI-D from 2023-01-15 to 2023-03-10
  plan <- wapor_plan_time_slices("2023-01-15", "2023-03-10", avail = c("M", "D"))

  # Full month: February (M, weight = 1)
  feb <- plan[plan$period_id == "2023-02", ]
  expect_equal(feb$code, "M")
  expect_equal(feb$weight, 1)

  # Edge dekads in January and March (D)
  d_rows <- plan[plan$code == "D", ]
  expect_true(nrow(d_rows) >= 2)

  # Simulated values:
  # Feb monthly total: 75 mm/month. Multiplier = weight = 1. Contribution = 75.
  # Jan D2 (Jan 11-20): overlap 15-20 = 6 days. Daily rate = 2.5. Contribution = 2.5*6 = 15.
  # Jan D3 (Jan 21-31): 11 days, full. Daily rate = 2.0. Contribution = 2.0*11 = 22.
  # Mar D1 (Mar 1-10): 10 days, full. Daily rate = 3.0. Contribution = 3.0*10 = 30.
  # Total = 75 + 15 + 22 + 30 = 142

  jan_d2 <- plan[plan$period_id == "2023-01-D2", ]
  jan_d3 <- plan[plan$period_id == "2023-01-D3", ]
  mar_d1 <- plan[plan$period_id == "2023-03-D1", ]

  expect_equal(jan_d2$overlap_days, 6L)
  expect_equal(jan_d3$overlap_days, 11L)
  expect_equal(mar_d1$overlap_days, 10L)

  # Compute seasonal sum with simulated data
  total <- 75 * feb$weight +       # M: monthly total * weight
    2.5 * jan_d2$overlap_days +     # D: daily rate * overlap_days
    2.0 * jan_d3$overlap_days +     # D: daily rate * overlap_days
    3.0 * mar_d1$overlap_days       # D: daily rate * overlap_days
  expect_equal(total, 142)
})

# --- Seasonal API boundary tests ---------------------------------------------

test_that("wapor_map seasonal=TRUE rejects multiple variables", {
  # seasonal mode is implemented and its validation rejects multiple variables.
  expect_error(
    wapor_map(
      region   = c(35.0, 33.0, 36.0, 34.0),
      variable = c("L1-AETI-D", "L1-NPP-D"),
      period   = c("2023-01-01", "2023-03-31"),
      folder   = tempdir(),
      seasonal = TRUE
    ),
    "single variable"
  )
})

test_that("wapor_ts seasonal argument is accepted (no 'unused argument' error)", {
  # Confirm seasonal is a known parameter. Use an invalid unit_conversion to
  # produce an early validation error — if seasonal were unknown, R would error
  # with "unused argument" first.
  expect_error(
    wapor_ts(
      region          = c(35.0, 33.0, 36.0, 34.0),
      variable        = "L1-AETI-D",
      period          = c("2023-01-01", "2023-03-31"),
      unit_conversion = "invalid_unit",
      seasonal        = FALSE
    ),
    "unit_conversion.*none, unit_conversion"
  )
})

test_that("public download functions reject old explicit target units", {
  expect_error(
    wapor_ts(
      region = c(35.0, 33.0, 36.0, 34.0),
      variable = "L1-AETI-D",
      period = c("2023-01-01", "2023-03-31"),
      unit_conversion = "dekad"
    ),
    "unit_conversion.*none, unit_conversion"
  )

  expect_error(
    wapor_map(
      region = c(35.0, 33.0, 36.0, 34.0),
      variable = "L1-AETI-D",
      period = c("2023-01-01", "2023-03-31"),
      folder = tempdir(),
      unit_conversion = "month"
    ),
    "unit_conversion.*none, unit_conversion"
  )
})

test_that("safe public unit_conversion mode preserves monthly values", {
  expect_equal(resolve_output_unit_conversion("L3-AETI-M", "unit_conversion"), "none")
  expect_equal(calculate_conversion_factor("month", "month", 30, 30), 1)
})

test_that("wapor_map seasonal separate_files isolates seasonal components", {
  skip_if_not_installed("terra")

  tmp_dir <- tempfile("wapor_seasonal_components_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  r_month <- terra::rast(nrows = 2, ncols = 2, xmin = 35, xmax = 36, ymin = 33, ymax = 34, vals = 10)
  terra::crs(r_month) <- "EPSG:4326"
  r_dekad <- terra::rast(nrows = 2, ncols = 2, xmin = 35, xmax = 36, ymin = 33, ymax = 34, vals = 2)
  terra::crs(r_dekad) <- "EPSG:4326"

  mock_plan <- data.frame(
    code = c("D", "M"),
    period_id = c("2023-01-D1", "2023-02"),
    slice_start = as.Date(c("2023-01-01", "2023-02-01")),
    slice_end = as.Date(c("2023-01-10", "2023-02-28")),
    overlap_start = as.Date(c("2023-01-05", "2023-02-01")),
    overlap_end = as.Date(c("2023-01-10", "2023-02-28")),
    weight = c(0.6, 1),
    slice_days = c(10L, 28L),
    overlap_days = c(6L, 28L),
    stringsAsFactors = FALSE
  )
  mock_download <- function(...) {
    list(
      groups = list(
        D_group = list(
          code = "D",
          variable = "L1-AETI-D",
          raster = r_dekad,
          layer_ids = "2023-01-D1",
          multipliers = 6
        ),
        M_group = list(
          code = "M",
          variable = "L1-AETI-M",
          raster = r_month,
          layer_ids = "2023-02",
          multipliers = 1
        )
      ),
      plan = mock_plan,
      aggregation_rule = "weighted_sum"
    )
  }

  local_mocked_bindings(
    download_seasonal_rasters = mock_download,
    .package = "Rwapor"
  )

  result <- wapor_map(
    region = c(35, 33, 36, 34),
    variable = "L1-AETI-D",
    period = c("2023-01-05", "2023-02-28"),
    folder = tmp_dir,
    seasonal = TRUE,
    separate_files = TRUE
  )

  expect_type(result, "list")
  expect_named(result, c("seasonal_aggregate", "seasonal_components"))
  expect_true(file.exists(result$seasonal_aggregate))
  expect_true(all(file.exists(result$seasonal_components)))
  expect_match(result$seasonal_aggregate, "L1-AETI-D_seasonal")
  expect_true(all(grepl("seasonal_component", basename(result$seasonal_components))))
  expect_true(all(grepl("components", dirname(result$seasonal_components), fixed = TRUE)))
  expect_false(dir.exists(file.path(tmp_dir, "L1-AETI-D")))
})
