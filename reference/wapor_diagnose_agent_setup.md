# Diagnose Agent and System Setup

Runs diagnostic checks on the active system to verify R version, spatial
libraries (GDAL/PROJ), package dependencies, gcloud authentication, and
path/OneDrive configurations. Prints a detailed markdown report useful
for troubleshooting agent environments.

## Usage

``` r
wapor_diagnose_agent_setup()
```

## Value

Invisibly returns the diagnostic report string.

## Examples

``` r
if (FALSE) { # \dontrun{
wapor_diagnose_agent_setup()
} # }
```
