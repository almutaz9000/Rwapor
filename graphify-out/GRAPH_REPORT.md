# Graph Report - .  (2026-05-14)

## Corpus Check
- 110 files · ~141,941 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 400 nodes · 497 edges · 46 communities (31 shown, 15 thin omitted)
- Extraction: 80% EXTRACTED · 20% INFERRED · 0% AMBIGUOUS · INFERRED: 99 edges (avg confidence: 0.87)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Seasonal Analysis Debug Scripts|Seasonal Analysis Debug Scripts]]
- [[_COMMUNITY_WaPOR Analysis & Monitoring Core|WaPOR Analysis & Monitoring Core]]
- [[_COMMUNITY_Time Slice & Unit Conversion|Time Slice & Unit Conversion]]
- [[_COMMUNITY_Crop Parameters & Aggregation|Crop Parameters & Aggregation]]
- [[_COMMUNITY_Shiny Analysis UI Modules|Shiny Analysis UI Modules]]
- [[_COMMUNITY_Batch Season Analysis Pipeline|Batch Season Analysis Pipeline]]
- [[_COMMUNITY_Data Catalog & Download|Data Catalog & Download]]
- [[_COMMUNITY_DuckDB Monitoring Schema|DuckDB Monitoring Schema]]
- [[_COMMUNITY_Seasonal AETI Analysis|Seasonal AETI Analysis]]
- [[_COMMUNITY_Archived Monitoring Scripts|Archived Monitoring Scripts]]
- [[_COMMUNITY_Schema & Module Refactor Plans|Schema & Module Refactor Plans]]
- [[_COMMUNITY_Dashboard Config Validation|Dashboard Config Validation]]
- [[_COMMUNITY_Agent Session State|Agent Session State]]
- [[_COMMUNITY_WaPOR API Metadata Cache|WaPOR API Metadata Cache]]
- [[_COMMUNITY_Agent Workflow Scripts|Agent Workflow Scripts]]
- [[_COMMUNITY_Agent Workflow Design|Agent Workflow Design]]
- [[_COMMUNITY_Dashboard Map UI|Dashboard Map UI]]
- [[_COMMUNITY_Debug & Profiling Tools|Debug & Profiling Tools]]
- [[_COMMUNITY_Favorites Management|Favorites Management]]
- [[_COMMUNITY_GDALPROJ Configuration|GDAL/PROJ Configuration]]
- [[_COMMUNITY_Visualization Module|Visualization Module]]
- [[_COMMUNITY_Raster Blob & Zonal Stats|Raster Blob & Zonal Stats]]
- [[_COMMUNITY_Project Entry Points|Project Entry Points]]
- [[_COMMUNITY_Monitoring Class Masking|Monitoring Class Masking]]
- [[_COMMUNITY_API URL Generation|API URL Generation]]
- [[_COMMUNITY_FAO Crop Data Fetch|FAO Crop Data Fetch]]
- [[_COMMUNITY_Season Profile Verification|Season Profile Verification]]
- [[_COMMUNITY_Archived Debug R Paths|Archived Debug R Paths]]
- [[_COMMUNITY_Archived Debug R Env|Archived Debug R Env]]
- [[_COMMUNITY_Archived Empty Script|Archived Empty Script]]
- [[_COMMUNITY_Archived Terra Classify|Archived Terra Classify]]
- [[_COMMUNITY_Archived Terra TempDir|Archived Terra TempDir]]
- [[_COMMUNITY_Archived Terra Unique|Archived Terra Unique]]
- [[_COMMUNITY_WaPOR L3-AETI-D Variable|WaPOR L3-AETI-D Variable]]
- [[_COMMUNITY_Agent Skills Reference|Agent Skills Reference]]
- [[_COMMUNITY_Geometry Comparison Util|Geometry Comparison Util]]
- [[_COMMUNITY_Env Diagnostics Script|Env Diagnostics Script]]
- [[_COMMUNITY_Mock Raster Generator|Mock Raster Generator]]
- [[_COMMUNITY_Raster Alignment Check|Raster Alignment Check]]
- [[_COMMUNITY_Manual Load Test|Manual Load Test]]

