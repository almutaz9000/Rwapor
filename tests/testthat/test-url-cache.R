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
