# Rwapor branch history and retirement record

Date: 2026-10-09

## Decision

`main` is the canonical integration branch. Release tags, rather than old
development branches, are the permanent record of milestones. The old remote
branches listed below are retired because they are either ancestors of `main`,
or stale divergent snapshots whose intended changes have been superseded by
later reviewed releases. They must not be merged wholesale: doing so would
reintroduce pre-1.0 implementations of scaling, tiled processing, remote I/O,
and zonal statistics.

## Retained operational branches

* `main` — released, integrated package.
* `version-1.0.6` — current maintenance/release line; fast-forward-equivalent
  package content to the current release before the `main` merge commit.
* `gh-pages` — generated package website deployment branch.

This leaves three operational branches, below the ten-branch limit.

## Release milestones

| Tag | Milestone |
| --- | --- |
| `version-0.5`–`version-0.9.9` | Dashboard, API client, seasonal-analysis and monitoring foundations. |
| `v1.0.0` | Public 1.0 release and tiled GeoTIFF execution foundation. |
| `v1.0.1` | Size-aware processing and native-resolution aggregation. |
| `v1.0.2` | Correct monthly green/blue-water aggregation. |
| `v1.0.3`–`v1.0.4` | Plotting, local-analysis units, and polygon visualisation. |
| `v1.0.5` | Correct scale handling, COG datatype safety, disk controls, and ETc alignment. |
| `v1.0.6` | Remote-I/O and zonal-engine performance, download cache, generalized zonal statistics, irrigation indicators, citations, and CI hardening. |

The detailed user-facing release notes remain in `NEWS.md`; the tags above are
the immutable package-development timeline.

## Retired-ref classes

| Class | Disposition | Reason |
| --- | --- | --- |
| `agent-workflow-*`, `ai-*`, `formalize-*`, `feature/shared-*`, `feat/shared-*`, `docs-*`, `workflow-*`, `verify-*`, `jules-*-workflow` | Delete remote ref | Stale workflow/documentation snapshots; their useful coordination changes were replaced by the current workflow. |
| `bolt-*`, `bolt/*`, `jules-bolt-*`, `perf-raster-*`, `optimize-*` | Delete remote ref | Pre-1.0 optimization snapshots diverged across core analysis files. Later released implementations include reviewed, regression-tested versions. |
| `cleanup-*`, `fix/namespace-*`, `remove-get-*`, `add-static-*` | Delete remote ref | Stale namespace/test cleanup series; subsequent releases establish the package namespace and CI state. |
| `claude/mystifying-saha`, `claude/project-expert-agents-skills-uppwkl`, `consolidate-monitoring-*`, `fix-shiny-*`, `harden-shiny-*`, `maintenance-*`, `migrate-*` | Delete remote ref | Old one-off branches superseded by post-1.0 production-hardening releases. |
| `version-0.9.9`, `version-1.0.0`, `version-1.0.4`, `perf/large-raster-1.0.1`, `claude/ecstatic-allen-xdfb2g` | Delete remote ref after confirming tags | Milestones are preserved by `v1.0.0` through `v1.0.6` tags and incorporated release history. |

## Conflict policy applied

No stale branch was merged into `main`. The superior edit is the one in the
newest released, tested implementation: it has current interfaces, regression
tests, and cross-platform CI. A historical branch may be reconsidered only by
cherry-picking a narrowly identified change onto a new branch with a targeted
test and a clean `R CMD check`.

## Follow-up gates

1. Run the full test suite and `devtools::check(document = FALSE)` from a
   clean worktree before the next release.
2. Complete and review the active provenance work separately; it is not part
   of this history cleanup.
3. Validate produced COGs in release checks where GDAL supports it.
4. Replace monitoring raster blobs with file/object-store COG references before
   claiming scalable monitoring for very large rasters.
