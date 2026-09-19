# Memo 10: Local LLM Coding Reliability & Cost Optimization

Objective

Establish a reliable local-LLM coding workflow that allows Open Engineering development to move as much suitable coding work as possible from paid cloud inference to local inference.

The primary objective is cost reduction without sacrificing developer productivity.

The current local environment is:

* Mac mini M4 Pro
* 24 GB RAM
* Qwen3-Coder-30B-A3B-Instruct-4bit
* MLXServe
* OpenAI-compatible local endpoint
* Warp
* OpenCode
* Open Engineering repositories

The immediate problem is that the local LLM can be responsive for ordinary interaction but may time out during agentic coding tasks.

The goal of this memo is therefore not to replace the local model prematurely, but to identify precisely where the failure occurs and make the local coding stack reliable.

⸻

1. Problem Statement

The current architecture is approximately:

Warp
  │
  ▼
OpenCode
  │
  ▼
OpenAI-compatible API
  │
  ▼
MLXServe
  │
  ▼
Qwen3-Coder-30B-A3B-Instruct-4bit
  │
  ▼
Apple Silicon / MLX

For an agentic coding task, the actual interaction is more complex:

LLM
 │
 ├──► inspect files
 │
 ├──► execute command
 │
 ├──► receive result
 │
 ├──► reason
 │
 ├──► modify files
 │
 ├──► run tests
 │
 └──► iterate

A timeout therefore does not necessarily mean that Qwen3 is too slow.

Potential failure domains include:

1. Model inference
2. Context size
3. KV-cache / memory pressure
4. Streaming
5. OpenAI-compatible API behavior
6. Tool-call protocol
7. Tool execution
8. OpenCode
9. Warp
10. Client timeout configuration
11. Agent context amplification
12. Repository size and tool output

The investigation must identify the first failing layer.

⸻

2. Guiding Principle

Do not solve the problem by immediately changing models.

Instead:

Find the first broken layer, fix it, measure the result, and only then move upward through the stack.

This prevents expensive and potentially unnecessary changes to the local LLM environment.

The desired architecture is:

                         ┌─────────────────────┐
                         │ Cloud LLM           │
                         │ complex / fallback  │
                         └──────────┬──────────┘
                                    │
                         ┌──────────▼──────────┐
                         │ Coding Router       │
                         │                     │
                         │ local first         │
                         │ cloud when needed   │
                         └──────────┬──────────┘
                                    │
                         ┌──────────▼──────────┐
                         │ Local LLM           │
                         │ Qwen3-Coder         │
                         └─────────────────────┘

The cloud model should become a fallback and escalation mechanism, rather than the default for every coding task.

⸻

3. Investigation Strategy

The investigation proceeds from the bottom of the stack upward.

                 REAL CODING TASK
                       │
                       ▼
                     Warp
                       │
                       ▼
                    OpenCode
                       │
                       ▼
                Tool-call protocol
                       │
                       ▼
              OpenAI-compatible API
                       │
                       ▼
                   MLXServe
                       │
                       ▼
                  Qwen3-Coder
                       │
                       ▼
                 Apple Silicon

We test each layer independently.

⸻

4. Phase 0 — Freeze the Baseline

Before making changes, record the current configuration.

Record:

* macOS version
* Mac model
* RAM
* MLXServe version
* Qwen model version
* quantization
* context size
* maximum output tokens
* KV quantization
* MLX memory configuration
* OpenCode version
* Warp version
* OpenCode model configuration
* timeout settings
* streaming configuration

Current known baseline:

Hardware:
  Mac mini M4 Pro
  24 GB RAM
Model:
  Qwen3-Coder-30B-A3B-Instruct-4bit
Server:
  MLXServe
  localhost:11234
Current parameters:
  --ctx-size 8192
  --max-tokens 1024
  --kv-quant 4
  --max-resident-mem=20GB
  --skip-mem-preflight

