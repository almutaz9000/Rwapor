# Repository Structure

This document defines the repository layout for production-focused package development and agentic workflows.

## Production-First Paths

These directories are the primary working surface for package functionality and user-facing behavior:

- `R/` package functions and modules
- `inst/` runtime app assets and package-installed resources
- `man/` generated documentation
- `tests/testthat/` formal automated tests
- `vignettes/` user guides and package walkthroughs
- `DESCRIPTION`, `NAMESPACE`, `README.md`, `NEWS.md`

## Workflow and Agent Coordination

- `agent-workflow/` canonical task state, issue logs, session brief, and closeout scripts
- `inst/agent_skills/` package-level operational guidance for agent use

## Development Utilities

- `dev-tools/scripts/` reusable development helpers (debug harnesses, data-refresh scripts)

These scripts are intentionally outside package runtime paths and are not included in package builds.

## Development Archive

- `dev-archive/2026-05-production-cleanup/`

Contains historical development artifacts moved from the repository root, including:

- graph snapshots and generated analysis (`graphify-out/`)
- old archived reports (`archived_reports/`)
- implementation notes and plans (`improvements/`)
- project-specific snapshots (`project-snapshots-Savola/`)
- ad hoc local databases (`*.duckdb`)

## Usage Rules

1. For package changes, start in production-first paths.
2. Use `dev-tools/scripts/` for diagnostics and one-off maintenance commands.
3. Use `dev-archive/` only when historical context is required.
4. If moving files again, update all path references in docs and workflow files in the same change.
