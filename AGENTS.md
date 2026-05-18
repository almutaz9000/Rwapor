# Agent Entry Point

All agents must start with [agent-workflow/START-HERE.md](agent-workflow/START-HERE.md).

Use model-specific folders only for runtime configuration. The canonical project workflow, memory, task state, and issue state live under `agent-workflow/`.

**Model-Specific Guidance**:
- **Jules**: Always check [.jules/bolt.md](.jules/bolt.md) for active tasks and environment-specific requests.
