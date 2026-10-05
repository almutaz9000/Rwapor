test_that("rasterize mask reprojects and fractions", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  template <- terra::rast(nrows=2,ncols=2,xmin=0,xmax=2,ymin=0,ymax=2,crs="EPSG:32636")
  p <- sf::st_sf(id=1, geometry=sf::st_sfc(sf::st_polygon(list(matrix(c(0,0,1,0,1,2,0,2,0,0),ncol=2,byrow=TRUE))),crs=32636))
  m <- Rwapor::wapor_rasterize_mask(p, template, fraction=TRUE)
  expect_equal(terra::values(m)[,1], c(1,0,1,0), tolerance=1e-8)
})

test_that("lonlat polygons on a UTM template reproject", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  template <- terra::rast(nrows = 20, ncols = 20, xmin = 700000, xmax = 700400, ymin = 3600000, ymax = 3600400, crs = "EPSG:32636")
  p_utm <- sf::st_sf(id = 1, geometry = sf::st_sfc(sf::st_polygon(list(matrix(
    c(700000, 3600000, 700400, 3600000, 700400, 3600400, 700000, 3600400, 700000, 3600000), ncol = 2, byrow = TRUE
  ))), crs = 32636))
  p_ll <- sf::st_transform(p_utm, 4326)
  m <- wapor_rasterize_mask(p_ll, template)
  expect_true(any(!is.na(terra::values(m)[, 1])))
  empty <- terra::rasterize(terra::vect(p_ll), template, background = NA)
  expect_true(all(is.na(terra::values(empty)[, 1])))
})

test_that("fraction TRUE is 0.5 for a half cell", {
  skip_if_not_installed("terra"); skip_if_not_installed("sf")
  template <- terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 20, ymin = 0, ymax = 20, crs = "EPSG:32636")
  p <- sf::st_sf(id = 1, geometry = sf::st_sfc(sf::st_polygon(list(matrix(
    c(0, 0, 10, 0, 10, 20, 0, 20, 0, 0), ncol = 2, byrow = TRUE
  ))), crs = 32636))
  m <- wapor_rasterize_mask(p, template, fraction = TRUE)
  expect_equal(unname(terra::values(m)[1, 1]), 0.5, tolerance = 1e-6)
})

test_that("harmonize 10 m map on 20 m template", {
  skip_if_not_installed("terra")
  source <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 20, ymin = 0, ymax = 20, crs = "EPSG:32636", vals = c(1, 1, 1, 2))
  target <- terra::rast(nrows = 1, ncols = 1, xmin = 0, xmax = 20, ymin = 0, ymax = 20, crs = "EPSG:32636")
  h <- wapor_harmonize_mask(source, target, 1, min_fraction = 0.5)
  expect_equal(unname(terra::values(h$fraction)[1, 1]), 0.75, tolerance = 1e-8)
  expect_false(is.na(terra::values(h$mask)[1, 1]))
  h2 <- wapor_harmonize_mask(source, target, 1, min_fraction = 0.8)
  expect_true(is.na(terra::values(h2$mask)[1, 1]))
  h3 <- wapor_harmonize_mask(source, target, c(1, 2), min_fraction = 0.5)
  expect_equal(unname(terra::values(h3$fraction)[1, 1]), 0.75, tolerance = 1e-8)
})
