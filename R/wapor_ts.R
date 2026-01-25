#' Download a Time Series
#'
#' @param region Region definition
#' @param variable Variable name
#' @param period Date range
#' @param identifier Column name in vector file to identify polygons (optional)
#' @param unit_conversion Target unit conversion
#' @param download_locally If TRUE, download files using parallel processing before reading
#' @return DataFrame with zonal statistics
#' @importFrom terra rast crop extract
#' @importFrom dplyr bind_rows mutate group_by summarize left_join
#' @importFrom purrr map_dfr
#' @importFrom sf st_drop_geometry
#' @export
wapor_ts <- function(region, variable, period, identifier = NULL, unit_conversion = "none", download_locally = FALSE) {
  
  # Parse region
  reg_info <- parse_region(region)
  l3_code <- if (reg_info$type == "l3_code") reg_info$value else NULL
  
  # Get URLs
  urls <- wapor_generate_urls(variable, l3_region = l3_code, period = period)
  if (length(urls) == 0) stop("No data found.")
  
  # Download locally if requested
  if (download_locally) {
      # Use a robust temp cache
      temp_dl_folder <- file.path(tempdir(), "rwapor_cache")
      message("Downloading files locally for processing (Parallel) to: ", temp_dl_folder)
      urls <- download_urls_parallel(urls, temp_dl_folder)
  }
  
  message(sprintf("Found %d files. Processing...", length(urls)))
  
  # Helper to process in chunks if needed, but for now load all.
  # If remote URLs, terra::rast might be lazy which is good.
  r <- terra::rast(urls)
  
  # Crop if needed
  vect <- NULL
  if (reg_info$type == "vector") {
    vect <- reg_info$value
    if (sf::st_crs(vect)$epsg != 4326) vect <- sf::st_transform(vect, 4326)
    v <- terra::vect(vect)
    r <- terra::crop(r, v)
    # Masking is expensive for TS extraction depending on extract method.
    # exact_extract is faster. Here we use terra::extract.
  } else if (reg_info$type == "bbox") {
    ext <- terra::ext(reg_info$value[c("xmin", "xmax", "ymin", "ymax")])
    r <- terra::crop(r, ext)
  }
  
  # Extract
  # We want mean, min, max per polygon/region
  # If region is bbox or l3_code (no polygons), it's one big region.
  
  stats <- list()
  
  if (!is.null(vect)) {
    # Zonal stats
    # use terra::extract
    # small optimization: exact_extractr is better for polygons but strict dependency?
    # Let's stick to terra.
    
    # We also need to apply scaling factor?
    # WaPOR rasters are usually Int32 with scale factor.
    # terra applies scale/offset automatically if in metadata.
    
    vals <- terra::extract(r, v, fun = NULL, na.rm = TRUE) # Get raw values to calc multiple stats?
    # Or separate calls? separate calls is slow.
    # terra::extract with fun=mean returns mean.
    
    # Better: extract returns a DF with ID and values.
    # With many layers, it's (ID, lyr1, lyr2, ...)
    # For large time series, this might be wide.
    
    # Actually, we can pass a function to extract that returns multiple valid
    # e.g. fun=function(x) c(mean=mean(x, na.rm=T), min=min(x, na.rm=T), max=max(x, na.rm=T))
    
    msg_extract <- capture.output(
      ex <- terra::extract(r, v, fun = function(x) c(mean = mean(x, na.rm=TRUE), 
                                                     min = min(x, na.rm=TRUE), 
                                                     max = max(x, na.rm=TRUE)))
    )
    
    # ex structure: ID, lyr1.mean, lyr1.min, lyr1.max, lyr2.mean ...
    # We need to reshape this.
    
  } else {
    # global stats for the whole raster (cropped)
    # terra::global
    ex <- terra::global(r, fun = c("mean", "min", "max"), na.rm = TRUE)
    # ex structure: mean, min, max rows per layer?
    # terra::global returns rows = layers, cols = stats provided.
    ex$ID <- 1
    # We match the structure of extract somewhat?
    # output of global:
    #      mean       min       max
    # lyr1  ...       ...       ...
    # lyr2  ...       ...       ...
    
    # We need to convert this to long format with dates.
  }
  
  # Post-processing to creating the DataFrame
  # We need to map Layer Index -> Date/Url -> Date Info
  
  parts <- strsplit(variable, "-")[[1]]
  tres <- tail(parts, 1)
  
  # Gather metadata for all layers
  meta_list <- lapply(urls, function(u) get_date_info(u, tres))
  # Create a lookup DF
  meta_df <- do.call(rbind, lapply(meta_list, as.data.frame))
  meta_df$layer_index <- 1:nrow(meta_df)
  # row.names(ex) usually matches layer names.
  
  results <- list()
  
  if (is.null(vect)) {
    # Global stats
    # ex has rows corresponding to layers
    df_res <- cbind(meta_df, ex)
    # ex cols: mean, min, max
    # We assume simple single region
    df_res$region_id <- 1
    results[[1]] <- df_res
  } else {
    # Zonal stats result `ex` is wide: ID, lyr1.mean, ...
    # This is painful to reshape if many layers.
    
    # Alternative approach: iterate over layers?
    # No, extract is efficient for all layers.
    
    # Reshaping:
    # ID | lyr1.mean | lyr1.min | ...
    
    # Let's pivot longer?
    # tidyr::pivot_longer
    
    # But names are messy.
    # terra names layers usually by filename or default.
    # Let's rely on column order if we sort it?
    # Or we can rely on `names(r)`.
    
    # Robust Zonal stats using exactextractr
    # This handles small polygons correctly by using fractional coverage
    
    # Make sure r names are consistent
    names(r) <- paste0("L", 1:terra::nlyr(r))
    
    # exact_extract returns a dataframe with one row per feature
    # Cols: <layer_name>.<stat>
    ex <- exactextractr::exact_extract(r, sf::st_as_sf(v), c("mean", "min", "max"), progress = FALSE)
    
    # Add ID column to match previous logic (row index as ID)
    ex$ID <- 1:nrow(ex)
    
    # ex columns: mean.L1, min.L1, max.L1 ... OR L1.mean if logic differs?
    # exact_extract naming convention: <stat>.<layer> usually if multiple layers?
    # Actually for named layers it seems to be <layer_name>.<stat> in recent versions or <stat>.<layer_name>
    # Let's check documentation or assume standard behavior. 
    # Usually it is <layer_name>.<stat> if stacks are named.
    # However, exact_extract might output `mean.L1`, `min.L1`.
    
    # Let's standardize names to sure. 
    # If standard output is `mean.L1`, `min.L1`, `max.L1`
    
    n_poly <- nrow(v)
    n_lyr <- terra::nlyr(r)
    
    # Extract IDs
    ids <- if (!is.null(identifier)) vect[[identifier]] else 1:n_poly
    
    out_list <- list()
    
    for (i in 1:n_lyr) {
      lyr_name <- paste0("L", i)
      # Check likely column names
      # exact_extract typically: <stat>.<layer>
      col_mean <- paste0("mean.", lyr_name)
      col_min <- paste0("min.", lyr_name)
      col_max <- paste0("max.", lyr_name)
      
      # Fallback if names are reversed (some versions do <layer>.<stat>)
      if (!col_mean %in% names(ex) && paste0(lyr_name, ".mean") %in% names(ex)) {
          col_mean <- paste0(lyr_name, ".mean")
          col_min <- paste0(lyr_name, ".min")
          col_max <- paste0(lyr_name, ".max")
      }
      
      cols <- c(col_mean, col_min, col_max)
      
      sub_df <- ex[, cols, drop = FALSE]
      colnames(sub_df) <- c("mean", "min", "max")
      
      sub_df$ID <- ids[ex$ID] # map ID correctly? ex$ID usually 1..N
      if (!is.null(identifier)) {
          # if identifer is provided, we map internal ID (1..N) to that identifier
          sub_df[[identifier]] <- ids[ex$ID]
      }
      
      # Add metadata
      m <- meta_df[i, ]
      # Replicate metadata for each polygon
      m_rep <- m[rep(1, nrow(sub_df)), ]
      
      combined <- cbind(sub_df, m_rep)
      out_list[[i]] <- combined
    }
    
    results <- do.call(rbind, out_list)
  }
  
  final_df <- if (is.data.frame(results)) results else do.call(rbind, results)
  
  # Get Source Units using dynamic/static fetcher
  source_var_meta <- get_variable_metadata(variable)
  
  if (!is.null(source_var_meta)) {
    attr(final_df, "units") <- source_var_meta$units
    attr(final_df, "long_name") <- source_var_meta$long_name
  } else {
    attr(final_df, "units") <- "unknown" # Should not happen if Vars complete
  }
  
  # Apply Unit Conversion
  final_df <- df_unit_convertor(final_df, unit_conversion)
  
  return(final_df)
}