No optimization should be considered successful unless it is compared against this baseline.

⸻

5. Phase 1 — Test Qwen Without an Agent

First bypass Warp, OpenCode and tools.

The test should communicate directly with MLXServe.

Test cases:

Test A — Simple generation

Explain what this repository does.

Test B — Code generation

Write a TypeScript function that validates an email address.

Test C — Code analysis

Analyse this function and identify potential problems.

Test D — Larger context

Provide a realistic source file or collection of files.

Measure:

* time to first token
* total latency
* generated tokens
* tokens/second
* completion success
* memory usage

Interpretation:

Result	Likely area
Simple request fails	MLX/model/server
Simple request works slowly	inference performance
Large context fails	context/memory
All direct tests work	agent/protocol layer
Streaming fails but non-streaming works	streaming/API

⸻

6. Phase 2 — Measure Inference Properly

“Timeout” is not a sufficient diagnostic.

Every experiment should capture:

Request started
       ↓
Time to first token
       ↓
Streaming chunks
       ↓
Final token
       ↓
Request completed

Record at minimum:

TTFT
Total latency
Input tokens
Output tokens
Tokens/sec
Streaming interval
Memory
Success/failure

A result such as:

TTFT:          2.1 sec
Input:         3,200 tokens
Output:          780 tokens
Generation:   20.4 sec
Throughput:    38 tok/s
Total:         22.5 sec

is considerably more useful than:

Request timed out.

⸻

7. Phase 3 — Investigate Context Pressure

Context pressure is already a known area of concern.

A previous failure showed:

Prompt exceeds maximum context length:
1230 requested, 870 available

This demonstrates that context limitations must be treated as a first-class diagnostic dimension.

Test the same task at progressively larger contexts:

1K
2K
4K
6K
8K

Record:

input tokens
TTFT
tokens/sec
memory
completion
failure

The important question is whether performance degrades smoothly or suddenly collapses.

For example:

1K   → 45 tok/s
2K   → 43 tok/s
4K   → 39 tok/s
6K   → 31 tok/s
8K   → timeout

would strongly suggest a context/memory problem rather than a general model problem.

⸻

8. Phase 4 — Test Streaming

Test:

MLXServe → non-streaming
MLXServe → streaming

independently.

A local model may successfully generate a response while a client incorrectly interprets streaming behavior as inactivity.

Measure the time between streamed chunks.

A client timeout can occur even while inference is still progressing if the client expects tokens to arrive within a shorter interval.

⸻

9. Phase 5 — Test Tool Calling

Tool calling is a particularly important investigation area.

Previous investigation identified a potentially significant interoperability problem:

mlx_lm.server emits:
tool_calls[].id: null

where an OpenAI-compatible agent may expect a usable tool-call identifier.

This must be tested directly.

Capture the complete raw interaction:

REQUEST
   ↓
ASSISTANT RESPONSE
   ↓
TOOL CALL
   ↓
TOOL RESULT
   ↓
ASSISTANT RESPONSE

Inspect:

* tool_calls[].id
* tool_call_id
* finish_reason
* streaming tool-call chunks
* JSON validity
* tool-call completion
* tool-result correlation
* whether the next assistant turn is generated

The important question is:

Does the LLM actually complete the tool-call protocol expected by OpenCode?

⸻

10. Phase 6 — Build a Coding Task Ladder

Do not test only complete real-world coding tasks.

Increase complexity incrementally.

Level 0 — Text

What is 2 + 2?

Level 1 — Code generation

Write a Python function.

Level 2 — Code analysis

Analyse this file.

Level 3 — Repository context

Analyse these three files together.

Level 4 — One tool

Read package.json.

Level 5 — Multiple tools

Inspect package.json and then inspect src/.

Level 6 — Modification

Modify this file to implement X.

Level 7 — Verification

Modify → test → analyse failure → fix.

Level 8 — Real Open Engineering task

Implement a real feature in an Open Engineering repository.