## God Nodes (most connected - your core abstractions)
1. `Core Analysis Functions Tests` - 27 edges
2. `Rwapor Agent Skills Reference` - 19 edges
3. `wapor_map` - 18 edges
4. `wapor_ts` - 17 edges
5. `Rwapor R Package` - 14 edges
6. `Standalone Monitoring Module Test Script (Archived)` - 12 edges
7. `Shiny Analysis Module (mod_analysis.R)` - 12 edges
8. `Core WaPOR Function Tests` - 12 edges
9. `Rwapor Shiny Dashboard App Entry Point` - 11 edges
10. `inst/shiny/mod_analysis.R` - 11 edges

## Surprising Connections (you probably didn't know these)
- `NEWS.md Changelog` --references--> `wapor_validate_analysis_config()`  [EXTRACTED]
  NEWS.md → tests/testthat/test-dashboard-validation.R
- `ISS-20260513-013: Silent Source Errors and Async State Leak (Resolved)` --references--> `inst/shiny/mod_analysis.R`  [EXTRACTED]
  agent-workflow/issues-log.md → tests/testthat/test-analysis-shiny.R
- `ISS-20260512-009: beneficial_fraction Missing agg_t` --references--> `Analysis Shiny Helpers Tests`  [EXTRACTED]
  agent-workflow/issues-log.md → tests/testthat/test-analysis-shiny.R
- `NEWS.md Changelog` --references--> `wapor_harmonize_raster()`  [EXTRACTED]
  NEWS.md → tests/testthat/test-analysis.R
- `NEWS.md Changelog` --references--> `wapor_run_seasonal_analysis()`  [EXTRACTED]
  NEWS.md → tests/testthat/test-analysis-shiny.R

