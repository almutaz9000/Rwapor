# Agent Skill Updates

## 2026-03-31
- Agent: Rwapor-dev
- Instruction update: For L3 overlap detection, always normalize `period` to character before `wapor_guess_region()`.
- Why: Prevents recurring runtime validation failures.
- Example trigger: AOI upload + L3 variable selection in download module.

## 2026-03-31
- Agent: Rwapor-dev
- Instruction update: Avoid silent error swallowing in Shiny reactives; return status+message object.
- Why: `NULL`-only fallbacks hide root cause and mislead users.
- Example trigger: Auto-detection reports "no overlap" when parse/API call actually failed.

## 2026-03-31
- Agent: Rwapor-dev
- Instruction update: For Windows/OneDrive AOI uploads, include explicit local-file diagnostics and sync guidance.
- Why: Frequent false "file does not exist" from cloud placeholders.
- Example trigger: Raster AOI selection from OneDrive Desktop path.
