---
description: Scaffold a new exported analysis function in R/analysis_indicators.R following Rwapor conventions
argument-hint: Function name and brief description, e.g. "compute_cwp_net Net crop water productivity"
---

# New Analysis Function

Scaffold a new exported analysis function for the Rwapor package.

Initial request: $ARGUMENTS

## Phase 1: Understand the request

Parse `$ARGUMENTS` to extract:
- **Function name** (snake_case, should start with a domain prefix like `compute_`, `season_`, `calc_`)
- **What it computes** (brief description)

If either is unclear, ask the user before proceeding.

## Phase 2: Read existing patterns

Read these files to understand conventions before writing any code:
1. `R/analysis_indicators.R` — existing indicator functions (structure, roxygen style, parameter names)
2. `R/analysis.R` — how indicators are called and composed
3. `NAMESPACE` — to understand what is currently exported

Look for:
- Parameter naming conventions (`rast`, `mask`, `season`, `crop_coef`, etc.)
- Return value conventions (named list, single raster, data frame?)
- How `terra::` functions are called
- Roxygen2 tag patterns: `@param`, `@return`, `@export`, `@examples`, `@seealso`
- Whether the function should use `@importFrom` or `terra::` prefix

## Phase 3: Clarify before coding

Ask the user:
1. What are the inputs? (rasters, scalars, data frames?)
2. What does the function return? (terra SpatRaster, numeric vector, data frame?)
3. Should it be exported (`@export`) or internal?
4. Are there crop coefficient or season parameters involved?
5. Any edge cases to handle (NA masking, unit conversion)?

Wait for answers.

## Phase 4: Implement

Write the function in `R/analysis_indicators.R` (at the end of the file, before the last blank line):
- Full roxygen2 block with `@title`, `@description`, `@param` for each arg, `@return`, `@export` (if applicable), `@examples`
- Function body following existing patterns (use `terra::` prefix, handle NAs, follow unit conventions)
- No comments explaining what the code does — only non-obvious WHY comments

After writing, confirm: "Added `function_name()` to R/analysis_indicators.R. Run `/document` to regenerate docs."
