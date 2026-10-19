test_that("inst/spec/indicators.yaml is in sync with wapor_list_indicator_steps() and .wapor_builtin_indicator_steps()", {
  skip_if_not_installed("yaml")

  spec_path <- system.file("spec", "indicators.yaml", package = "Rwapor")
  if (!nzchar(spec_path)) {
    spec_path <- testthat::test_path("..", "..", "inst", "spec", "indicators.yaml")
  }
  expect_true(file.exists(spec_path))

  spec <- yaml::read_yaml(spec_path)
  expect_true(is.list(spec$indicators))

  reg_ids <- sort(unique(c(
    as.character(wapor_list_indicator_steps()),
    as.character(.wapor_builtin_indicator_steps())
  )))
  yaml_ids <- sort(vapply(spec$indicators, function(x) as.character(x$id), character(1)))

  expect_identical(yaml_ids, reg_ids)

  by_id <- stats::setNames(
    spec$indicators,
    vapply(spec$indicators, function(x) as.character(x$id), character(1))
  )

  required_fields <- c(
    "id", "label", "category", "formula", "units_in", "units_out",
    "dekad_rule", "inputs", "citation", "r_function", "py_function", "status"
  )

  for (id in reg_ids) {
    entry <- by_id[[id]]
    expect_true(
      all(required_fields %in% names(entry)),
      info = paste("Missing fields in indicators.yaml for:", id)
    )
    expect_identical(as.character(entry$id), id)
    expect_true(nzchar(as.character(entry$formula)))
    expect_true(nzchar(as.character(entry$units_out)))
    expect_true(as.character(entry$status) %in% c("implemented", "planned"))
  }
})
