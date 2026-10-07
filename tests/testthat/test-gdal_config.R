# Tests for wapor_configure_gdal() and wapor_gdal_settings()

# =============================================================================
# wapor_configure_gdal() — argument validation
# =============================================================================

test_that("wapor_configure_gdal rejects invalid chunk_size", {
  expect_error(wapor_configure_gdal(chunk_size = -1), "chunk_size")
  expect_error(wapor_configure_gdal(chunk_size = 0),  "chunk_size")
  expect_error(wapor_configure_gdal(chunk_size = "big"), "chunk_size")
})

test_that("wapor_configure_gdal rejects non-logical vsi_cache", {
  expect_error(wapor_configure_gdal(vsi_cache = "yes"), "vsi_cache")
  expect_error(wapor_configure_gdal(vsi_cache = 1),     "vsi_cache")
})

# =============================================================================
# wapor_configure_gdal() — environment variables are set
# =============================================================================

test_that("wapor_configure_gdal sets an explicit CPL_VSIL_CURL_CHUNK_SIZE", {
  withr::local_envvar(CPL_VSIL_CURL_CHUNK_SIZE = NA)
  wapor_configure_gdal(chunk_size = 5242880L)  # 5 MB
  expect_equal(Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE"), "5242880")
})

test_that("wapor_configure_gdal leaves the chunk size alone by default (ISS-20261005-001)", {
  # Not created: GDAL's own default applies.
  withr::local_envvar(CPL_VSIL_CURL_CHUNK_SIZE = NA)
  applied <- wapor_configure_gdal()
  expect_identical(Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE", unset = NA), NA_character_)
  expect_false("CPL_VSIL_CURL_CHUNK_SIZE" %in% names(applied))
  expect_false("CPL_VSIL_CURL_CHUNK_SIZE" %in% names(Rwapor:::.RWAPOR_GDAL_DEFAULTS))

  # Not changed: a value the user set survives a default call, even with overwrite.
  withr::local_envvar(CPL_VSIL_CURL_CHUNK_SIZE = "65536")
  wapor_configure_gdal(overwrite = TRUE)
  expect_identical(Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE"), "65536")
})

test_that("wapor_configure_gdal accepts only chunk sizes GDAL accepts", {
  expect_error(wapor_configure_gdal(chunk_size = 512), "between 1024 and 10485760")
  expect_error(wapor_configure_gdal(chunk_size = 32 * 1024^2), "between 1024 and 10485760")
  expect_error(wapor_configure_gdal(chunk_size = NA_real_), "chunk_size")
})

test_that("wapor_configure_gdal sets GDAL_DISABLE_READDIR_ON_OPEN", {
  wapor_configure_gdal()
  expect_equal(Sys.getenv("GDAL_DISABLE_READDIR_ON_OPEN"), "EMPTY_DIR")
})

test_that("wapor_configure_gdal sets VSI_CACHE to TRUE by default", {
  wapor_configure_gdal()
  expect_equal(Sys.getenv("VSI_CACHE"), "TRUE")
})

test_that("wapor_configure_gdal disables VSI_CACHE when vsi_cache = FALSE", {
  wapor_configure_gdal(vsi_cache = FALSE)
  expect_equal(Sys.getenv("VSI_CACHE"), "FALSE")

  # Restore
  wapor_configure_gdal()
})

test_that("wapor_configure_gdal sets HTTP multiplex to YES by default", {
  wapor_configure_gdal()
  expect_equal(Sys.getenv("GDAL_HTTP_MULTIPLEX"), "YES")
})

test_that("wapor_configure_gdal disables HTTP multiplex when http_multiplex = FALSE", {
  wapor_configure_gdal(http_multiplex = FALSE)
  expect_equal(Sys.getenv("GDAL_HTTP_MULTIPLEX"), "NO")

  # Restore
  wapor_configure_gdal()
})

test_that("wapor_configure_gdal returns invisibly a named character vector", {
  result <- wapor_configure_gdal()
  expect_type(result, "character")
  expect_named(result)
  expect_true("GDAL_DISABLE_READDIR_ON_OPEN" %in% names(result))
})

test_that("wapor_configure_gdal verbose prints a message", {
  expect_message(wapor_configure_gdal(verbose = TRUE), "GDAL settings")
})

test_that("wapor_configure_gdal silent by default", {
  expect_silent(wapor_configure_gdal(verbose = FALSE))
})

# =============================================================================
# wapor_gdal_settings()
# =============================================================================

test_that("wapor_gdal_settings returns a named character vector", {
  settings <- wapor_gdal_settings()
  expect_type(settings, "character")
  expect_true(length(settings) > 0)
  expect_true(!is.null(names(settings)))
})

test_that("wapor_gdal_settings includes all expected keys", {
  settings <- wapor_gdal_settings()
  expect_true("CPL_VSIL_CURL_CHUNK_SIZE"     %in% names(settings))
  expect_true("VSI_CACHE"                    %in% names(settings))
  expect_true("GDAL_DISABLE_READDIR_ON_OPEN" %in% names(settings))
  expect_true("GDAL_HTTP_MULTIPLEX"          %in% names(settings))
  expect_true("GDAL_CACHEMAX"                %in% names(settings))
})

test_that("wapor_gdal_settings reflects current environment after configure", {
  withr::local_envvar(CPL_VSIL_CURL_CHUNK_SIZE = NA)
  wapor_configure_gdal(chunk_size = 2097152L)  # 2 MB
  settings <- wapor_gdal_settings()
  expect_equal(settings[["CPL_VSIL_CURL_CHUNK_SIZE"]], "2097152")
})

# =============================================================================
# .onLoad — package attach applies defaults
# =============================================================================

test_that("package load applies the defaults but never a chunk size", {
  withr::local_envvar(CPL_VSIL_CURL_CHUNK_SIZE = NA, GDAL_DISABLE_READDIR_ON_OPEN = NA,
                      RWAPOR_AUTO_CONFIG = "true")
  withr::local_options(Rwapor.configure_gdal = TRUE, Rwapor.gdal_checked = TRUE)
  Rwapor:::.onLoad("", "Rwapor")
  expect_identical(Sys.getenv("GDAL_DISABLE_READDIR_ON_OPEN"), "EMPTY_DIR")
  expect_identical(Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE", unset = NA), NA_character_)
})

# =============================================================================
# .wapor_with_remote_io() — scoped /vsicurl/ extension filter
# =============================================================================

test_that("remote extension filter is set during the call and cleared after it", {
  key <- "CPL_VSIL_CURL_ALLOWED_EXTENSIONS"
  withr::local_envvar(CPL_VSIL_CURL_ALLOWED_EXTENSIONS = NA)
  terra::setGDALconfig(key, "")
  inside <- Rwapor:::.wapor_with_remote_io(unname(terra::getGDALconfig(key)))
  expect_identical(inside, Rwapor:::.RWAPOR_REMOTE_EXTENSIONS)
  expect_identical(unname(terra::getGDALconfig(key)), "")

  # Nested calls keep the filter until the outer call ends.
  nested <- Rwapor:::.wapor_with_remote_io({
    Rwapor:::.wapor_with_remote_io(NULL)
    unname(terra::getGDALconfig(key))
  })
  expect_identical(nested, Rwapor:::.RWAPOR_REMOTE_EXTENSIONS)
  expect_identical(unname(terra::getGDALconfig(key)), "")

  # Cleared when the code fails.
  expect_error(Rwapor:::.wapor_with_remote_io(stop("remote read failed")), "remote read failed")
  expect_identical(unname(terra::getGDALconfig(key)), "")
})

test_that("remote extension filter respects the user's filter and the opt-out", {
  key <- "CPL_VSIL_CURL_ALLOWED_EXTENSIONS"
  terra::setGDALconfig(key, ".tif,.vrt")
  on.exit(terra::setGDALconfig(key, ""), add = TRUE)
  expect_identical(Rwapor:::.wapor_with_remote_io(unname(terra::getGDALconfig(key))), ".tif,.vrt")
  expect_identical(unname(terra::getGDALconfig(key)), ".tif,.vrt")

  terra::setGDALconfig(key, "")
  withr::local_options(Rwapor.remote_extension_filter = FALSE)
  expect_identical(Rwapor:::.wapor_with_remote_io(unname(terra::getGDALconfig(key))), "")
})

test_that("remote capability probe returns a stable contract", {
  caps <- wapor_remote_capabilities(refresh = TRUE)
  expect_true(is.list(caps))
  expect_true(all(c("has_curl", "has_cog", "streaming", "message") %in% names(caps)))
  expect_type(caps$streaming, "logical")
})

test_that("remote source resolver has explicit error and stream modes", {
  old <- getOption("Rwapor.remote_fallback")
  old_caps <- getOption("Rwapor.remote_capabilities")
  on.exit(options(Rwapor.remote_fallback = old, Rwapor.remote_capabilities = old_caps), add = TRUE)
  options(Rwapor.remote_fallback = "error")
  # Simulate a GDAL build without curl (the probe result is cached in this option).
  options(Rwapor.remote_capabilities = list(
    has_curl = FALSE, has_cog = TRUE, streaming = FALSE,
    message = "curl /vsicurl support is missing."
  ))
  expect_error(
    Rwapor:::.wapor_resolve_remote_sources("https://example.invalid/test.tif"),
    "Remote COG streaming is unavailable"
  )
  # With curl available, error mode streams instead of failing.
  options(Rwapor.remote_capabilities = list(
    has_curl = TRUE, has_cog = TRUE, streaming = TRUE, message = "ok"
  ))
  expect_identical(
    Rwapor:::.wapor_resolve_remote_sources("https://example.invalid/test.tif"),
    "/vsicurl/https://example.invalid/test.tif"
  )
  options(Rwapor.remote_fallback = "stream")
  expect_identical(
    Rwapor:::.wapor_resolve_remote_sources("https://example.invalid/test.tif"),
    "/vsicurl/https://example.invalid/test.tif"
  )
})
test_that("load-time configuration keeps GDAL variables the user already set", {
  withr::local_envvar(GDAL_HTTP_VERSION = "1.1", GDAL_CACHEMAX = "")
  applied <- wapor_configure_gdal(overwrite = FALSE)
  expect_identical(Sys.getenv("GDAL_HTTP_VERSION"), "1.1")
  expect_false("GDAL_HTTP_VERSION" %in% names(applied))
  expect_identical(Sys.getenv("GDAL_CACHEMAX"), "512")

  # Manual calls still override by default.
  wapor_configure_gdal()
  expect_identical(Sys.getenv("GDAL_HTTP_VERSION"), "2")
})

test_that(".onLoad can be switched off with RWAPOR_AUTO_CONFIG", {
  withr::local_envvar(RWAPOR_AUTO_CONFIG = "false", GDAL_CACHEMAX = "")
  Rwapor:::.onLoad("", "Rwapor")
  expect_identical(Sys.getenv("GDAL_CACHEMAX"), "")
})

test_that("the PROJ fix runs on load even when GDAL auto-configuration is off", {
  calls <- 0L
  testthat::local_mocked_bindings(
    wapor_fix_proj = function(...) { calls <<- calls + 1L; invisible("") },
    .package = "Rwapor"
  )
  withr::local_envvar(RWAPOR_AUTO_CONFIG = "false", GDAL_CACHEMAX = "")
  withr::local_options(Rwapor.fix_proj = NULL)
  Rwapor:::.onLoad("", "Rwapor")
  expect_identical(calls, 1L)
  expect_identical(Sys.getenv("GDAL_CACHEMAX"), "")

  withr::local_options(Rwapor.fix_proj = FALSE)
  Rwapor:::.onLoad("", "Rwapor")
  expect_identical(calls, 1L)
})
