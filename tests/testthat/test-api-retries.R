test_that("API retry policy constructs an httr2 request with valid callbacks", {
  request <- Rwapor:::.wapor_req_retry(httr2::request("https://example.invalid"))
  expect_s3_class(request, "httr2_request")
})

test_that("Retry-After accepts both delay-seconds and HTTP-date forms", {
  numeric_response <- httr2::response(
    status_code = 503,
    headers = list("Retry-After" = "7")
  )
  expect_equal(Rwapor:::.wapor_retry_after(numeric_response), 7)

  date_response <- httr2::response(
    status_code = 503,
    headers = list(
      "Date" = "Wed, 21 Oct 2015 07:28:00 GMT",
      "Retry-After" = "Wed, 21 Oct 2015 07:28:30 GMT"
    )
  )
  expect_equal(Rwapor:::.wapor_retry_after(date_response), 30)
})

test_that("invalid or past Retry-After hints fall back to policy backoff", {
  invalid <- httr2::response(status_code = 503, headers = list("Retry-After" = "later"))
  negative <- httr2::response(status_code = 503, headers = list("Retry-After" = "-1"))

  expect_true(is.na(Rwapor:::.wapor_retry_after(invalid)))
  expect_true(is.na(Rwapor:::.wapor_retry_after(negative)))
})

test_that("retry backoff uses bounded full jitter", {
  withr::local_seed(2401)
  attempts <- 1:7
  delays <- vapply(attempts, Rwapor:::.wapor_retry_backoff, numeric(1))
  bounds <- pmin(2^attempts, 30)

  expect_true(all(delays >= 0))
  expect_true(all(delays < bounds))
})
