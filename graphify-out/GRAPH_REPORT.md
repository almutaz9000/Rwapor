# Graph Report - .  (2026-06-22)

## Corpus Check
- 25 files · ~139,970 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 72 nodes · 36 edges · 37 communities (35 shown, 2 thin omitted)
- Extraction: 83% EXTRACTED · 17% INFERRED · 0% AMBIGUOUS · INFERRED: 6 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Agent Workflow Coordination|Agent Workflow Coordination]]
- [[_COMMUNITY_Shiny Visualization Architecture Mapping|Shiny Visualization Architecture Mapping]]
- [[_COMMUNITY_Dashboard Interface Visualization|Dashboard Interface Visualization]]
- [[_COMMUNITY_Rwapor Package Reference|Rwapor Package Reference]]
- [[_COMMUNITY_Agent and Skill Configuration Mappings|Agent and Skill Configuration Mappings]]
- [[_COMMUNITY_Workflow Migration History|Workflow Migration History]]
- [[_COMMUNITY_Release Notes and Changelog|Release Notes and Changelog]]
- [[_COMMUNITY_Community 12|Community 12]]

## God Nodes (most connected - your core abstractions)
1. `Agent Workflow Start Here` - 7 edges
2. `Raster Visualization UI View` - 5 edges
3. `mod_visualisation_server` - 5 edges
4. `Rwapor Package Readme` - 4 edges
5. `Rwapor Agent Skills Reference` - 2 edges
6. `Overlay Options and Layer Checklist` - 2 edges
7. `Workflow Migration ISS-20260511-001` - 2 edges
8. `wapor-agent` - 2 edges
9. `wapor-r-subagent` - 2 edges
10. `Rwapor Dashboard UI Screenshot` - 2 edges

## Surprising Connections (you probably didn't know these)
- `Agent Workflow Change Log` --semantically_similar_to--> `Rwapor Release Notes`  [INFERRED] [semantically similar]
  agent-workflow/change-log.md → NEWS.md
- `wapor-viz-subagent` --conceptually_related_to--> `mod_visualisation_server`  [INFERRED]
  agent-workflow/agent-migration-audit-2026-06-22.md → docs/SHINY_ARCHITECTURE.md
- `Jules Adapter Guide` --references--> `Agent Workflow Start Here`  [EXTRACTED]
  .jules/bolt.md → agent-workflow/START-HERE.md
- `Agent Entry Point` --references--> `Agent Workflow Start Here`  [EXTRACTED]
  AGENTS.md → agent-workflow/START-HERE.md
- `Debugging Checklist` --conceptually_related_to--> `Rwapor Package Readme`  [INFERRED]
  docs/debugging/DEBUGGING_CHECKLIST.md → README.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Broken Configuration and Agent Flow** — agent_workflow_agent_migration_audit_2026_06_22_wapor_agent, agent_workflow_agent_migration_audit_2026_06_22_wapor_r_subagent, agent_workflow_agent_migration_audit_2026_06_22_agent_project_md, agent_workflow_agent_migration_audit_2026_06_22_rwapor_developer_skill [EXTRACTED 1.00]
- **Shiny UI Components Mapping** — docs_shiny_architecture_color_palette_controls, docs_shiny_architecture_leaflet_map_visualization_pane, docs_shiny_architecture_raster_summary_statistics_table, docs_shiny_architecture_dashboard_screenshot [EXTRACTED 1.00]

## Communities (37 total, 2 thin omitted)

### Community 0 - "Agent Workflow Coordination"
Cohesion: 0.25
Nodes (8): Jules Adapter Guide, Agent Workflow Issues Log, Project Memory, Agent Workflow Session Brief, Agent Workflow Start Here, Agent Workflow Task Status, Agent Entry Point, Agent Workflow Design Spec

### Community 1 - "Shiny Visualization Architecture Mapping"
Cohesion: 0.33
Nodes (7): wapor-viz-subagent, Color Palette Controls Widget, Rwapor Dashboard UI Screenshot, Leaflet Map Visualization Pane, mod_visualisation_server, mod_visualisation_ui, Raster Summary Statistics Table

### Community 2 - "Dashboard Interface Visualization"
Cohesion: 0.29
Nodes (7): Color Palette Controls, Crop Mask Filter Layer Toggle, Rwapor Dashboard UI Screenshot, Leaflet Map Visualization Pane, Overlay Options and Layer Checklist, Raster Visualization UI View, Raster Summary Statistics Table

### Community 3 - "Rwapor Package Reference"
Cohesion: 0.33
Nodes (6): Rwapor Agent Skills Reference, Debugging Checklist, Repository Structure Guide, Rwapor Package Readme, Enhanced Visualization Features, Shiny Batch Analysis and Script Generation Design

### Community 4 - "Agent and Skill Configuration Mappings"
Cohesion: 0.50
Nodes (4): .agent/PROJECT.md, rwapor-developer Skill, wapor-agent, wapor-r-subagent

### Community 5 - "Workflow Migration History"
Cohesion: 0.67
Nodes (3): Centralized Agent State Design, Agent and Skill Configuration Audit, Workflow Migration ISS-20260511-001

## Knowledge Gaps
- **23 isolated node(s):** `Jules Adapter Guide`, `Agent Entry Point`, `Rwapor Release Notes`, `Agent Workflow Change Log`, `Agent Workflow Issues Log` (+18 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Are the 3 inferred relationships involving `Rwapor Package Readme` (e.g. with `Debugging Checklist` and `Repository Structure Guide`) actually correct?**
  _`Rwapor Package Readme` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Jules Adapter Guide`, `Agent Entry Point`, `Rwapor Release Notes` to the rest of the system?**
  _26 weakly-connected nodes found - possible documentation gaps or missing edges._