The first level that consistently fails identifies the next investigation target.

⸻

11. Phase 7 — Remove Warp

Test:

OpenCode
   │
   ▼
MLXServe

without Warp.

If this works reliably, investigate Warp.

If this fails, continue downward.

⸻

12. Phase 8 — Remove OpenCode

Use a minimal OpenAI-compatible client:

Diagnostic Client
      │
      ▼
   MLXServe
      │
      ▼
   Qwen3-Coder

Test:

1. ordinary completion
2. streaming
3. large context
4. tool calling
5. multiple tool calls
6. file modification
7. multi-step agentic task

This gives us a clean reference implementation against which OpenCode can be compared.

⸻

13. Phase 9 — Observe the Mac During Failure

When a timeout occurs, observe the system rather than immediately restarting it.

Record:

* CPU utilisation
* GPU utilisation
* memory pressure
* process memory
* swap
* MLXServe activity
* network/socket activity

Interpretation:

High compute utilisation

The model is probably still working.

Low GPU + high CPU

Likely preprocessing, tokenisation, context construction or tool processing.

Low CPU + low GPU

Potential waiting/deadlock/protocol problem.

Rapid memory growth

Potential context/KV-cache problem.

Swap activity

Potential memory-pressure problem.

⸻

14. Phase 10 — Create a Diagnostic Harness

Create a dedicated repository or component for repeatable local-LLM diagnostics.

Suggested structure:

local-llm-diagnostics/
│
├── README.md
│
├── scenarios/
│   ├── 00-basic-generation/
│   ├── 01-code-generation/
│   ├── 02-code-analysis/
│   ├── 03-context/
│   ├── 04-streaming/
│   ├── 05-tool-call/
│   ├── 06-tool-loop/
│   ├── 07-file-edit/
│   └── 08-agent-task/
│
├── clients/
│   ├── raw-http/
│   ├── openai-compatible/
│   └── opencode/
│
├── measurements/
│   ├── latency/
│   ├── throughput/
│   ├── memory/
│   └── failures/
│
└── reports/
    └── latest.md

A single diagnostic command should eventually produce:

LOCAL LLM DIAGNOSTIC
====================
Model:
  Qwen3-Coder-30B-A3B-Instruct-4bit
Server:
  MLXServe :11234
Basic generation       PASS
Large context          PASS
Streaming              PASS
Tool calling           FAIL
Tool-call ID           FAIL
Single tool             PASS
Multi-tool loop         FAIL
OpenCode                FAIL
Warp                    NOT TESTED
Likely failure domain:
  Tool-call interoperability

This becomes a regression test suite for the entire local coding stack.

⸻

15. Success Criteria

The local setup should eventually satisfy:

Reliability

A normal coding task should complete without unexplained timeouts.

Observability

Every failure should tell us which layer failed.

Compatibility

Tool calls must correctly survive the complete:

Qwen
→ MLXServe
→ OpenAI-compatible API
→ OpenCode
→ tool
→ OpenCode
→ MLXServe
→ Qwen

cycle.

Productivity

Local inference should be fast enough that developers do not habitually bypass it.

Cost

Local inference should become the default for suitable development tasks.

Escalation

Cloud inference remains available for tasks where local inference is demonstrably inefficient or incapable.

⸻

16. Local-First Coding Strategy

Once reliability is established, introduce a local-first policy.

Local by default

Use the local LLM for:

* code explanation
* small refactoring
* code smells
* documentation
* tests
* straightforward bug fixes
* repetitive transformations
* repository exploration
* small feature implementation
* formatting
* boilerplate
* local experimentation

Escalate to cloud

Use cloud inference when:

* the local model repeatedly fails a task
* the context exceeds practical local limits
* the task requires substantially stronger reasoning
* local inference becomes prohibitively slow
* the local model enters a tool-call loop
* a deadline makes latency more important than inference cost

This creates a cost-aware hybrid architecture rather than treating local and cloud inference as mutually exclusive.

