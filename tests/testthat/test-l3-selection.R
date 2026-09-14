test_that("multi-L3 selection requires an explicit policy", {
  expect_error(
    wapor_resolve_l3_selection(c("AAA", "BBB")),
    "multiple L3 regions"
  )

  expect_equal(
    wapor_resolve_l3_selection(c("AAA", "BBB"), l3_region = "BBB"),
    "BBB"
  )

  expect_equal(
    wapor_resolve_l3_selection(c("AAA", "BBB"), l3_mode = "mosaic_all"),
    c("AAA", "BBB")
  )
})
