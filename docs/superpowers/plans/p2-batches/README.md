# P2 batch briefs

One brief per implementation run. Order, priorities and the verification gate: `docs/superpowers/plans/2026-09-30-p2-generalized-zonal-features.md`, section 1A.
The next batch starts only after the previous one passed its gate.

| Order | Batch | Brief | Priority | Board tasks |
|---|---|---|---|---|
| 1 | B1 | `B1-classification.md` | P2-1 foundation | ti-10 |
| 2 | B2 | `B2-zonal-and-masks.md` | P2-1 foundation | ti-10, ti-16, ti-12 |
| 3 | B3 | `B3-indicators.md` | P2-2 core value | ti-09, ti-13 |
| 4 | B4 | `B4-crops-and-peff.md` | P2-2 core value | ti-11, p2-peff |
| 5 | B5 | `B5-plots-offline.md` | P2-3 polish | ti-14, ti-15 |
| 6 | R | master plan section 9 | release 1.0.6 | - |

Codex: `powershell -ExecutionPolicy Bypass -File .\agent-workflow\scripts\codex_task.ps1 -Plan docs/superpowers/plans/p2-batches/<brief> -Effort high`
Other models (Antigravity, Gemini, ...): give them the brief file and say "implement this batch only".
