---
allowed-tools: Bash("/c/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/x64/Rscript.exe":*)
description: Run devtools::check() — full R CMD check including documentation, tests, and CRAN checks
---

## Context

- R executable: `/c/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/x64/Rscript.exe`
- Project root: !`pwd`
- Current branch: !`git branch --show-current`

## Task

Run a full R CMD check via devtools:

```bash
"/c/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/x64/Rscript.exe" -e "devtools::check()"
```

This will:
- Rebuild documentation
- Run all examples
- Run all tests
- Check NAMESPACE completeness
- Check for CRAN policy compliance

After completion, report:
1. **ERRORs** — must be fixed before any release or PR merge
2. **WARNINGs** — should be fixed; flag any that are pre-existing vs new
3. **NOTEs** — informational; flag if new since last check
4. Overall verdict: PASS / FAIL

Do not attempt to fix issues unless the user asks.
