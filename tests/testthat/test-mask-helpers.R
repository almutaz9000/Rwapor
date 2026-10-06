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

# --- B2 completion (2026-10-06): area check, adjacent polygons, NoData, several classes

.mh_square <- function(x1, x2, y1, y2, crs = 32636) {
  sf::st_sf(id = 1, geometry = sf::st_as_sfc(sf::st_bbox(c(xmin = x1, ymin = y1, xmax = x2, ymax = y2), crs = crs)))
}

test_that("both mask kinds carry the mask area over polygon area ratio", {
  template <- terra::rast(nrows = 20, ncols = 20, xmin = 700000, xmax = 700400, ymin = 3600000, ymax = 3600400, crs = "EPSG:32636")
  field <- .mh_square(700040, 700240, 3600060, 3600300)             # 10 x 12 whole cells
  binary <- wapor_rasterize_mask(sf::st_transform(field, 4326), template)
  expect_equal(sum(!is.na(terra::values(binary))), 120)
  expect_equal(attr(binary, "area_ratio"), 1, tolerance = 1e-5)   # the lon/lat rectangle is not exactly straight in UTM
  cut <- .mh_square(700047, 700233, 3600053, 3600307)               # borders cut cells
  frac <- wapor_rasterize_mask(cut, template, fraction = TRUE)
  expect_equal(attr(frac, "area_ratio"), 1, tolerance = 1e-6)        # fractions reproduce the area exactly
  expect_equal(sum(terra::values(frac)) * 400, 186 * 254, tolerance = 1e-6)
  expect_identical(names(frac), "crop_mask")
  # A lon/lat template: the ratio still compares like with like.
  ll <- terra::rast(nrows = 40, ncols = 40, xmin = 35, xmax = 35.4, ymin = 32, ymax = 32.4, crs = "EPSG:4326")
  f_ll <- wapor_rasterize_mask(.mh_square(35.1, 35.25, 32.1, 32.3, 4326), ll, fraction = TRUE)
  expect_equal(attr(f_ll, "area_ratio"), 1, tolerance = 1e-3)
})

test_that("a centre-based mask that misses the area warns for polygons of 25 cells or more", {
  template <- terra::rast(nrows = 20, ncols = 20, xmin = 700000, xmax = 700400, ymin = 3600000, ymax = 3600400, crs = "EPSG:32636")
  sliver <- .mh_square(700000, 700400, 3600001, 3600009)            # 400 m x 8 m: 8 cells' worth, no centre inside
  expect_no_warning(m <- wapor_rasterize_mask(sliver, template))
  expect_equal(attr(m, "area_ratio"), 0)
  strip <- .mh_square(700000, 700400, 3600001, 3600029)             # 400 m x 28 m = 28 cells' worth, one row of centres
  expect_warning(wapor_rasterize_mask(strip, template), "71% of the polygon area")
  expect_warning(wapor_rasterize_mask(strip, template, touches = TRUE), "143% of the polygon area")
  expect_no_warning(wapor_rasterize_mask(strip, template, fraction = TRUE))
})

test_that("fractions of adjacent polygons add up in a shared cell", {
  template <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 40, ymin = 0, ymax = 20, crs = "EPSG:32636")
  halves <- rbind(.mh_square(0, 10, 0, 20), .mh_square(10, 30, 0, 20))   # split cell 1, half of cell 2
  m <- wapor_rasterize_mask(halves, template, fraction = TRUE)
  expect_equal(unname(terra::values(m)[, 1]), c(1, 0.5))
})

test_that("harmonize counts NoData as not the class and returns the winning class for several", {
  target <- terra::rast(nrows = 1, ncols = 2, xmin = 0, xmax = 40, ymin = 0, ymax = 20, crs = "EPSG:32636")
  # 10 m map, 2 x 4 cells: left target cell holds 1, 1, 2, NA; right holds 2, 2, 2, 1
  map <- terra::rast(nrows = 2, ncols = 4, xmin = 0, xmax = 40, ymin = 0, ymax = 20, crs = "EPSG:32636",
                     vals = c(1, 1, 2, 2,
                              2, NA, 2, 1))
  one <- wapor_harmonize_mask(map, target, 1)
  expect_equal(unname(terra::values(one$fraction)[, 1]), c(0.5, 0.25))   # 2 of 4 (NoData is not class 1), 1 of 4
  expect_equal(unname(terra::values(one$mask)[, 1]), c(1, NA))
  both <- wapor_harmonize_mask(map, target, c(1, 2), min_fraction = 0.5)
  expect_equal(unname(terra::values(both$fraction)[, 1]), c(0.5, 0.75))
  expect_equal(unname(terra::values(both$mask)[, 1]), c(1, 2))           # the winner's class code
  expect_equal(unname(terra::values(wapor_harmonize_mask(map, target, c(2, 1), min_fraction = 0.5)$mask)[, 1]), c(1, 2))
  expect_equal(unname(terra::values(wapor_harmonize_mask(map, target, c(1, 2), value = 9, return_fraction = FALSE))[, 1]), c(9, 9))
  expect_error(wapor_harmonize_mask(map, target, 1, min_fraction = 2), "between 0 and 1")
})
