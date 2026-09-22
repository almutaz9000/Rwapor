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

#' Skip if the WaPOR API is not reachable
#'
#' Performs a 5-second probe of the FAO GISMGR API host.  Use this at the
#' top of any test that calls wapor_generate_urls(), wapor_ts(), or
#' wapor_map() so that CI runs on a machine without internet do not produce
#' false failures.
#'
#' @param host Character. URL to probe. Default is the FAO GISMGR API root.
#' @param timeout Numeric. Probe timeout in seconds. Default 5.
skip_if_wapor_offline <- function(host = "https://data.apps.fao.org",
                                   timeout = 5) {
  testthat::skip_on_cran()
  reachable <- tryCatch({
    resp <- httr2::request(host) |>
      httr2::req_timeout(timeout) |>
      httr2::req_error(is_error = function(r) FALSE) |>
      httr2::req_perform()
    TRUE
  }, error = function(e) FALSE)
  if (!reachable) {
    testthat::skip(paste0("WaPOR API not reachable (", host, "). Skipping network test."))
  }
}
