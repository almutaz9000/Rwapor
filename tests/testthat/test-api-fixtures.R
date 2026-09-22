test_that("catalogue pagination works with deterministic fixture responses", {
  requests <- character()
  fixture <- function(url) {
    requests <<- c(requests, url)
    if (identical(url, "fixture-page-1")) {
      return(list(response = list(
        items = list(list(downloadUrl = "https://example/a.tif")),
        links = list(list(rel = "next", href = "fixture-page-2"))
      )))
    }
    if (identical(url, "fixture-page-2")) {
      return(list(response = list(
        items = list(list(downloadUrl = "https://example/b.tif")),
        links = list()
      )))
    }
    stop("unexpected fixture URL")
  }

  got <- Rwapor:::collect_responses(
    "fixture-page-1", use_cache = FALSE, request_fn = fixture
  )
  expect_equal(unlist(got), c("https://example/a.tif", "https://example/b.tif"))
  expect_identical(requests, c("fixture-page-1", "fixture-page-2"))
})

test_that("catalogue fixtures reject malformed envelopes and links", {
  malformed <- function(url) list(response = list(items = "not-a-list", links = list()))
  expect_error(
    Rwapor:::collect_responses("fixture", use_cache = FALSE, request_fn = malformed),
    "malformed 'items'"
  )

  malformed_link <- function(url) list(response = list(
    items = list(), links = list(list(rel = "next"))
  ))
  expect_error(
    Rwapor:::collect_responses("fixture", use_cache = FALSE, request_fn = malformed_link),
    "malformed pagination link"
  )
})

test_that("catalogue fixtures reject missing response envelope", {
  expect_error(
    Rwapor:::collect_responses(
      "fixture", use_cache = FALSE,
      request_fn = function(url) list(items = list())
    ),
    "no valid 'response' envelope"
  )
})
