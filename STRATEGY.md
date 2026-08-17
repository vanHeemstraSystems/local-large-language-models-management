# STRATEGY

Operating strategy for the local-LLM stack on this 24 GB Mac mini M4 Pro.
This document is the short, operator-focused summary of *how* we run and
tune the stack safely. Detailed evidence lives in the workspace spec and
task notes.

## Core principle

**Machine stability outranks maximizing resident model memory or context capacity.**

A local LLM that occasionally kernel-panics the machine is not usable, no
matter how much context or how many tokens/second it delivers. Every
tuning decision below is subordinate to this principle.

## Safety-revised memory baseline

- `--max-resident-mem 18GB` (was `20GB`).
- `--ctx-size 16384`, `--max-tokens 1536`, `--kv-quant 4`,
  `--prefill-chunk 1024`, `--skip-mem-preflight` — unchanged.
- OpenCode provider limits — unchanged (context 16384 / output 1536).

Why 18GB. On 2026-08-17 the machine kernel-panicked during a modest
MLXServe workload (8,260-token prompt, streaming, speculative decoding).
Panic report: `"completeMemory() prepare count underflow"
@IOGPUMemory.cpp:550` in `com.apple.iokit.IOGPUFamily`; `mlx-serve` was
the panicked task. mlx-serve generated the associated GPU workload/state,
but the panic itself occurred inside Apple's IOGPUFamily driver. The
evidence does not establish whether the underlying defect is in
MLXServe, MLX, Metal/IOGPUFamily, or an interaction among them; do not
describe MLXServe as definitively containing the root-cause bug.

Reducing the resident-memory cap to 18GB is the least invasive lever
that increases headroom on the 24GB envelope while keeping the frozen
baseline otherwise intact. Note that `mlx-serve` derives its
`[wired] mode=max limit=18186 MB` line independently of the flag, so
the wired-limit line looks identical at 18GB and 20GB; the visible
change is the registry line (`max_resident_mem=18.0 GB`).

## Layered failure modes and which layer each mitigation addresses

Field experience surfaced *three* distinct failure modes, stacked from
softest to hardest:

1. **Hard ctx cap (`--ctx-size 16384`)** — request rejected with
   "Prompt exceeds maximum context length: N requested, 16384 available".
   Deterministic and recoverable.
   *Mitigations:* OpenCode compaction/pruning (`compaction`,
   `tool_output.max_lines`, `tool_output.max_bytes`); retrieval budgets
   (smaller `codebase-retrieval` payloads); session-restart discipline.

2. **Per-request GPU memory gate** — request rejected with
   "requires ~XMB GPU memory but only ~YMB available". Depends on live
   free GPU memory at request time, so warm/fragmented caches can reject
   prompts that a cold session accepts.
   *Mitigations:* `--prefill-chunk 1024` (the biggest single lever;
   already applied); compaction (reduces prompt size); session-restart
   discipline (clears warm cache state); resident-memory headroom
   (18GB cap leaves more physical margin).

3. **Driver-level IOGPUFamily panic** — full macOS kernel panic. No
   OpenCode-side, MLXServe-side, or client-side configuration can
   *guarantee* protection at this layer.
   *Mitigations we can apply:* resident-memory headroom (18GB cap);
   avoiding the specific workload shape that preceded the observed
   panic (streaming + speculative decoding + accumulating GPU state) is
   a candidate but *not yet a confirmed cause* — a separate task will
   assess PLD/speculative decoding contribution in isolation.

Compaction/truncation and retrieval budgets address layer 1 primarily
and layer 2 secondarily; resident-memory headroom and session-restart
discipline address layer 2 and (as best as we can) layer 3.

## Experimental discipline

**One variable at a time.** Every tuning experiment isolates a single
flag or setting against an otherwise frozen baseline. Never change
`--max-resident-mem` and PLD/speculative decoding in the same
experiment. Never mix ctx-size and prefill-chunk changes.

**Stop rule (mandatory).** Abort *immediately* on:

- GPU stalls or non-responsive server;
- severe/urgent macOS memory pressure
  (`kern.memorystatus_level` dropping into critical range);
- process hangs;
- any abnormal MLXServe log output (OOM, IOGPUCommandBuffer errors,
  panics, unexplained thread aborts).

On any stop-rule trigger: stop the server, capture the log and any
system diagnostics, record the observation verbatim, and *do not*
push through. No repeated high-pressure automated loops. Short,
controlled requests only during safety validation phases.

**Restart between experimental cycles.** Cumulative GPU/cache state is
a confounder for per-request-gate behaviour and (potentially) for the
driver-level failure mode. During safety-validation runs, restart the
server between cycles so cache state is removed as a variable. During
normal daily use, session-restart discipline plays the same role when
the warm cache degrades.

## Root-cause attribution discipline

For the 2026-08-17 kernel panic (and any similar future event):

- mlx-serve was the panicked task and generated the GPU workload/state
  associated with the panic — this is a fact from the panic report.
- The panic itself occurred inside Apple's IOGPUFamily driver
  (`IOGPUMemory.cpp:550`) — also a fact from the panic report.
- Whether the underlying defect is in MLXServe, MLX, Metal/IOGPUFamily,
  or an interaction among them is **undetermined**.

Do not write, in any file or note, that MLXServe definitively contains
the root-cause bug. Use "the panicked task was mlx-serve" or "the panic
occurred during an MLXServe workload" instead.

## Order of operations for future tuning

1. Establish that the current baseline is stable under short controlled
   cycles (this is the Safety Phase).
2. Only then, investigate whether PLD/speculative decoding contributes
   materially to instability — one variable at a time, never combined
   with a resident-memory change.
3. Resume retrieval-payload and context-budget work once the baseline
   is judged safe under sustained (not just short) workloads.

A few clean short cycles demonstrate basic viability. They are **not**
proof of long-horizon safety. Extended use is required before promoting
the baseline from "viable" to "safe for sustained agent workloads".
