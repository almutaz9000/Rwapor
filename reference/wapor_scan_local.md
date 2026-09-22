# Scan Local Folder for Available Variables

Scans a download folder to find which WaPOR/AgERA5 variables are
available locally, along with their date ranges.

## Usage

``` r
wapor_scan_local(folder)
```

## Arguments

- folder:

  Character. Path to the download folder.

## Value

A data.frame with columns: variable, file_count, min_date, max_date,
folder_path. Returns empty data.frame if no variables found.
