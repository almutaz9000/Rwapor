# Project Memory

_Last updated: 2026-05-11_

## Confirmed Patterns

- **Shared workflow is canonical**: Use `agent-workflow/` as the single source of truth. Model-specific folders are adapters only.
- **Production-first repo layout**: Keep package runtime artifacts at root (`R/`, `inst/`, `man/`, `tests/testthat/`, `vignettes/`) and move development-only artifacts under `dev-archive/`.
- **Developer tooling location**: Keep non-package helper scripts in `dev-tools/scripts/` and update docs when script paths move.
- **R stack**: Use `terra` and `sf`. Do not introduce `raster` or `sp` into active workflows.
- **R version**: Use `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe` for package commands.
- **Vectorized zonal stats**: Prefer passing full multi-layer stacks to `exactextractr::exact_extract()` once and using matrix-style aggregation instead of looping layer-by-layer, which recomputes polygon coverage and is much slower.
- **Metadata-driven aggregation**: Seasonal aggregation behavior comes from variable metadata and units, not hardcoded rules.
- **Dekadal defaults**: WaPOR `-D` variables with `/day` units are expected to auto-convert to dekadal totals unless the user overrides that behavior.
- **Temperature conversion**: AGERA5 `TMIN` and `TMAX` should convert from Kelvin to Celsius automatically in download paths.
- **Scale factors**: `terra::rast()` already applies embedded scale and offset metadata. Do not scale those rasters a second time.
- **Windows path stability**: Prefer existing helpers such as `safe_project()` and `wapor_fix_proj()` when CRS or PROJ issues appear on Windows and OneDrive paths.
- **Zonal stats**: `exactextractr` remains the preferred engine for weighted polygon summaries.

## Avoid

- **Parallel project memory**: Do not store independent repo truth in `.claude/`, `.gemini/`, `.agent/`, or `.github/agents/`.
- **Manual scale-factor math**: Avoid multiplying rasters by metadata scale values when `terra` already handled them.
- **Mixed raster stacks**: Avoid mixing `terra` and `raster` object types in the same workflow.
- **Per-layer exactextract loops**: Avoid calling `exact_extract()` once per raster layer when one multi-layer extraction can reuse coverage fractions.
- **Hardcoded variable codes**: Avoid pinning analysis logic to fixed WaPOR variable strings when the value should come from user input or metadata.
- **Whole-package scanning for local fixes**: Start from the relevant files and only widen scope when the evidence requires it.

## Active Constraints

- Keep `agent-workflow/session-brief.md` short enough to be the default first read.
- Use `agent-workflow/task-status.md` and `agent-workflow/issues-log.md` for live execution state.
- Use `inst/agent_skills/RWAPOR_AGENT_SKILLS.md` for package usage guidance, not for session state.
