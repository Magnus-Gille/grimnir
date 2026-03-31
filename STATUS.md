# Grimnir System — Status

**Last session:** 2026-03-31 (evening)
**Branch:** main

## Completed This Session

### Benchmark: m4air-mlx-v019 (complete)
- **GLM-4.7-Flash**: 30/30 completed, avg 51s, ~11 tok/s. Quality: 83% (Opus-judged)
- **Qwen3-14B**: 16/30 completed, 14 timed out, avg 250s, ~5.8 tok/s. Quality: 75% when it completes
- **Qwen3.5-35B-A3B** (MLX model): 25/30 completed, 5 timed out, avg 240s, ~9.5 tok/s. Quality TBD (judges incomplete)
- Judge evaluation completed for GLM + Qwen3-14B (both Opus + o4-mini). Qwen3.5 judges not yet run.
- Key finding: Qwen3-14B got ~45% speedup vs previous run (not from MLX — MLX only supports Qwen3.5-35B-A3B currently)
- No-MLX baseline comparison attempted but model too large for Air's 32GB with old engine

### Mac Studio capacity model (written)
- `docs/mac-studio-capacity-model.md` in eval repo (commit 7126ea5)
- Mac Studio = Max (128GB) or Ultra (256GB+). No Pro chip available.
- 128GB viable if small MoE models are "good enough" — that's the open question
- Hybrid architecture: frontier models (Claude) for hard tasks, local models for fast worker tasks

### Grimnir-specific benchmark tasks (designed, not yet wired up)
- 12 tasks in `src/tasks/grimnir.ts` covering real Grimnir workloads:
  briefing gen (2), memory synthesis (2), code triage (2), structured output (2),
  intent routing (2), chat/translation (2)
- Need to wire into task index + add category type before running
- Purpose: answer "are small models good enough for actual Grimnir use cases?"

### Model registry
- Added Qwen3.5-35B-A3B to model registry (commit 7126ea5)

## In Progress

### Grimnir benchmark integration
- `src/tasks/grimnir.ts` exists but not wired into `src/tasks/index.ts` or types
- Need to run against GLM, Qwen3-14B, Qwen3.5-35B-A3B + judge the results
- This data answers the Max 128GB vs Ultra question

## Next Steps

1. **Wire up grimnir tasks** — add to index.ts, update TaskCategory type, run benchmark
2. **Run Qwen3.5 judges** — quality scores still missing for the MLX model
3. Multi-principal Munin Phase 1 implementation (authz matrix is the spec)
4. Fé observation — check tomorrow's briefing for Commercial Pulse quality
5. Skuld Phase 4: meeting prep cards

## Blockers
None
