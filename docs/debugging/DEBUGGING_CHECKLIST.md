# Rwapor Debugging Checklist

Use this checklist for API, raster, seasonal analysis, Shiny, performance, testing, and data coverage debugging tasks.

## 1. Session Setup

- Confirm you are in repo root.
- Use R 4.5.3 executable path:
  - `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe`
- Run environment diagnostics:

```powershell
C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe dev-tools/scripts/debug/check_env_windows.R
```

## 2. Reproduce Minimally

- Capture exact failing input (variable code, period, AOI, source mode).
- Reduce to minimal reproducible case.
- Save exact error output and traceback.

## 3. Classify Failure Mode

- API/connectivity: network, auth, no-data, invalid code.
- Raster geometry: CRS mismatch, no overlap, resolution conflict.
- Seasonal engine: period shape, class mask/season raster assumptions.
- Shiny state: observer loops, invalid reactive state, disconnects.
- Performance: memory spikes, repeated scans, slow aggregation.
- Test/reproducibility: flaky tests, path escaping, fixture drift.
- Coverage/validation: missing local dekads vs unavailable upstream data.

## 4. Focused Commands

Targeted test:

```powershell
C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe -e "testthat::test_file('tests/testthat/test-analysis-shiny.R')"
```

All tests:

```powershell
C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe -e "devtools::test()"
```

Documentation refresh after API/public changes:

```powershell
C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe -e "devtools::document()"
```

## 5. Debug Helpers

- Environment check: `dev-tools/scripts/debug/check_env_windows.R`
- API repro harness: `dev-tools/scripts/debug/repro_api_failure.R`
- Raster alignment harness: `dev-tools/scripts/debug/repro_alignment_check.R`
- Mock stack generator: `dev-tools/scripts/debug/mock_wapor_stacks.R`
- Profiling harness: `dev-tools/scripts/debug/profile_seasonal_analysis.R`

## 6. Exit Criteria

- Root cause identified with evidence.
- Fix validated against repro.
- Regression test added or updated.
- User-facing behavior change documented when applicable.
