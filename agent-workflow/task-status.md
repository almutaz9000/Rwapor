# Task Status

_Live execution state. See `templates/task-entry.md` for the entry format._

## Active

- None open as of 2026-09-03.

## Pending Follow-Ups

- **Verify L3 per-region temporal-resolution availability against live
  metadata** instead of the static `WAPOR3_VARS` list, so the seasonal
  planner never selects a resolution (A/M) that a specific L3 mosaic region
  doesn't actually publish. Currently mitigated (not fixed) by the
  reconciliation warning in `download_seasonal_rasters()` — see
  `issues-log.md` ISS-20260903-002. Owner: unassigned.
- **Raster integrity validation**: no checksum/hash validation of downloaded
  rasters exists anywhere in the download path; a truncated-but-parseable
  GeoTIFF from a partial HTTP range read would not necessarily error.
  Lower priority — GDAL/terra usually fail loudly on real corruption.
  Owner: unassigned.
- **Adopt the `agent-workflow/` hub in day-to-day sessions.** The hub
  (this folder) was created 2026-09-03 — all adapter files
  (`CLAUDE.md`, `AGENTS.md`, `.claude/settings.json`,
  `.github/agents/rwapor-dev.agent.md`, `.agent/PROJECT.md`,
  `.agent/skills/project-memory`, `.agent/skills/memory-maintenance`) already
  pointed here before the files existed; confirm in the next few sessions
  that the workflow is actually being followed and entries stay curated.

## Blocked

- None.

## Recently Completed

- **2026-09-03** — WaPOR seasonal download robustness pass: fixed the
  disk-cache hash collision, added retry to the seasonal raster loader, added
  plan-vs-loaded reconciliation with `missing_periods`, upgraded API retry to
  exponential backoff + `Retry-After` awareness. See `change-log.md` and
  `issues-log.md` (ISS-20260903-001).
- **2026-09-03** — Created the `agent-workflow/` hub itself (this folder was
  referenced everywhere but did not exist). See `change-log.md`.