## Hyperedges (group relationships)
- **Agent Workflow Lifecycle Scripts** — agent_preflight_script, agent_digest_script, agent_closeout_script [EXTRACTED 1.00]
- **Agent Workflow Required Documents** — workflow_session_brief, workflow_task_status, workflow_issues_log, workflow_change_log, workflow_project_memory, workflow_start_here [EXTRACTED 1.00]
- **DuckDB Monitoring Database Schema** — duckdb_farm_timeseries_table, duckdb_farm_rasters_table, duckdb_farm_polygons_table, duckdb_monitoring_log_table [EXTRACTED 1.00]
- **Rwapor Shiny Dashboard Module Set** — shiny_app, mod_download, mod_analysis, mod_visualisation, mod_timeseries, mod_monitoring, mod_aoi, utils_shiny [EXTRACTED 1.00]
- **Analysis Module UI Component Set** — mod_analysis, mod_analysis_ui_sidebar, mod_analysis_ui_body [EXTRACTED 1.00]
- **Archived Monitoring Test Scripts (Savola)** — archived_repro_error, archived_test_monitoring, archived_test_monitoring_run, archived_run_savola_monitoring, archived_test_parallel_monitoring [INFERRED 0.95]
- **WaPOR Variable Metadata JSON Files** — wapor_metadata_l1_json, wapor_metadata_l2_json, wapor_metadata_l3_json [EXTRACTED 1.00]
- **Rwapor Favorites API Functions** — rwapor_wapor_get_favorites, rwapor_wapor_is_favorite, rwapor_wapor_add_favorite, rwapor_wapor_remove_favorite [INFERRED 0.95]
- **Shiny Module Layer (Download, Monitoring, Timeseries, Visualisation)** — mod_download_mod_download_ui, mod_download_mod_download_server, mod_monitoring_mod_monitoring_ui, mod_monitoring_mod_monitoring_server, mod_timeseries_mod_timeseries_ui, mod_timeseries_mod_timeseries_server, mod_visualisation_mod_visualisation_ui [EXTRACTED 1.00]
- **Analysis Pipeline Stack (Pipeline, Engine, Indicators, Anomaly, Comparison, Validation)** — analysis_pipeline_wapor_analysis_pipeline, analysis_engine_wapor_run_seasonal_analysis, analysis_indicators_wapor_masked_sum, analysis_indicators_wapor_calc_seasonal_aeti, analysis_anomaly_wapor_detect_aeti_anomalies, analysis_comparison_wapor_compare_seasons, analysis_validation_wapor_validate_analysis_config [INFERRED 0.95]
- **Shared Shiny Utilities (utils_shiny, monitoring_helpers)** — utils_shiny_null_coalesce, utils_shiny_is_l3_code, utils_shiny_extract_bbox_from_feature, utils_shiny_build_polygon_file, utils_shiny_get_shinyfiles_roots, utils_shiny_draw_tools, monitoring_helpers_enhanced_zonal_stats [INFERRED 0.95]
- **Interval & Time Slice Helpers** — interval_helpers_subtract_interval, interval_helpers_compute_overlap, interval_helpers_is_fully_within, plan_wapor_time_slices_wapor_plan_time_slices [INFERRED 0.95]
- **Savola Project End-to-End Workflow** — savola_unified_pipeline, savola_wapor_vector_to_season_rasters, analysis_pipeline_wapor_analysis_pipeline, analysis_engine_wapor_run_seasonal_analysis, crop_defaults_fao_crop_defaults [EXTRACTED 1.00]
- **Seasonal Download and Aggregation Pipeline** — seasonal_download_download_seasonal_rasters, utils_get_seasonal_aggregation_rule, utils_get_seasonal_multiplier_values, utils_get_seasonal_output_units, wapor_map_wapor_map, wapor_ts_wapor_ts [INFERRED 0.90]
- **Unit Conversion Subsystem** — unit_convertor_wapor_convert_units, unit_convertor_wapor_convert_raster, unit_convertor_wapor_convert_temperature, unit_convertor_is_temperature_variable, utils_calculate_conversion_factor, utils_extract_temporal_unit, utils_resolve_output_unit_conversion [INFERRED 0.90]
- **Region Parsing and Spatial Cropping Subsystem** — utils_wapor_parse_region, utils_wapor_crop_to_region, utils_wapor_safe_project, utils_wapor_guess_region, utils_wapor_l3_extent, utils_load_l3_extent_cache, utils_save_l3_extent_cache, utils_get_l3_cache_path [INFERRED 0.90]
- **Farm Monitoring DuckDB Subsystem** — wapor_monitoring_wapor_init_monitoring_db, wapor_monitoring_wapor_run_monitoring, wapor_monitoring_wapor_save_raster_blobs, wapor_monitoring_package_save_global_raster_blob_to_db, wapor_monitoring_wapor_raster_from_blob, wapor_monitoring_wapor_enhanced_zonal_stats, wapor_monitoring_wapor_recalculate_stats_from_rasters, wapor_monitoring_wapor_generate_seasonal_raster, wapor_monitoring_wapor_apply_seasonal_mask_recalc, wapor_monitoring_duckdb_schema [EXTRACTED 0.95]
- **WaPOR Metadata Cache Subsystem** — wapor_metadata_cache_wapor_fetch_metadata, wapor_metadata_cache_wapor_update_metadata, wapor_metadata_cache_get_metadata_path, wapor_metadata_cache_parse_metadata_items, wapor_metadata_cache_fetch_all_pages, wapor_metadata_cache_extract_item_metadata, wapor_metadata_cache_json_files, wapor_metadata_cache_fao_gismgr_api [INFERRED 0.90]
- **Debug and Reproducibility Scripts** — scripts_debug_check_env_windows, scripts_debug_mock_wapor_stacks, scripts_debug_profile_seasonal_analysis, scripts_debug_repro_alignment_check, scripts_debug_repro_api_failure [INFERRED 0.85]
- **Manual Test Scripts** — tests_manual_inspect_monitoring_db, tests_manual_migrate_monitoring_schema, tests_manual_reload_and_run, tests_manual_test_analysis_utils, tests_manual_test_enhanced_plot, tests_manual_test_load [INFERRED 0.85]
- **WaPOR Favorites Local Storage Subsystem** — rwapor_favorites_get_favorites_path, rwapor_favorites_wapor_get_favorites, rwapor_favorites_wapor_add_favorite, rwapor_favorites_wapor_remove_favorite, rwapor_favorites_wapor_is_favorite, rwapor_favorites_favorites_json_store [INFERRED 0.90]
- **Manual Monitoring Test Suite** — test_minimal_duckdb_script, test_monitoring_script, test_monitoring_helpers_script, test_monitoring_module_script, test_monitoring_module_load_script [INFERRED 0.95]
- **Manual Shiny and Visualization Test Suite** — test_shiny_script, test_visualization_script, test_viz_fixes_script, test_viz_module_script [INFERRED 0.95]
- **DuckDB Monitoring Schema Tables** — db_table_farm_timeseries, db_table_farm_rasters, db_table_monitoring_log, db_table_farm_metadata [EXTRACTED 1.00]
- **Monitoring Helper Function Set** — fn_wapor_enhanced_zonal_stats, fn_wapor_raster_from_blob, fn_wapor_save_raster_to_db, fn_wapor_get_farms_extent, fn_wapor_update_farm_metadata, fn_wapor_plot_raster_timeseries, fn_wapor_recalculate_stats_from_rasters [EXTRACTED 1.00]
- **Seasonal Analysis Core Functions** — fn_wapor_run_seasonal_analysis, fn_wapor_export_analysis_outputs, fn_wapor_normalize_analysis_indicators, fn_wapor_parse_batch_periods, fn_wapor_generate_shiny_script, fn_wapor_detect_folder_seasons [INFERRED 0.95]
- **Crop Water Productivity Analysis Functions** — fn_wapor_build_kc, fn_wapor_build_kc_by_class, fn_wapor_calc_peff_usda, fn_wapor_calc_cwp, fn_wapor_calc_bwp, fn_wapor_calc_seasonal_etc, fn_wapor_calc_adequacy_etc, fn_wapor_calc_p95_aeti, fn_wapor_calc_beneficial_fraction, fn_wapor_calc_green_water, fn_wapor_calc_blue_water, fn_wapor_calc_yield_npp [EXTRACTED 1.00]
- **Temporal Resolution Planning Functions** — fn_wapor_plan_time_slices, fn_wapor_temporal_codes, fn_resolve_output_unit_conversion, fn_get_seasonal_aggregation_rule, fn_get_seasonal_multiplier_values, fn_get_seasonal_output_units, fn_download_seasonal_rasters [EXTRACTED 1.00]
- **Formal testthat Test Suite** — test_analysis_shiny_r, test_analysis_r, test_dashboard_validation_r, test_gdal_config_r, test_multi_season_r, test_plan_wapor_time_slices_r, test_wapor_r, test_wapor_metadata_cache_r [EXTRACTED 1.00]
- **Agent Entry Point Documents** — agents_md, claude_md, agent_workflow_start_here [EXTRACTED 1.00]
- **Agent Workflow Canonical File Set** — start_here_workflow, session_brief_active_focus, task_status_active, agent_workflow_layer, project_memory_confirmed_patterns [EXTRACTED 1.00]
- **Agent Workflow Templates** — template_issue_entry, template_memory_entry, template_session_brief, template_task_entry [EXTRACTED 1.00]
- **Shiny Analysis Module Files** — mod_analysis_r, shiny_mod_analysis_ui_body, r_analysis_utils, r_analysis_engine, r_analysis_validation [EXTRACTED 1.00]
- **Open Issues Related to Shiny Analysis** — issues_iss_20260512_010, issues_iss_20260511_007, issues_iss_20260511_008, issues_iss_20260512_009, issues_iss_20260511_002, issues_iss_20260511_004, issues_iss_20260511_005 [INFERRED 0.95]
- **WaPOR Spatial Data Levels** — agent_skills_wapor_l1_data, agent_skills_wapor_l2_data, agent_skills_wapor_l3_data [EXTRACTED 1.00]
- **Package Improvement Implementation Plans (P1-P4)** — improvement_p1_schema_versioning, improvement_p2_shiny_decomposition, improvement_p3_external_metadata, improvement_p4_shiny_batch_impl [EXTRACTED 1.00]
- **Visualization Tab Modes** — viz_features_single_raster_mode, viz_features_dual_raster_mode, viz_features_conditional_query_mode [EXTRACTED 1.00]
- **Debugging Helper Scripts** — debugging_check_env_script, debugging_repro_api_script, debugging_repro_alignment_script, debugging_mock_stacks_script, debugging_profile_script [EXTRACTED 1.00]
- **Rwapor Dashboard UI Components** — dashboard_screenshot_sidebar_controls, dashboard_screenshot_leaflet_map, dashboard_screenshot_navigation_tabs [EXTRACTED 0.95]

