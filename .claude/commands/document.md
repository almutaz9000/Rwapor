---
allowed-tools: Bash("/c/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/x64/Rscript.exe":*)
description: Run devtools::document() to regenerate NAMESPACE and man/ from roxygen2 comments
---

## Context

- R executable: `/c/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/x64/Rscript.exe`
- Project root: !`pwd`
- Modified R files (may need redocumenting): !`git diff --name-only HEAD | grep "^R/"`

## Task

Run `devtools::document()` to regenerate the NAMESPACE file and all `.Rd` files in `man/` from roxygen2 comments in `R/`.

```bash
"/c/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/x64/Rscript.exe" -e "devtools::document()"
```

After the command completes:
1. Report which `.Rd` files were updated or created
2. Report if NAMESPACE changed
3. If there were any warnings or errors in the roxygen2 parsing, highlight them clearly
4. Do not make any code changes — only run documentation generation
