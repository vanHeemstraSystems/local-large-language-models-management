# STRATEGY

Operating strategy for the local-LLM stack on this 24 GB Mac mini M4 Pro. This document is the short, operator-focused summary of *how* we run and tune the stack safely. Detailed evidence lives in the workspace spec and task notes; the concrete OpenCode + Augment Context Engine context-budget numbers live in the "Context budget policy" section of `README.md`.

## Core principle

**Machine stability outranks maximizing resident model memory or context capacity.**

A local LLM that occasionally kernel-panics the machine is not usable, no matter how much context or how many tokens/second it delivers. Every tuning decision below is subordinate to this principle.

## Strategic objective

The objective of this repository is not merely to run a large language model locally.

The objective is to establish a practical, reproducible, and safe **local software-engineering agent stack** in which:

- the coding agent provides the interaction and agent loop;
- repository context is retrieved deliberately rather than placed wholesale into every prompt;
- the language model performs inference locally on the Mac mini;
- tool calls provide controlled access to the repository and development environment;
- context growth is actively managed;
- machine stability is treated as a hard operational constraint.

The currently proven architecture is:

```
Developer
    |
    v
Warp / terminal environment
    |
    v
OpenCode
    |
    +---- built-in coding tools
    |
    +---- Augment Context Engine MCP
    |         |
    |         +---- repository retrieval
    |
    v
OpenAI-compatible API
    |
    v
MLXServe
    |
    v
Qwen3-Coder-30B-A3B-Instruct-4bit
    |
    v
MLX / Metal
    |
    v
Apple M4 Pro unified memory (24 GB)
```

The architectural separation is intentional:

> Augment provides relevant context; Qwen provides local intelligence; OpenCode provides the agent loop; MLXServe provides local inference.

No component should be asked to perform a responsibility that another layer can perform more efficiently or safely.

## Current maturity

The stack should be described according to demonstrated capability rather than intended capability.

### Proven

The following have been demonstrated end-to-end:

- OpenCode can use the local MLXServe endpoint.
- Qwen3-Coder can receive OpenCode tool definitions.
- The model can request a tool.
- OpenCode can execute the tool.
- The tool result can be returned to the model.
- The model can reason over that result and stop naturally.
- Augment Context Engine can be exposed through MCP.
- Qwen can invoke codebase retrieval when repository context is required.
- Retrieved repository context can be used to produce a grounded answer.
- OpenCode compaction can materially reduce conversation context.
- Context and retrieval costs have been measured under real agent workloads.

This establishes a functioning local retrieval-augmented agent loop.

### Not yet proven

The following must not yet be treated as production-proven:

- sustained edit-producing coding sessions;
- repeated inspect → retrieve → edit → test → repair loops;
- long-running autonomous agent operation;
- long-horizon stability under sustained GPU load;
- safe operation close to the theoretical 16K context limit;
- kernel-panic-free operation over extended workloads.

The next maturity milestone is therefore not a larger model or larger context.

It is a reliable edit-producing loop:

```
inspect
   ↓
retrieve
   ↓
reason
   ↓
edit
   ↓
verify
   ↓
repair if necessary
   ↓
stop
```

This loop should be demonstrated repeatedly before the stack is described as suitable for sustained coding work.

## Configuration authority

Repeated configuration values across documentation and configuration files create drift risk.

The runtime configuration files are authoritative for machine-consumed values.

### Runtime sources of truth

`scripts/mlxserve.sh`

Authoritative for MLXServe runtime defaults, including:

- context size;
- output-token limit;
- KV-cache quantisation;
- prefill chunk;
- resident-memory policy;
- memory-preflight behaviour;
- optional extra MLXServe arguments.

`opencode.json`

Authoritative for OpenCode behaviour, including:

- provider endpoint;
- model context/output limits;
- compaction configuration;
- tool-output limits;
- MCP configuration.

### Documentation

`STRATEGY.md` is authoritative for:

- why those settings exist;
- operational safety principles;
- experimental discipline;
- failure interpretation;
- tuning order;
- maturity criteria.

`README.md` is the operator-facing guide and should summarize the current configuration and measured context budget.

If README or STRATEGY disagrees with a runtime configuration file about the actual configured value, the runtime configuration is authoritative and the documentation must be corrected.

Measured historical values should remain clearly identified as measurements rather than configuration.

## Daily operating mode

Normal coding sessions should optimize for reliability rather than maximum context utilization.

Recommended operating behaviour:

1. Start from the committed, verified baseline.
2. Start MLXServe before beginning the coding-agent session.
3. Confirm that the expected model and runtime settings appear in the MLXServe startup log.
4. Start OpenCode with only the tools/MCP services required for the task.
5. Prefer repository retrieval over manually injecting large files into the conversation.
6. Keep individual retrieval results focused.
7. Allow OpenCode compaction to control conversation growth.
8. Start a fresh session when context becomes dominated by historical tool results or repeated retrieval.
9. Treat GPU-memory-gate rejection as a signal to reduce/restart, not as a challenge to bypass.
10. Stop immediately if the machine exhibits the safety symptoms documented below.