## Communities (46 total, 15 thin omitted)

### Community 0 - "Seasonal Analysis Debug Scripts"
Cohesion: 0.09
Nodes (43): profile_seasonal_analysis.R (Profiling Scaffold), repro_api_failure.R (API Failure Reproducer), download_seasonal_rasters, inspect_monitoring_db.R (Manual DB Inspector), migrate_monitoring_schema.R (DB Migration Script), reload_and_run.R (Dev Reload Script), test_analysis_utils.R (Manual Analysis Utils Test), test_enhanced_plot.R (Manual Plot Test) (+35 more)

### Community 1 - "WaPOR Analysis & Monitoring Core"
Cohesion: 0.07
Nodes (36): DuckDB-Backed Farm Monitoring, ETLook Surface Energy Balance Model, FAO-56 Crop Parameters (Kc, HI, MC, fc, AOT), Rwapor Agent Skills Reference, wapor_analysis_pipeline() Function, wapor_capabilities() Planned Function, wapor_harmonize_raster() Function, WaPOR Level 1 Data (300m, All Africa) (+28 more)

### Community 2 - "Time Slice & Unit Conversion"
Cohesion: 0.07
Nodes (18): Concept: RWAPOR_RUN_LIVE_TESTS Env Guard, Concept: Time Slice Planning A/M/D/E Hierarchy, Concept: wapor_* Prefix Convention (Breaking Change 0.9.7), Concept: WaPOR URL Filename Date Format, run_wapor(), skip_if_no_live_api(), wapor_generate_urls(), wapor_harmonize_raster() (+10 more)

