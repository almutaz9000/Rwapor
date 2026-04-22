library(testthat)
library(Rwapor)

test_that("wapor_generate_urls handles list of periods", {
  # Mocking a variable that exists
  var <- "L1-AETI-D"
  
  # Single period
  p1 <- c("2023-01-01", "2023-01-10")
  urls1 <- wapor_generate_urls(var, period = p1)
  expect_true(length(urls1) > 0)
  
  # List of periods (overlapping or distinct)
  p_list <- list(
    c("2023-01-01", "2023-01-10"),
    c("2023-02-01", "2023-02-10")
  )
  urls_multi <- wapor_generate_urls(var, period = p_list)
  
  expect_true(length(urls_multi) > length(urls1))
  # Should be equal to sum of individual periods if distinct
  urls2 <- wapor_generate_urls(var, period = p_list[[2]])
  expect_equal(length(urls_multi), length(urls1) + length(urls2))
})

test_that("wapor_map seasonal mode with multiple periods creates multiple files", {
  # Use a small bbox and short periods to save time/bandwidth
  reg <- c(35.0, 33.0, 35.1, 33.1)
  var <- "L1-AETI-D"
  p_list <- list(
    "Jan2023" = c("2023-01-01", "2023-01-10"),
    "Feb2023" = c("2023-02-01", "2023-02-10")
  )
  
  temp_folder <- tempfile("wapor_test_multi")
  dir.create(temp_folder)
  
  res <- wapor_map(
    region = reg,
    variable = var,
    period = p_list,
    folder = temp_folder,
    seasonal = TRUE
  )
  
  expect_type(res, "list")
  expect_length(res, 2)
  expect_named(res, c("Jan2023", "Feb2023"))
  
  expect_true(file.exists(res$Jan2023))
  expect_true(file.exists(res$Feb2023))
  
  # Check if names contain the season label
  expect_true(grepl("Jan2023", res$Jan2023))
  expect_true(grepl("Feb2023", res$Feb2023))
  
  unlink(temp_folder, recursive = TRUE)
})
