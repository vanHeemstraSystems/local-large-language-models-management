# Memo 9: Evaluate Magnitude as Local LLM Inference Runtime

Project: Local LLMs Management  
Date: 2026-09-07  
Status: Proposed investigation  
Repository: https://github.com/magnitudedev/magnitude  

## 1. Executive Summary

Evaluate Magnitude as a potential inference/runtime layer for our local LLM environment on the Mac Mini M4 Pro.

Magnitude is designed specifically to provide local inference for coding agents. This makes it potentially more suitable for our use case than a general-purpose local LLM server.

Our current architecture has encountered problems with:

* Qwen responsiveness;
* inference timeouts;
* tool-call interoperability;
* OpenCode integration;
* MLX server behaviour;
* OpenAI-compatible API expectations.

Magnitude should therefore be tested as an alternative runtime between our coding-agent clients and local models.

The objective is not yet to replace MLX, llama.cpp, Ollama, or our current setup, but to establish whether Magnitude provides a more reliable agent-oriented runtime.

⸻

## 2. Why Magnitude Is Relevant

Our requirement is not simply:

“Run Qwen locally.”

Our actual requirement is:

“Run a capable coding agent locally, with reliable tool calling, long-running tasks, adequate context, and predictable latency.”

This distinction is important.

A conventional local LLM server primarily exposes model inference.

An agent-oriented runtime additionally needs to deal with:

* long-running inference;
* tool calls;
* context management;
* model loading;
* memory pressure;
* concurrency;
* coding-agent workloads;
* interruption and continuation;
* reliable API semantics.

Magnitude is explicitly positioned around this problem.

It should therefore be evaluated as an agent inference runtime, rather than simply as another LLM frontend.

⸻

## 3. Relationship to Our Existing Architecture

The proposed architecture is:

┌──────────────────────────────┐
│       Coding Interfaces      │
│                              │
│   Warp / OpenCode / Agents   │
└──────────────┬───────────────┘
               │
               │ OpenAI-compatible API
               ▼
┌──────────────────────────────┐
│          Magnitude           │
│                              │
│ Local agent inference layer  │
│ Model management             │
│ Hardware optimisation        │
│ Context / inference control  │
└──────────────┬───────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
   Qwen models       Other models
       │
       ▼
┌──────────────────────────────┐
│       Mac Mini M4 Pro        │
└──────────────────────────────┘

Magnitude should initially be treated as an alternative runtime, not as a replacement for the higher-level agent tooling.

⸻

## 4. Existing Problem We Need to Validate Against

Our previous investigations identified an important interoperability problem involving the MLX LLM server and tool calls.

In particular, we observed that:

mlx_lm.server
        ↓
tool_calls[].id = null
        ↓
OpenAI-compatible client expects a valid tool-call ID
        ↓
OpenCode can abort the operation

This means that raw model quality is not the only variable determining whether a local coding agent works.

The inference runtime and API protocol implementation are equally important.

Magnitude should therefore be tested specifically for tool-call reliability, not merely tokens/second.

⸻

## 5. Primary Investigation Questions

### A. Model compatibility

Determine which models work well with Magnitude on the Mac Mini M4 Pro.

Start with:

* Qwen3 coding-capable models;
* our currently preferred Qwen configuration;
* GGUF variants where appropriate;
* potentially multimodal Qwen models if browser/visual capabilities become relevant.

Do not assume that the model recommended by Magnitude is automatically the best model for our hardware.

⸻

### B. Tool calling

This is one of the most important tests.

Determine whether Magnitude correctly produces and preserves:

tool_calls[].id

and other OpenAI-compatible tool-call fields.

Test:

Agent
  ↓
tool request
  ↓
Magnitude
  ↓
local model
  ↓
tool_calls
  ↓
agent executes tool
  ↓
tool result
  ↓
model continues

The test must include multiple sequential tool calls.

A single successful tool call is insufficient.

⸻

### C. Timeout behaviour

Reproduce the timeout scenarios currently experienced with local Qwen.

Measure:

* time to first token;
* time between streamed tokens;
* tool-call latency;
* total task duration;
* timeout frequency;
* behaviour during long reasoning;
* behaviour when the model is loading;
* behaviour under memory pressure.

Compare Magnitude against the current MLX-based runtime.

⸻

### D. Agent task completion

Benchmark real coding tasks rather than simple prompts.

Example:

Inspect repository
        ↓
Understand existing implementation
        ↓
Identify bug
        ↓
Edit multiple files
        ↓
Run tests
        ↓
Inspect failures
        ↓
Fix implementation
        ↓
Run tests again
        ↓
Report result

This is much more representative of our intended workload.

⸻

## 6. Benchmark Matrix

Create a repeatable benchmark:

Runtime	Model	Tool calls	TTFT	tok/s	Timeout	Task success
MLX	Qwen	✓				
llama.cpp	Qwen	✓				
Magnitude	Qwen	✓				
Ollama	Qwen	✓				

The benchmark should use identical prompts, repositories and tasks wherever possible.

⸻

## 7. Hardware Considerations

The target machine is:

Mac Mini M4 Pro

Magnitude should be evaluated specifically against the available unified memory and Apple Silicon acceleration.

Important measurements:

* model memory footprint;
* context memory;
* KV-cache behaviour;
* CPU utilisation;
* GPU utilisation;
* unified-memory pressure;
* swap usage;
* sustained inference performance;
* model loading time.

A model that achieves a high benchmark tokens/sec but causes excessive memory pressure is not necessarily a good runtime for our environment.

⸻

## 8. Architecture Principle

We should separate:

Agent

Examples:

* OpenCode
* Warp AI
* Claude Code
* other coding agents

from:

Inference runtime

Examples:

* MLX
* llama.cpp
* Ollama
* Magnitude

from:

Model

Examples:

* Qwen3
* Qwen3-Coder
* Qwen VL variants
* other local models.

This gives Local LLMs Management the ability to change one layer without redesigning the others.

⸻

## 9. Recommended Experiment

Install Magnitude alongside the existing runtime.

Do not remove the current setup.

Run:

             Same agent
                 │
        ┌────────┴────────┐
        │                 │
       MLX            Magnitude
        │                 │
       Qwen              Qwen
        │                 │
        └────────┬────────┘
                 │
          Same coding task

Record results automatically.

The first milestone should be:

Can Magnitude execute a realistic OpenCode coding task against our local Qwen model without the timeout/tool-call failures currently encountered?

If yes, continue with performance and quality benchmarking.

⸻

## 10. Success Criteria

Magnitude should only become the preferred runtime if it demonstrates a meaningful improvement in the dimensions that matter to us.

Minimum criteria:

Reliability

* No recurring tool-call ID failures.
* No unexplained agent aborts.
* No recurring inference timeouts.
* Correct streaming behaviour.
* Stable long-running sessions.

Performance

* Acceptable time-to-first-token.
* Competitive sustained tokens/sec.
* Acceptable tool-call latency.
* Predictable performance under context growth.

Agent quality

* Successful multi-step repository modifications.
* Reliable test execution.
* Ability to recover from failed commands.
* Good adherence to repository context and instructions.

Operational simplicity

* Easy local installation.
* Easy model switching.
* Easy restart/recovery.
* Observable runtime behaviour.
* No unnecessary cloud dependency.

⸻

## 11. Potential Role in Local LLMs Management

If the evaluation succeeds, Magnitude could become:

the preferred local inference runtime for coding-agent workloads.

It would sit below the agent layer and above the underlying local model.

This would allow us to maintain a runtime abstraction such as:

Local LLM Runtime
├── MLX
├── llama.cpp
├── Ollama
└── Magnitude

with Magnitude potentially becoming the specialised:

Coding Agent Runtime

while other runtimes remain available for experimentation or different workloads.

⸻

## 12. Important Non-Goals

This investigation should not:

* immediately replace MLX;
* immediately replace Qwen;
* assume Magnitude is faster without measurement;
* assume Magnitude fixes the existing tool-call problem;
* optimise solely for tokens/sec;
* introduce unnecessary dependencies into the architecture;
* abandon the OpenAI-compatible API abstraction.

The goal is evidence-based selection of the best local inference runtime.

⸻

## 13. Next Steps

### Phase 1 — Inspect

Review the Magnitude repository and documentation:

https://github.com/magnitudedev/magnitude

Determine:

* supported platforms;
* Apple Silicon support;
* supported model formats;
* supported Qwen models;
* API compatibility;
* tool-calling implementation;
* context-window handling;
* model management;
* configuration options.

### Phase 2 — Install

Install Magnitude alongside the existing local LLM environment.

Do not modify or remove the working runtime.

### Phase 3 — Integrate

Connect:

OpenCode → Magnitude → Qwen

and verify basic inference.

### Phase 4 — Tool-call test

Run a repository task requiring:

* file inspection;
* file modification;
* shell execution;
* test execution;
* multiple sequential tool calls.

### Phase 5 — Benchmark

Compare Magnitude against the current MLX runtime.

### Phase 6 — Decide

Classify Magnitude as:

ADOPT
TRIAL
KEEP AS ALTERNATIVE
REJECT

based on measured results.

⸻

## 14. Architectural Recommendation

Recommendation: TRIAL MAGNITUDE.

Magnitude is sufficiently aligned with our problem that it deserves a proper technical evaluation.

The strongest reason is not simply that it supports local models.

The stronger reason is that it is designed around the exact workload we care about:

local inference for coding agents.

Our Local LLMs Management architecture should consequently evolve from:

"How do we run Qwen locally?"

toward:

"Which local inference runtime gives our agents
the most reliable and effective engineering capability?"

Magnitude is now a serious candidate for that runtime layer.

⸻

## 15. References

* Magnitude GitHub repository:
    https://github.com/magnitudedev/magnitude
* Magnitude documentation:
    https://docs.magnitude.run/
* Qwen:
    https://github.com/QwenLM/Qwen
* MLX LM:
    https://github.com/ml-explore/mlx-lm
* llama.cpp:
    https://github.com/ggml-org/llama.cpp

⸻

## Decision

Status: INVESTIGATE

Proposed owner: Local LLMs Management

Primary hypothesis:

Magnitude may provide a more reliable and agent-optimised local inference layer for Qwen on Apple Silicon than our current MLX-based setup, particularly for long-running coding tasks and tool calling.

Next concrete action:

Install Magnitude alongside MLX and run the same OpenCode + Qwen engineering benchmark against both runtimes.