### Community 3 - "Crop Parameters & Aggregation"
Cohesion: 0.09
Nodes (8): FAO_CROP_DEFAULTS Dataset, wapor_calc_beneficial_fraction(), wapor_calc_blue_water(), wapor_calc_green_water(), wapor_calc_peff_usda(), wapor_masked_sum(), wapor_run_seasonal_analysis(), Core Analysis Functions Tests

### Community 4 - "Shiny Analysis UI Modules"
Cohesion: 0.11
Nodes (27): WaPOR v3 Metadata Fetch Script, Shiny Analysis Module (mod_analysis.R), Shiny Analysis Module UI Body, Shiny Analysis Module UI Sidebar, Shiny AOI (Area of Interest) Module, Shiny Download Module, Shiny Monitoring Module, Shiny Timeseries Module (+19 more)

### Community 5 - "Batch Season Analysis Pipeline"
Cohesion: 0.11
Nodes (23): Shiny Analysis Module Fixes 2026-05-12, Concept: Batch/Multi-Season Named List Periods, wapor_export_analysis_outputs(), P4: Shiny Batch Analysis Implementation Plan, ISS-20260511-002: Batch-Mode Shiny Session Disconnect, ISS-20260511-004: Analysis Folder Scan Targets Output Folder, ISS-20260511-005: Detect from Folder Session Disconnect, ISS-20260511-006: AOI Upload Complexity Resolved (+15 more)

### Community 6 - "Data Catalog & Download"
Cohesion: 0.1
Nodes (21): WAPOR3_VARS named list, Favorites Management (wapor_get/add/remove_favorite), L3 Region Auto-Detection (wapor_guess_region), mod_download_server, mod_download_ui, Multi-Season JSON Save/Load, wapor_map (called from mod_download), Monitoring Variable Constants (.MON_DEFAULT_VARS etc) (+13 more)

