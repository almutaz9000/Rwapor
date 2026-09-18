# Project Memory

_Durable, curated lessons only. Not a diary, not a copy of `git log`. See
`templates/memory-entry.md` for the entry format. Keep this file curated —
merge or remove stale entries rather than letting it grow unbounded._

## Confirmed Working Patterns

- **Rscript path (Windows)**: use
  `C:\Users\Mohammedal\AppData\Local\Programs\R\R-4.5.3\bin\Rscript.exe` for
  `devtools::document()`, `devtools::test()`, and `devtools::check()`. Plain
  `Rscript` is not on PATH in the Bash tool's environment.
- **Raster engine**: this package uses `terra` (and `sf`) exclusively. Never
  introduce the legacy `raster` package.
- **NAMESPACE**: always generated via `devtools::document()`; never hand-edit.
- **WaPOR variable metadata is static and curated**: `WAPOR3_VARS` in
  `R/metadata.R` explicitly lists L1/L2/L3 entries — it is not fetched live.
  L3 entries generally exist directly in the list; the "borrow L2's temporal
  codes" fallback in `wapor_temporal_codes()` (`R/plan_wapor_time_slices.R`)
  only fires for variable/resolution combos genuinely absent from the list,
  which is rare in practice.
- **Seasonal download shape**: `download_seasonal_rasters()`
  (`R/seasonal_download.R`) is the shared helper behind both `wapor_map()` and
  `wapor_ts()` when `seasonal = TRUE`. It calls `wapor_plan_time_slices()` to
  build an optimum coarsest-sufficient plan, then downloads one code group
  (A/M/D/E) at a time and applies per-layer multipliers from
  `get_seasonal_multiplier_values()`.
- **Retry policy**: shared GISMGR API retry logic lives in
  `.wapor_req_retry()` (`R/api_client.R`) — exponential backoff capped at 30s,
  honors a numeric `Retry-After` header, treats HTTP 429/5xx as transient.
  Use it (or the same pattern) for any new API call site instead of a bare
  `httr2::req_retry(max_tries = 3, backoff = ~ 2)`.
- **Disk URL cache**: keyed by `.wapor_url_hash()` (`R/api_client.R`), which
  must be a real hash (`digest::digest(x, "sha256")`) — a byte-sum/length
  checksum previously used here can collide for different queries whose
  request strings are character permutations of each other. Fixed 2026-09-03,
  see `issues-log.md` ISS-20260903-001.
- **Seasonal download reconciliation**: `download_seasonal_rasters()` tracks
  every plan row that could not be downloaded (no URLs for a code group, no
  URL match for a specific period, or a raster stack that failed to load
  after retries) and returns it as `missing_periods`, also exposed via
  `attr(wapor_ts_result, "missing_periods")`. Any code path that silently
  `next`s past a download failure without adding to this list reintroduces
  silent under-coverage — treat that as a regression.

## Recurring Pitfalls

- A `for (d in days_seq)` loop over a `Date` vector strips the `Date` class in
  base R; `plan_wapor_time_slices.R` re-coerces `d <- as.Date(d, ...)` inside
  the loop as a deliberate workaround — don't "simplify" this away.
- `sf::st_bbox()` on a plain unnamed numeric vector does not work — it needs a
  named vector (`c(xmin=, ymin=, xmax=, ymax=)`) and, for CRS-aware use with
  `terra::vect()`/`wapor_safe_project()`, an explicit `crs =` argument.
- The "optimum raster selection" guarantee (coarsest-sufficient temporal
  resolution, no gaps/overlaps) only applies to the `seasonal = TRUE` code
  path via `wapor_plan_time_slices()`. `wapor_monitoring.R`'s
  `wapor_save_raster_blobs()` fetches raw per-variable URLs directly and does
  not go through the planner.

- **No `Collate:` field in `DESCRIPTION`**: R loads `R/*.R` alphabetically.
  Two same-named top-level functions defined in different files is *not*
  file-scoped in R (unlike a comment claiming "scoped to this file") — the
  alphabetically-last file's definition silently wins for the whole package.
  Found 2026-09-16: `%||%` was defined twice with different semantics
  (`R/utils.R` vs `R/wapor_metadata_cache.R`); the stricter one had been
  silently governing ~40 call sites. Before "deduplicating" any
  same-named helper across files, diff the implementations for real
  semantic differences first, then verify the surviving one against the
  full test suite — don't assume the shorter/simpler version is safe to
  keep. See `issues-log.md` ISS-20260916-002.
- **The task tracker (`task-status.md`/`agents-board.json`/`IMPROVEMENT_PLAN.md`)
  lags actual code state** — found 2026-09-17: 7 of ~20 "pending" tasks were
  already substantially or fully implemented (2.2, 3.1, 1.6, 3.4, 5.1, 5.2,
  6.1, 6.2 — see `issues-log.md` ISS-20260917-002). Before starting any task
  from this tracker, grep the codebase for its named deliverable
  (function/file names from the task's own spec) first — don't trust
  "pending" status at face value.
- **PowerShell's `Set-Content -Encoding utf8` always writes a UTF-8 BOM**,
  which Python's `json.loads`/plain `utf-8` decoding rejects outright, and
  which `python -m json.tool` also chokes on by default. Any Python tooling
  that reads a file written by `board_claim.ps1` (or any PowerShell
  `-Encoding utf8` write) must decode with `utf-8-sig`, and any ad hoc
  `python -m json.tool` check on it needs `encoding='utf-8-sig'` too. Found
  2026-09-17 when this silently broke the dashboard on every board update
  since the tool was created — see `issues-log.md` ISS-20260917-001.

## Stable Project Constraints

- Agent-tooling wiring: `agent-workflow/` (this folder) is the single
  authoritative source of project state for all models. Model-specific
  folders (`.claude/`, `.agent/`, `.gemini/`, `.github/agents/`, generic
  `AGENTS.md`/`GEMINI.md`/`.rules`/etc.) are thin adapters that point here —
  they must not accumulate independent project memory. See
  `docs/superpowers/specs/2026-05-11-agent-workflow-design.md`.
- `inst/agent_skills/RWAPOR_AGENT_SKILLS.md` is the reference for WaPOR
  package usage/behavior when an agent is calling the R API, not for
  dev-tooling workflow.
