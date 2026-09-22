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

test_that("tile-size recommendation decreases as layer count increases", {
  small <- wapor_suggest_tile_size(12L, target_ram_mb = 64, min_tile = 1)
  large <- wapor_suggest_tile_size(120L, target_ram_mb = 64, min_tile = 1)
  expect_gte(small, large)
})