### Community 7 - "DuckDB Monitoring Schema"
Cohesion: 0.17
Nodes (18): Concept: Use DBI::dbExecute not duckdb::dbExecute, DuckDB Table: farm_metadata, DuckDB Table: farm_rasters, DuckDB Table: farm_timeseries, DuckDB Table: monitoring_log, mod_monitoring_ui(), wapor_enhanced_zonal_stats(), wapor_get_farms_extent() (+10 more)

### Community 8 - "Seasonal AETI Analysis"
Cohesion: 0.14
Nodes (11): wapor_detect_aeti_anomalies(), wapor_run_seasonal_analysis(), wapor_calc_seasonal_aeti(), wapor_masked_sum(), wapor_analysis_pipeline(), wapor_validate_analysis_config(), wapor_load_crop_mask(), FAO_CROP_DEFAULTS dataset (+3 more)

### Community 9 - "Archived Monitoring Scripts"
Cohesion: 0.17
Nodes (18): L3-AETI-D Error Reproduction Script (Archived), Savola Monitoring Pipeline Runner (Archived), Monitoring Optimization Test Script (Archived), Standalone Monitoring Module Test Script (Archived), Parallel Monitoring Test Script (Archived), Wrapper Script Sourcing Parallel Monitoring (Archived), DuckDB farm_polygons Table Schema, DuckDB farm_rasters Table Schema (+10 more)

### Community 10 - "Schema & Module Refactor Plans"
Cohesion: 0.18
Nodes (11): .check_and_update_schema() Internal Function, RWAPOR_SCHEMA_VERSION Constant, P1: Database Schema Versioning & Migrations, mod_monitoring Sub-Modules (Planned), P2: Shiny Module Decomposition, P3: External Metadata Registry, variable_registry.json External File (Planned), wapor_register_variable() Function (Planned) (+3 more)

### Community 11 - "Dashboard Config Validation"
Cohesion: 0.2
Nodes (10): wapor_validate_analysis_config() Function, Dashboard Validation Improvements 2026-05-13, wapor_validate_analysis_config(), ISS-20260513-011: Missing Async Runtime Dependencies (Resolved), ISS-20260513-012: Config Validation Throws on Malformed Dates (Resolved), ISS-20260513-013: Silent Source Errors and Async State Leak (Resolved), R/analysis_validation.R, R/run_dashboard.R (+2 more)

### Community 12 - "Agent Session State"
Cohesion: 0.2
Nodes (10): Project Memory: Patterns to Avoid, Project Memory: Confirmed Patterns, Session Brief: Active Focus 2026-05-13, Agent Closeout Script (agent_closeout.ps1), Agent Preflight Script (agent_preflight.ps1), Agent Workflow: START-HERE Entry Point, Task Status: Active and Pending Tasks, Memory Entry Template (+2 more)

### Community 13 - "WaPOR API Metadata Cache"
Cohesion: 0.25
Nodes (9): .extract_item_metadata, FAO GISMGR API (WaPOR-3 Catalog), .fetch_all_pages, .get_metadata_path, WaPOR Metadata JSON Cache Files (inst/metadata/), .null_chr, .parse_metadata_items, wapor_fetch_metadata (+1 more)

### Community 14 - "Agent Workflow Scripts"
Cohesion: 0.39
Nodes (9): Agent Closeout PowerShell Script, Agent Digest PowerShell Script, Agent Preflight PowerShell Script, Change Log Workflow Document, Issues Log Workflow Document, Project Memory Workflow Document, Session Brief Workflow Document, Agent Workflow Start-Here Document (+1 more)

### Community 15 - "Agent Workflow Design"
Cohesion: 0.29
Nodes (7): agent-workflow/ Coordination Layer, Agent Workflow Initialization 2026-05-11, ISS-20260511-001: Parallel Agent Memory Drift (Resolved), Canonical Agent Workflow Structure, Agent Workflow Design Spec 2026-05-11, Agent Workflow Enforcement Model, Issue Entry Template