⸻

17. Cost Measurement

The objective should be measured in terms of:

cost per completed coding task

rather than merely:

cost per token

Track:

local inference time
developer waiting time
cloud token cost
task completion rate
retry rate
failure rate

A cheap local request that requires three failed attempts and ten minutes of developer intervention may be less economical than a successful cloud request.

Therefore the real optimization target is:

Minimize total development cost while maintaining acceptable productivity.

⸻

18. Long-Term Architecture

The eventual Open Engineering coding workflow should look like:

                    Developer
                        │
                        ▼
                 Coding Agent
                        │
                        ▼
                 Local-first Router
                   /           \
                  /             \
                 ▼               ▼
          Local Qwen          Cloud LLM
                 │               │
                 └───────┬───────┘
                         ▼
                  Coding Tools
                         │
                         ▼
                    Repository
                         │
                         ▼
                  Tests / Checks

The router should eventually make the decision automatically.

For example:

simple task
    │
    ▼
 local
complex task
    │
    ▼
 local attempt
    │
    ├── success → done
    │
    └── failure/timeout
            │
            ▼
         cloud

This allows local inference to provide the default cost advantage without requiring developers to manually decide which model to use for every task.

⸻

19. Current Hypotheses

The investigation should explicitly test these hypotheses rather than assuming them.

H1 — Context pressure

Large agent prompts are consuming too much context/memory.

H2 — Streaming incompatibility

MLXServe’s streaming behavior is not being interpreted correctly by OpenCode/Warp.

H3 — Tool-call incompatibility

The OpenAI-compatible tool-call implementation is incomplete or incompatible.

The previously observed:

tool_calls[].id: null

makes this particularly important to investigate.

H4 — Client timeout

The local model is still generating, but OpenCode/Warp gives up before generation completes.

H5 — Agent amplification

A simple request is fast, while an agentic request repeatedly increases context size and therefore inference latency.

H6 — Memory pressure

The 24 GB environment is entering memory pressure during larger agentic workloads.

H7 — OpenCode integration

The local API works correctly but OpenCode makes assumptions based on cloud-model behavior.

H8 — Warp integration

OpenCode works correctly but Warp introduces another timeout or protocol limitation.

⸻

20. Recommended Order of Work

Implementation should proceed in this order:

1. Freeze baseline
       ↓
2. Direct MLXServe test
       ↓
3. Measure TTFT / throughput
       ↓
4. Test context scaling
       ↓
5. Test streaming
       ↓
6. Test tool calling
       ↓
7. Test multi-tool loop
       ↓
8. Test OpenCode
       ↓
9. Test Warp
       ↓
10. Build diagnostic harness
       ↓
11. Fix identified incompatibility
       ↓
12. Establish local-first workflow
       ↓
13. Add cloud escalation
       ↓
14. Measure cost/productivity

Do not skip directly to model replacement.

⸻

21. Expected Outcome

The desired result is not simply:

“Make Qwen stop timing out.”

The desired result is a repeatable local coding platform in which:

* local LLM inference is observable
* failures are diagnosable
* tool calling is reliable
* OpenCode can use the local model
* Warp can use the local model
* coding tasks can run autonomously
* cloud inference is used selectively
* local inference absorbs an increasing percentage of coding work
* cost savings can be measured objectively

The ultimate architecture is therefore:

              OPEN ENGINEERING CODING
                       │
                       ▼
                Local-first AI
                       │
             ┌─────────┴─────────┐
             │                   │
             ▼                   ▼
       Local Qwen             Cloud LLM
       zero marginal         paid inference
       inference cost
             │                   │
             └─────────┬─────────┘
                       ▼
                 Coding Agent
                       │
                       ▼
              Tools / Repository
                       │
                       ▼
                  Tests / Git

The strategic goal is:

Make local inference good enough that paying for cloud inference becomes an intentional escalation rather than the default path.
