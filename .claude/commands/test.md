---
allowed-tools: Bash("/c/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/x64/Rscript.exe":*)
description: Run devtools::test() with an optional filter argument to run specific test files
argument-hint: Optional filter string, e.g. "analysis" or "plan_wapor"
---

## Context

- R executable: `/c/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/x64/Rscript.exe`
- Project root: !`pwd`
- Available test files: !`ls tests/testthat/test-*.R 2>/dev/null`
- Filter argument: $ARGUMENTS

## Task

Run the testthat test suite using devtools.

**If a filter argument was provided** (`$ARGUMENTS` is not empty), run only matching tests:
```bash
"/c/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/x64/Rscript.exe" -e "devtools::test(filter='$ARGUMENTS')"
```

**If no filter argument**, run the full suite:
```bash
"/c/Users/Mohammedal/AppData/Local/Programs/R/R-4.5.3/bin/x64/Rscript.exe" -e "devtools::test()"
```

After the run completes:
1. Summarise: total tests, passed, failed, skipped, warnings
2. For any failures, quote the test name, the expectation that failed, and the actual vs expected values
3. Do not attempt to fix failures unless the user asks