### Community 16 - "Dashboard Map UI"
Cohesion: 0.4
Nodes (6): Interactive Leaflet Map, Monitoring Points Spatial Layer, Top Navigation Tabs, Satellite Imagery Basemap, Rwapor Shiny Dashboard, Sidebar Control Panel

### Community 17 - "Debug & Profiling Tools"
Cohesion: 0.33
Nodes (6): Environment Check Script (check_env_windows.R), Rwapor Debugging Checklist, Mock Stack Generator (mock_wapor_stacks.R), Profiling Harness (profile_seasonal_analysis.R), Raster Alignment Harness (repro_alignment_check.R), API Reproduction Harness (repro_api_failure.R)

### Community 18 - "Favorites Management"
Cohesion: 0.67
Nodes (6): Favorites JSON Local Storage (~/.rwapor_favorites.json), get_favorites_path, wapor_add_favorite, wapor_get_favorites, wapor_is_favorite, wapor_remove_favorite

### Community 19 - "GDAL/PROJ Configuration"
Cohesion: 0.4
Nodes (4): Concept: PROJ_LIB/GDAL_DATA Override for Terra, wapor_configure_gdal(), Testthat Setup (PROJ/GDAL Environment Fix), GDAL Configuration Tests

### Community 20 - "Visualization Module"
Cohesion: 0.5
Nodes (5): mod_visualisation_server(), mod_visualisation_ui(), inst/shiny/mod_visualisation.R, Enhanced Visualization Module Test, Visualization Module Fixes Test

### Community 21 - "Raster Blob & Zonal Stats"
Cohesion: 0.5
Nodes (5): wapor_apply_seasonal_mask_recalc, wapor_enhanced_zonal_stats, wapor_generate_seasonal_raster, wapor_raster_from_blob, wapor_recalculate_stats_from_rasters

### Community 22 - "Project Entry Points"
Cohesion: 0.67
Nodes (4): agent-workflow/START-HERE.md, AGENTS.md Agent Entry Point, CLAUDE.md Claude Adapter Notes, Concept: agent-workflow/ as Canonical Memory

### Community 23 - "Monitoring Class Masking"
Cohesion: 0.5
Nodes (3): mod_monitoring_server, wapor_enhanced_zonal_stats, %||% null-coalescing operator

### Community 25 - "FAO Crop Data Fetch"
Cohesion: 1.0
Nodes (3): get_fao_crop_data.R Script, FAO Irrigation Paper No. 56 (Crop Kc Data), fetch_fao_table

## Knowledge Gaps
- **123 isolated node(s):** `Agent Workflow Start-Here Document`, `Debug R Library Paths Script (Archived)`, `Debug R Environment Script (Archived)`, `Empty R Script (Archived)`, `Wrapper Script Sourcing Parallel Monitoring (Archived)` (+118 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `NEWS.md Changelog` connect `Time Slice & Unit Conversion` to `Dashboard Config Validation`, `Crop Parameters & Aggregation`?**
  _High betweenness centrality (0.107) - this node is a cross-community bridge._
- **Why does `wapor_map()` connect `Time Slice & Unit Conversion` to `DuckDB Monitoring Schema`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **Why does `wapor_run_seasonal_analysis()` connect `Crop Parameters & Aggregation` to `Time Slice & Unit Conversion`, `Batch Season Analysis Pipeline`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **Are the 6 inferred relationships involving `wapor_map` (e.g. with `download_seasonal_rasters` and `wapor_convert_temperature`) actually correct?**
  _`wapor_map` has 6 INFERRED edges - model-reasoned connections that need verification._
- **Are the 6 inferred relationships involving `wapor_ts` (e.g. with `download_seasonal_rasters` and `resolve_output_unit_conversion`) actually correct?**
  _`wapor_ts` has 6 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Agent Workflow Start-Here Document`, `Debug R Library Paths Script (Archived)`, `Debug R Environment Script (Archived)` to the rest of the system?**
  _123 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Seasonal Analysis Debug Scripts` be split into smaller, more focused modules?**
  _Cohesion score 0.09 - nodes in this community are weakly interconnected._