For sustained agent workloads, launching MLXServe with PLD disabled is an available precaution:

```
MLXSERVE_EXTRA_ARGS=--no-pld
```

This is a precaution, not a statement that PLD caused the observed kernel panic. The causal relationship remains undetermined.

## Context is a budget, not a target

`16384` is a protocol/runtime ceiling. It is not a recommended working-set size.

Every OpenCode request consumes context from several sources:

```
system instructions
+ coding-agent instructions
+ tool definitions
+ MCP definitions
+ user conversation
+ assistant conversation
+ retrieved repository context
+ tool results
+ generation allowance
```

Consequently, a nominal 16K model context does not mean that 16K tokens of repository material are available.

The measured initial OpenCode + Augment envelope already consumes a substantial fraction of the available context before repository retrieval occurs.

The operating objective is therefore:

> Maintain enough unused context for the next tool call and its result.

Do not optimize for the largest prompt that MLXServe can accept once. Optimize for enough headroom to complete the next agent-loop transition.

A request that fits but leaves insufficient room for its tool result is not operationally useful.

## Retrieval strategy

Repository retrieval should reduce context consumption, not recreate the entire repository inside the conversation.

Prefer:

```
question
   ↓
targeted retrieval
   ↓
inspect relevant files
   ↓
reason
   ↓
act
```

Avoid:

```
retrieve broadly
   ↓
retrieve again
   ↓
dump large files
   ↓
retain every tool result
   ↓
hit context/GPU limit
```

Retrieval payload limits should therefore be treated as part of the agent architecture, not merely as performance tuning.

However, excessively aggressive truncation is also unsafe operationally. Experiments showed that insufficient context can cause the model to perform additional or inappropriate tool calls, ultimately consuming more context than the larger original retrieval would have consumed.

The goal is **sufficient minimal context**, not minimal context.

## Session lifecycle

A local agent session should not be assumed to have unlimited useful life.

Use three conceptual states:

### Green — continue

- requests complete normally;
- retrieval is focused;
- compaction is effective;
- sufficient context headroom remains;
- no GPU-memory warnings occur.

### Amber — compact or restart

- repeated retrieval results dominate history;
- the session approaches the measured reliable context region;
- compaction has occurred repeatedly;
- the GPU memory gate begins rejecting otherwise reasonable requests;
- responses become dominated by attempts to recover missing context.

Preferred response:

1. preserve important conclusions in repository files or notes;
2. end the current agent session;
3. restart from a clean context;
4. retrieve only what the next task requires.

### Red — stop the workload

- GPU stalls;
- MLXServe hangs;
- severe memory pressure;
- IOGPU/Metal errors;
- abnormal process termination;
- kernel panic or reboot.

Do not immediately reproduce the workload.

Capture evidence first.

## Safety-revised memory baseline

- `--max-resident-mem 18GB` (was `20GB`).
- `--ctx-size 16384`, `--max-tokens 1536`, `--kv-quant 4`, `--prefill-chunk 1024`, `--skip-mem-preflight` — unchanged.
- OpenCode provider limits — unchanged (context 16384 / output 1536).

The 18 GB policy was introduced after the 2026-08-17 IOGPUFamily kernel panic observed during an MLXServe workload. See Root-cause attribution discipline below for the evidence and the deliberately limited conclusions that may be drawn from it.

Reducing the resident-memory cap to 18GB is the least invasive lever that increases headroom on the 24GB envelope while keeping the frozen baseline otherwise intact. Note that `mlx-serve` derives its `[wired] mode=max limit=18186 MB` line independently of the flag, so the wired-limit line looks identical at 18GB and 20GB; the visible change is the registry line (`max_resident_mem=18.0 GB`).

## Layered failure modes and which layer each mitigation addresses

Field experience surfaced *three* distinct failure modes, stacked from softest to hardest:

1. **Hard ctx cap (**`--ctx-size 16384`**)** — request rejected with "Prompt exceeds maximum context length: N requested, 16384 available". Deterministic and recoverable. *Mitigations:* OpenCode compaction/pruning (`compaction`, `tool_output.max_lines`, `tool_output.max_bytes`); retrieval budgets (smaller `codebase-retrieval` payloads); session-restart discipline.
2. **Per-request GPU memory gate** — request rejected with "requires ~XMB GPU memory but only ~YMB available". Depends on live free GPU memory at request time, so warm/fragmented caches can reject prompts that a cold session accepts. *Mitigations:* `--prefill-chunk 1024` (the biggest single lever; already applied); compaction (reduces prompt size); session-restart discipline (clears warm cache state); resident-memory headroom (18GB cap leaves more physical margin).
3. **Driver-level IOGPUFamily panic** — full macOS kernel panic. No OpenCode-side, MLXServe-side, or client-side configuration can *guarantee* protection at this layer. *Mitigations we can apply:* resident-memory headroom (18GB cap); avoiding the specific workload shape that preceded the observed panic (streaming + speculative decoding + accumulating GPU state) is a candidate but *not a confirmed cause*. PLD/speculative decoding is toggleable at launch (`--no-pld`, or `MLXSERVE_EXTRA_ARGS=--no-pld` with the current script) and its state is visible in the startup `[args] ... pld=on|off` line and per-request `pld=enabled|disabled` log lines. Short controlled cycles at the 18GB baseline (PLD-on vs PLD-off, restart between runs) were clean in both series and therefore neither establish nor refute a causal PLD contribution to the driver-level failure mode; attribution stays undetermined (see root-cause attribution discipline). Disabling PLD is an available precaution for sustained agent workloads at the cost of throughput on echo-heavy workloads (code editing, RAG, agentic loops), where PLD is designed to help; the default has not been changed on that basis alone.

