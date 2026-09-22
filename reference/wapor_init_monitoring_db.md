# Initialize a DuckDB database for farm monitoring

Creates all required tables (if they do not yet exist) and runs any
pending schema migrations against an existing database. The function is
idempotent: calling it on a fully up-to-date database is a no-op.

## Usage

``` r
wapor_init_monitoring_db(con)
```

## Arguments

- con:

  DuckDB connection object.

## Value

The connection object invisibly.
