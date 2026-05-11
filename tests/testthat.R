library(testthat)

if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(".", export_all = TRUE, helpers = FALSE, quiet = TRUE)
  test_dir("tests/testthat")
} else if (requireNamespace("Rwapor", quietly = TRUE)) {
  library(Rwapor)
  test_check("Rwapor")
} else if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(".", export_all = TRUE, helpers = FALSE, quiet = TRUE)
  test_dir("tests/testthat")
} else {
  source_files <- list.files("R", pattern = "\\.[Rr]$", full.names = TRUE)
  for (path in sort(source_files)) {
    sys.source(path, envir = .GlobalEnv)
  }
  test_dir("tests/testthat")
}