Compaction/truncation and retrieval budgets address layer 1 primarily and layer 2 secondarily; resident-memory headroom and session-restart discipline address layer 2 and (as best as we can) layer 3.

## Experimental discipline

A setting becomes part of the baseline only through:

```
hypothesis
    ↓
isolated change
    ↓
controlled measurement
    ↓
observation
    ↓
verification
    ↓
documentation
    ↓
baseline decision
```

A successful request is evidence that a configuration *can* work.

It is not evidence that the configuration is reliably safe.

Similarly, one failed request does not automatically identify its root cause.

Separate:

- configuration;
- observation;
- inference;
- hypothesis;
- conclusion.

This distinction is particularly important for GPU/driver failures.

**One variable at a time.** Every tuning experiment isolates a single flag or setting against an otherwise frozen baseline. Never change `--max-resident-mem` and PLD/speculative decoding in the same experiment. Never mix ctx-size and prefill-chunk changes.

**Stop rule (mandatory).** Abort *immediately* on:

- GPU stalls or non-responsive server;
- severe/urgent macOS memory pressure (`kern.memorystatus_level` dropping into critical range);
- process hangs;
- any abnormal MLXServe log output (OOM, IOGPUCommandBuffer errors, panics, unexplained thread aborts).

On any stop-rule trigger: stop the server, capture the log and any system diagnostics, record the observation verbatim, and *do not* push through. No repeated high-pressure automated loops. Short, controlled requests only during safety validation phases.

**Restart between experimental cycles.** Cumulative GPU/cache state is a confounder for per-request-gate behaviour and (potentially) for the driver-level failure mode. During safety-validation runs, restart the server between cycles so cache state is removed as a variable. During normal daily use, session-restart discipline plays the same role when the warm cache degrades.

## Root-cause attribution discipline

For the 2026-08-17 kernel panic (and any similar future event):

- The workload at the time of the panic was an 8,260-token prompt served with streaming and speculative decoding — a fact from the panic report.
- The exact panic string was `"completeMemory() prepare count underflow" @ IOGPUMemory.cpp:550` in `com.apple.iokit.IOGPUFamily` — a fact from the panic report.
- mlx-serve was the panicked task and generated the GPU workload/state associated with the panic — this is a fact from the panic report.
- The panic itself occurred inside Apple's IOGPUFamily driver (`IOGPUMemory.cpp:550`) — also a fact from the panic report.
- Whether the underlying defect is in MLXServe, MLX, Metal/IOGPUFamily, or an interaction among them is **undetermined**.

Do not write, in any file or note, that MLXServe definitively contains the root-cause bug. Use "the panicked task was mlx-serve" or "the panic occurred during an MLXServe workload" instead.

## Order of operations for future tuning

1. Establish that the current baseline is stable under short controlled cycles (this is the Safety Phase).
2. Only then, investigate whether PLD/speculative decoding contributes materially to instability — one variable at a time, never combined with a resident-memory change.
3. Resume retrieval-payload and context-budget work once the baseline is judged safe under sustained (not just short) workloads.

A few clean short cycles demonstrate basic viability. They are **not** proof of long-horizon safety. Extended use is required before promoting the baseline from "viable" to "safe for sustained agent workloads".

## Phase 4 acceptance criterion

The next engineering phase should prioritize coding capability rather than additional context expansion.

The primary experiment should demonstrate a real repository change using:

```
inspect
  → retrieve
  → reason
  → edit
  → verify
  → stop
```

A Phase 4 trial should:

- begin from a clean server/session state;
- use the committed safety baseline;
- select a small, reversible repository task;
- require Augment Context Engine retrieval;
- require at least one actual file edit;
- require verification of that edit;
- record MLXServe request sizes throughout the loop;
- observe GPU/memory behaviour;
- stop under the existing safety rules.

Success means that the complete coding loop finishes naturally without context overflow, GPU-gate failure, process instability, or machine instability.

Only after repeated successful edit-producing sessions should longer-running or more autonomous workloads be investigated.