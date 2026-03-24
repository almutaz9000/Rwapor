# Helper to source all R files
r_path <- if (dir.exists("R")) "R" else "../R"
r_files <- list.files(r_path, pattern = "\\.[Rr]$", full.names = TRUE)
for (f in r_files) source(f)
