setwd("c:/Users/Mohammedal/OneDrive - Food and Agriculture Organization/Documents/GitHub/Rwapor")

path <- "R/wapor_ts.R"
lines <- readLines(path, warn = FALSE)

# Find artifact lines: entire line is digits followed by colon and optional spaces
# e.g. "140: " or "302:" or "140:  "
artifact_pattern <- "^[0-9]+: *$"
is_artifact <- grepl(artifact_pattern, lines)
cat("Artifact lines found:", sum(is_artifact), "\n")
cat("Artifact line numbers:", which(is_artifact)[1:min(10, sum(is_artifact))], "\n")

# Replace artifact lines with empty lines
lines[is_artifact] <- ""

# Write back
writeLines(lines, path)
cat("Fixed and saved.\n")

# Verify
lines2 <- readLines(path, warn = FALSE)
remaining <- sum(grepl(artifact_pattern, lines2))
cat("Remaining artifacts after fix:", remaining, "\n")
