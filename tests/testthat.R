library(testthat)
test_root <- if (file.exists("load_source.R")) "." else "tests"
if (requireNamespace("Rwapor", quietly = TRUE)) {
  library(Rwapor)
  test_check("Rwapor")
} else {
  source(file.path(test_root, "load_source.R"))
  test_dir(file.path(test_root, "testthat"))
}
