d <- as.Date(unlist(lapply(2023:2024, function(y) sprintf("%d-%02d-%02d", y, rep(1:12, each = 3), c(1, 11, 21)))))
bin <- as.integer(d - as.Date("2023-01-01")) %/% 10
cat("dekads:", length(d), " distinct P10D bins hit:", length(unique(bin)), "\n")
dup <- bin[duplicated(bin)]
cat("bins holding two dekads:", length(dup), "\n")
for (b in utils::head(dup, 3)) cat("  bin starting", format(as.Date("2023-01-01") + b * 10), "<-", paste(format(d[bin == b]), collapse = " and "), "\n")
allb <- seq(0, max(bin)); cat("empty bins inside the range:", sum(!allb %in% bin), "\n")
len <- as.integer(diff(c(d, as.Date("2025-01-01")))); cat("dekad lengths:", paste(names(table(len)), "days x", table(len), collapse = ", "), "\n")
