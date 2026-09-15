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

test_that("wapor_configure_gdal sets CPL_VSIL_CURL_CHUNK_SIZE", {
  wapor_configure_gdal(chunk_size = 5242880L)  # 5 MB
  expect_equal(Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE"), "5242880")

  # Restore default
  wapor_configure_gdal()
})

test_that("wapor_configure_gdal sets the correct default chunk size (10 MB)", {
  wapor_configure_gdal()
  expect_equal(Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE"), "10485760")
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
  expect_true("CPL_VSIL_CURL_CHUNK_SIZE" %in% names(result))
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
  wapor_configure_gdal(chunk_size = 20971520L)  # 20 MB
  settings <- wapor_gdal_settings()
  expect_equal(settings[["CPL_VSIL_CURL_CHUNK_SIZE"]], "20971520")

  # Restore default
  wapor_configure_gdal()
})

# =============================================================================
# .onLoad — package attach applies defaults
# =============================================================================

test_that("Package defaults are applied (chunk size is not the GDAL 16 KB default)", {
  # After package load, the chunk size should be our 10 MB default, not GDAL's 16 KB
  chunk <- Sys.getenv("CPL_VSIL_CURL_CHUNK_SIZE")
  expect_false(chunk == "" || chunk == "16384",
               info = "GDAL default 16 KB chunk size is still set — .onLoad may not have fired")
})
