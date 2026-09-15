# Scrape FAO Crop Data (Kc and Growth Stages)
#
# Source: FAO Irrigation and Drainage Paper No. 56, Chapter 6
# URL: https://www.fao.org/3/X0490E/x0490e0b.htm

library(httr2)
library(xml2)

get_repo_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- args[grepl("^--file=", args)]

  if (length(file_arg) > 0) {
    script_path <- normalizePath(sub("^--file=", "", file_arg[[1]]),
      winslash = "/", mustWork = TRUE
    )
    return(normalizePath(file.path(dirname(script_path), "..", ".."),
      winslash = "/", mustWork = TRUE
    ))
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

fetch_fao_table <- function(url, table_index = 1) {
  req <- request(url)
  resp <- req_perform(req)
  html <- read_html(resp_body_string(resp))
  
  tables <- xml_find_all(html, ".//table")
  if (length(tables) < table_index) {
    stop("Table index ", table_index, " not found on page.")
  }
  
  target_table <- tables[[table_index]]
  
  # Simple extraction (note: complex tables with rowspanning might need more logic)
  rows <- xml_find_all(target_table, ".//tr")
  data_list <- lapply(rows, function(row) {
    cells <- xml_find_all(row, ".//td|.//th")
    xml_text(cells, trim = TRUE)
  })
  
  # Find max columns
  max_cols <- max(sapply(data_list, length))
  
  # Standardize rows
  standard_data <- lapply(data_list, function(x) {
    if (length(x) < max_cols) c(x, rep(NA, max_cols - length(x)))
    else x
  })
  
  df <- as.data.frame(do.call(rbind, standard_data))
  return(df)
}

# ------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------
url <- "https://www.fao.org/3/X0490E/x0490e0b.htm"
repo_root <- get_repo_root()

growth_stages_out <- file.path(repo_root, "fao_growth_stages.csv")
crop_coeff_out <- file.path(repo_root, "fao_crop_coefficients.csv")

cat("=== Extracting FAO Crop Data ===\n")

# Table 11: Lengths of crop development stages
cat("\n--- Table 11: Growth Stages ---\n")
tryCatch({
  df11 <- fetch_fao_table(url, 1)
  # Cleaning: The first few rows are headers
  print(head(df11, 10))
  # Save to CSV
  write.csv(df11, growth_stages_out, row.names = FALSE)
  cat("Saved to ", growth_stages_out, "\n", sep = "")
}, error = function(e) cat("Error fetching Table 11: ", e$message, "\n"))

# Table 12: Crop coefficients (Kc)
cat("\n--- Table 12: Crop Coefficients (Kc) ---\n")
tryCatch({
  df12 <- fetch_fao_table(url, 2)
  print(head(df12, 10))
  # Save to CSV
  write.csv(df12, crop_coeff_out, row.names = FALSE)
  cat("Saved to ", crop_coeff_out, "\n", sep = "")
}, error = function(e) cat("Error fetching Table 12: ", e$message, "\n"))

cat("\n=== Extraction Complete ===\n")
