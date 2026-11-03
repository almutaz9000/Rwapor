test_that("wapor_clear_url_cache executes without error", {
  res <- wapor_clear_url_cache()
  expect_true(is.numeric(res) || is.integer(res))
})

test_that(".wapor_url_hash does not collide for character-permutation strings", {
  # Two different query strings of equal length whose characters are just
  # rearranged (e.g. swapped start/end dates in a period filter) must not
  # produce the same cache key. A byte-sum-based hash would collide here.
  a <- "L1-AETI-D::time:OVERLAPS:2023-06-15:2023-07-24;"
  b <- "L1-AETI-D::time:OVERLAPS:2023-06-24:2023-07-15;"
  expect_equal(nchar(a), nchar(b))
  expect_false(identical(Rwapor:::.wapor_url_hash(a), Rwapor:::.wapor_url_hash(b)))
})

test_that(".wapor_url_hash is deterministic for identical input", {
  x <- "L1-AETI-D::time:OVERLAPS:2023-01-01:2023-01-31;"
  expect_equal(Rwapor:::.wapor_url_hash(x), Rwapor:::.wapor_url_hash(x))
})

test_that("URL cache writes publish a complete RDS and leave no temporary file", {
  cache_dir <- withr::local_tempdir()
  cache_file <- file.path(cache_dir, "entry.rds")
  value <- list(items = c("first", "second"))

  expect_true(Rwapor:::.wapor_write_url_cache(value, cache_file))
  expect_identical(readRDS(cache_file), value)
  expect_length(list.files(cache_dir, all.files = TRUE, no.. = TRUE), 1L)

  replacement <- list(items = c("replacement-a", "replacement-b"))
  expect_true(Rwapor:::.wapor_write_url_cache(replacement, cache_file))
  expect_identical(readRDS(cache_file), replacement)
  expect_length(list.files(cache_dir, all.files = TRUE, no.. = TRUE), 1L)
})

test_that("failed URL cache publication preserves the destination and cleans its temporary file", {
  cache_dir <- withr::local_tempdir()
  blocked_path <- file.path(cache_dir, "blocked.rds")
  dir.create(blocked_path)
  sentinel <- file.path(blocked_path, "keep.txt")
  writeLines("preserve", sentinel)

  expect_false(Rwapor:::.wapor_write_url_cache(list(items = "new"), blocked_path))
  expect_identical(readLines(sentinel), "preserve")
  expect_identical(list.files(cache_dir, all.files = TRUE, no.. = TRUE), "blocked.rds")
})

test_that("concurrent URL cache writers leave one complete entry", {
  cache_dir <- withr::local_tempdir()
  cache_file <- file.path(cache_dir, "shared.rds")
  write_fn <- Rwapor:::.wapor_write_url_cache
  workers <- parallel::makeCluster(2L)
  on.exit(parallel::stopCluster(workers), add = TRUE)
  parallel::clusterExport(workers, c("write_fn", "cache_file"), envir = environment())

  results <- parallel::parLapply(workers, seq_len(8L), function(i) {
    value <- list(writer = i, payload = rep(as.character(i), 10000L))
    Sys.sleep(stats::runif(1, 0, 0.05))
    list(ok = write_fn(value, cache_file), value = value)
  })

  expect_true(all(vapply(results, `[[`, logical(1), "ok")))
  cached <- readRDS(cache_file)
  expect_true(any(vapply(results, function(result) identical(cached, result$value), logical(1))))
  expect_identical(list.files(cache_dir, all.files = TRUE, no.. = TRUE), "shared.rds")
})

test_that("corrupt URL cache entries are refetched and repaired", {
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir())
  url <- "fixture-cache-repair"
  calls <- 0L
  request <- function(...) {
    calls <<- calls + 1L
    list(response = list(items = list(list(downloadUrl = "https://example/data.tif")), links = list()))
  }

  first <- Rwapor:::collect_responses(url, request_fn = request)
  cache_file <- file.path(
    Rwapor:::.wapor_url_cache_dir(),
    paste0(Rwapor:::.wapor_url_hash(paste0(url, "::downloadUrl")), ".rds")
  )
  expect_true(file.exists(cache_file))
  writeBin(as.raw(c(0x00, 0x01, 0x02)), cache_file)

  second <- Rwapor:::collect_responses(url, request_fn = request)
  expect_identical(second, first)
  expect_identical(calls, 2L)
  expect_identical(readRDS(cache_file), first)
  third <- Rwapor:::collect_responses(url, request_fn = function(...) stop("cache should be used"))
  expect_identical(third, first)
})

test_that("zero URL cache TTL bypasses both cache reads and writes", {
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir())
  withr::local_options(Rwapor.cache_ttl = 0)
  calls <- 0L
  request <- function(...) {
    calls <<- calls + 1L
    list(response = list(items = list(list(downloadUrl = "https://example/data.tif")), links = list()))
  }

  Rwapor:::collect_responses("fixture-no-cache", request_fn = request)
  Rwapor:::collect_responses("fixture-no-cache", request_fn = request)
  expect_identical(calls, 2L)
  expect_length(list.files(Rwapor:::.wapor_url_cache_dir(), pattern = "[.]rds$"), 0L)
})
