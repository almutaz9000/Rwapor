test_that("tiled window geometry scales without full-grid allocation", {
  sizes <- c(1000L, 2500L, 5000L, 10000L)
  for (n in sizes) {
    tiles <- Rwapor:::.wapor_tiled_windows(n, n, tile_size = 128L)
    expect_true(length(tiles) > 1L)
    peak_cells <- max(vapply(tiles, function(x) x$nrows * x$ncols, numeric(1)))
    expect_lte(peak_cells, 128^2)
    expect_equal(sum(vapply(tiles, function(x) x$nrows * x$ncols, numeric(1))), n^2)
  }
})

test_that("tiled memory stays bounded as the AOI grows and matches full-engine pixels", {
  skip_if_not_installed("terra")
  skip_on_cran()

  small <- Rwapor:::.wapor_tiled_memory_benchmark(
    nrow = 32L, ncol = 32L, tile_size = 16L, n_layers = 3L
  )
  large <- Rwapor:::.wapor_tiled_memory_benchmark(
    nrow = 64L, ncol = 64L, tile_size = 16L, n_layers = 3L
  )

  expect_true(small$pixel_parity)
  expect_true(large$pixel_parity)
  expect_lte(small$max_abs_diff, 1e-6)
  expect_lte(large$max_abs_diff, 1e-6)
  expect_equal(small$max_window_cells, large$max_window_cells)
  expect_gt(large$full_aoi_bytes, small$full_aoi_bytes)
  expect_lt(large$peak_bytes, large$full_aoi_bytes)
  expect_equal(large$n_tiles, 16L)
})

test_that("tile-size recommendation decreases as layer count increases", {
  small <- wapor_suggest_tile_size(12L, target_ram_mb = 64, min_tile = 1)
  large <- wapor_suggest_tile_size(120L, target_ram_mb = 64, min_tile = 1)
  expect_gte(small, large)
})
