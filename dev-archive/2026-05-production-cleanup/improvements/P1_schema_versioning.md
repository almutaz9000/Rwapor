# Implementation Plan: Database Schema Versioning & Migrations (P1)

## Goal
Implement a robust mechanism to track the database schema version and automatically apply migrations (updates) when the package is updated. This prevents crashes when users connect to older databases with an outdated table structure.

## Proposed Changes

### `R/wapor_monitoring.R`
- Add a new internal function `.check_and_update_schema(con)`.
- This function will:
  1. Check for a `schema_info` table.
  2. If missing, create it and set `version = 0.9.7`.
  3. Compare the current version with the package version.
  4. Apply a sequence of `ALTER TABLE` commands for any missing columns or new tables.

### `R/utils.R`
- Define a central version constant `RWAPOR_SCHEMA_VERSION <- "0.9.7"`.

## Verification Plan
1. Create a database with the old schema (0.9.6).
2. Connect using the new package version.
3. Verify that the `schema_info` table is created and that any new columns (like `std_val` in `farm_timeseries`) are automatically added without user intervention.
