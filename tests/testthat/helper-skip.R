#' Skip if live tests are not enabled
#'
#' Logic: skips if RWAPOR_RUN_LIVE_TESTS is not "true"
skip_if_no_live_api <- function() {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  
  if (Sys.getenv("RWAPOR_RUN_LIVE_TESTS") != "true") {
    testthat::skip("RWAPOR_RUN_LIVE_TESTS is not 'true'. Skipping live API tests.")
  }
}
