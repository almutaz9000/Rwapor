#' Unit Converter for DataFrames
#'
#' @param df DataFrame containing variable data
#' @param unit_conversion Target unit ("none", "day", "dekad", "month", "year")
#' @return Converted DataFrame
#' @importFrom lubridate days_in_month ymd
#' @export
df_unit_convertor <- function(df, unit_conversion) {
  if (unit_conversion == "none") return(df)
  
  source_unit <- attr(df, "units")
  parts <- strsplit(source_unit, "/")[[1]]
  source_time <- parts[length(parts)]
  
  # Conversion factors
  # We need to iterate or vectorise. 
  # In R, we can calculate a vector of factors.
  
  days_in_current_month <- lubridate::days_in_month(lubridate::ymd(df$start_date))
  
  factor <- rep(1, nrow(df))
  
  if (source_time == "day") {
    if (unit_conversion == "day") factor <- 1
    else if (unit_conversion == "dekad") factor <- df$number_of_days
    else if (unit_conversion == "month") factor <- days_in_current_month
    else if (unit_conversion == "year") factor <- 365
  } else if (source_time == "dekad") {
    if (unit_conversion == "day") factor <- 1 / df$number_of_days
    else if (unit_conversion == "dekad") factor <- 1
    else if (unit_conversion == "month") factor <- 3 # Approximation often used? Or Python uses 3.
    else if (unit_conversion == "year") factor <- 36
  } else if (source_time == "month") {
    if (unit_conversion == "day") factor <- 1 / days_in_current_month
    else if (unit_conversion == "dekad") factor <- 1 / 3
    else if (unit_conversion == "month") factor <- 1
    else if (unit_conversion == "year") factor <- 12
  } else if (source_time == "year") {
    if (unit_conversion == "day") factor <- 1 / 365
    else if (unit_conversion == "dekad") factor <- 1 / 36
    else if (unit_conversion == "month") factor <- 1 / 12
    else if (unit_conversion == "year") factor <- 1
  }
  
  cols <- c("mean", "min", "max", "median") # Add others if present
  existing_cols <- intersect(names(df), cols)
  
  df[existing_cols] <- df[existing_cols] * factor
  
  # Update attributes
  attr(df, "original_units") <- source_unit
  attr(df, "units") <- paste0(paste(parts[-length(parts)], collapse="/"), "/", unit_conversion)
  
  return(df)
}

#' Unit Converter for Rasters
#'
#' @param r SpatRaster
#' @param variable Variable name to determine temporal resolution
#' @param urls List of URLs corresponding to layers
#' @param unit_conversion Target unit
#' @return Converted SpatRaster
#' @importFrom terra app nlyr
#' @export
raster_unit_convertor <- function(r, variable, urls, unit_conversion) {
  if (unit_conversion == "none") return(r)
  
  parts <- strsplit(variable, "-")[[1]]
  tres <- tail(parts, 1)
  
  # Check if we need conversion
  # We need metadata to know source unit. Assuming WAPOR vars.
  # But for simplicity, we can infer from variable name and WAPOR3_VARS.
  # Or just use the fact that we know 'tres'.
  
  # Let's iterate over layers
  for (i in seq_len(terra::nlyr(r))) {
    url <- urls[i]
    date_info <- get_date_info(url, tres)
    
    # Calculate factor for this layer
    # This logic mirrors df_unit_convertor but for a single scalar factor per layer
    
    # We need source unit time. 
    source_time <- switch(tres,
                          "D" = "dekad",
                          "M" = "month",
                          "A" = "year",
                          "E" = "day")
    
    days_in_current_month <- lubridate::days_in_month(lubridate::ymd(date_info$start_date))
    num_days <- date_info$number_of_days
    
    factor <- 1
    
    if (source_time == "day") {
      if (unit_conversion == "day") factor <- 1
      else if (unit_conversion == "dekad") factor <- num_days
      else if (unit_conversion == "month") factor <- days_in_current_month
      else if (unit_conversion == "year") factor <- 365
    } else if (source_time == "dekad") {
      if (unit_conversion == "day") factor <- 1 / num_days
      else if (unit_conversion == "dekad") factor <- 1
      else if (unit_conversion == "month") factor <- 3 
      else if (unit_conversion == "year") factor <- 36
    } else if (source_time == "month") {
      if (unit_conversion == "day") factor <- 1 / days_in_current_month
      else if (unit_conversion == "dekad") factor <- 1 / 3
      else if (unit_conversion == "month") factor <- 1
      else if (unit_conversion == "year") factor <- 12
    } else if (source_time == "year") {
      if (unit_conversion == "day") factor <- 1 / 365
      else if (unit_conversion == "dekad") factor <- 1 / 36
      else if (unit_conversion == "month") factor <- 1 / 12
      else if (unit_conversion == "year") factor <- 1
    }
    
    if (factor != 1) {
      r[[i]] <- r[[i]] * factor
    }
  }
  
  return(r)
}
