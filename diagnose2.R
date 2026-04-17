setwd("c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor")
devtools::load_all(".", quiet = TRUE)
library(sf)

farms_sf <- sf::st_read("Pivots_savola2.geojson", quiet = TRUE)
farms_sf[["farm_id"]] <- paste0("farm_", seq_len(nrow(farms_sf)))
small <- farms_sf[1:2, ]

# Step 1: Check wapor_parse_region
cat("--- wapor_parse_region ---\n")
reg_info <- Rwapor:::wapor_parse_region(small)
cat("type:", reg_info$type, "\n")
vect <- reg_info$value
cat("vect class:", paste(class(vect), collapse = ", "), "\n")
cat("vect dims:", nrow(vect), "x", ncol(vect), "\n")
cat("farm_id column:", head(vect$farm_id, 3), "\n")

# Step 2: Try getting URLs
cat("\n--- wapor_generate_urls ---\n")
urls <- tryCatch(
  Rwapor::wapor_generate_urls("L1-PCP-D", period = c("2020-01-01", "2020-01-31")),
  error = function(e) { cat("URL error:", e$message, "\n"); NULL }
)
cat("URLs found:", length(urls), "\n")
if (length(urls) > 0) cat("First URL:", substr(urls[1], 1, 80), "\n")

# Step 3: Try loading one raster
if (!is.null(urls) && length(urls) > 0) {
  cat("\n--- loading raster ---\n")
  url_vs <- paste0("/vsicurl/", urls[1])
  r <- tryCatch(
    suppressWarnings(terra::rast(url_vs)),
    error = function(e) { cat("Raster error:", e$message, "\n"); NULL }
  )
  if (!is.null(r)) {
    cat("Raster loaded. Dims:", dim(r), "\n")
    cat("CRS:", terra::crs(r, describe = TRUE)$name, "\n")

    # Step 4: crop to farm extent
    cat("\n--- cropping ---\n")
    bb <- sf::st_bbox(small)
    aoi_ext <- terra::ext(bb["xmin"], bb["xmax"], bb["ymin"], bb["ymax"])
    cat("AOI:", as.numeric(aoi_ext), "\n")
    cat("Raster ext:", as.numeric(terra::ext(r)), "\n")
    r_crop <- tryCatch(terra::crop(r, aoi_ext), error = function(e) { cat("Crop error:", e$message, "\n"); NULL })
    if (!is.null(r_crop)) cat("Cropped raster dims:", dim(r_crop), "\n")

    # Step 5: try exactextractr
    cat("\n--- exactextractr ---\n")
    names(r_crop) <- "L1"
    ex <- tryCatch(
      suppressWarnings(exactextractr::exact_extract(r_crop, small, c("mean", "min", "max"), progress = FALSE)),
      error = function(e) { cat("exactextractr error:", e$message, "\n"); NULL }
    )
    if (!is.null(ex)) {
      cat("exactextractr result:\n")
      print(ex)

      # Step 6: the assignment that might fail
      cat("\n--- Assignment test ---\n")
      ids <- vect[["farm_id"]]
      cat("ids:", ids, "\n")
      ex$ID <- seq_len(nrow(ex))
      cat("ex$ID:", ex$ID, "\n")

      sub_df <- ex[, c("mean.L1", "min.L1", "max.L1"), drop = FALSE]
      cat("sub_df nrow:", nrow(sub_df), "\n")

      # The potentially failing line
      sub_df$ID <- ids[ex$ID]
      cat("sub_df$ID:", sub_df$ID, "\n")

      identifier <- "farm_id"
      cat("Setting sub_df[[identifier]]...\n")
      sub_df[[identifier]] <- ids[ex$ID]
      cat("Success! sub_df$farm_id:", sub_df$farm_id, "\n")
    }
  }
}
