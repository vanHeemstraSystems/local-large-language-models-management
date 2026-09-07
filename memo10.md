Memo: Integrating Stably Orca with Local LLMs

Date: 2026-09-07
Status: Proposed
Repository: Local LLMs Management
Subject: Evaluate and integrate Stably Orca as a local multi-agent orchestration layer

⸻

1. Executive Summary

Orca should be evaluated as a multi-agent orchestration layer for our local LLM environment.

Orca is not a replacement for the local inference runtime. Instead, it can sit above our existing coding-agent and model infrastructure and orchestrate multiple CLI-based coding agents, including agents such as OpenCode and Qwen Code.

The proposed architecture is:

                         ORCA
              Multi-Agent Orchestration
                         │
            ┌────────────┼────────────┐
            │            │            │
         OpenCode     Qwen Code    Other CLI
            │            │            │
            └────────────┼────────────┘
                         │
                  OpenAI-compatible API
                         │
                       LiteLLM
                         │
                ┌────────┴────────┐
                │                 │
          mlx_lm.server       Other runtimes
                │
                ▼
          Local Qwen Models
                │
                ▼
          Mac Mini M4 Pro

The key architectural principle is:

Orca should orchestrate agents; it should not replace our model-serving layer.

⸻

2. Why Orca Is Relevant

Our current Local LLM work has focused on making locally hosted models usable from developer tools such as Warp and OpenCode.

We have already encountered compatibility and reliability issues around:

* Qwen coding models
* OpenCode
* mlx_lm.server
* OpenAI-compatible APIs
* tool calls
* streaming responses
* tool-call identifiers
* local inference performance
* timeout behaviour

Orca introduces another useful layer: parallel agent execution.

Instead of asking one coding agent to perform an investigation or implementation, Orca can coordinate multiple agents working independently, potentially using isolated Git worktrees.

This makes Orca particularly relevant for:

* competing implementations
* code investigations
* refactoring experiments
* bug fixing
* architecture experiments
* code reviews
* alternative solution generation
* automated comparison of agent results

⸻

3. Architectural Position

Orca should be considered an orchestration layer, not an inference engine.

Current architecture

Developer
   │
   ▼
Warp / OpenCode
   │
   ▼
LiteLLM
   │
   ▼
mlx_lm.server
   │
   ▼
Qwen

Proposed architecture

Developer
   │
   ▼
Orca
   │
   ├── OpenCode ─────┐
   ├── Qwen Code ───┤
   └── Other CLI ───┤
                    ▼
                 LiteLLM
                    │
                    ▼
              mlx_lm.server
                    │
                    ▼
                 Qwen

This separation is desirable because each component retains a clear responsibility.

Layer	Responsibility
Orca	Agent orchestration
OpenCode / Qwen Code	Coding-agent behaviour
LiteLLM	API/model compatibility and routing
mlx_lm.server	Local model serving
Qwen	Local inference
Git worktrees	Agent isolation

⸻

4. Multi-Agent Local LLM Pattern

The most interesting capability for our environment is parallel execution.

A single engineering task could be distributed to several local agents:

                         Task
                           │
                           ▼
                         Orca
                           │
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
          Agent A       Agent B       Agent C
          Qwen          Qwen          Qwen
             │             │             │
         Worktree A    Worktree B    Worktree C
             │             │             │
             └─────────────┼─────────────┘
                           ▼
                    Compare solutions
                           │
                           ▼
                    Select / merge

For example:

“Find the cause of this timeout and implement the best fix.”

Possible agents could independently:

1. investigate the existing implementation;
2. inspect upstream projects;
3. implement a minimal fix;
4. implement a more robust architectural solution;
5. create tests;
6. benchmark the alternatives.

This is substantially more powerful than simply increasing the context window or asking one local agent to retry.

⸻

5. Git Worktree Isolation

Orca’s use of isolated Git worktrees is particularly valuable.

Each agent can experiment without modifying the primary working tree.

repository/
│
├── main
├── worktree-agent-a
├── worktree-agent-b
└── worktree-agent-c

This provides a natural safety boundary for autonomous local agents.

The preferred workflow is:

Task
  ↓
Create isolated worktrees
  ↓
Run multiple local agents
  ↓
Collect results
  ↓
Evaluate changes
  ↓
Run tests
  ↓
Select preferred implementation
  ↓
Merge

This should become a reusable pattern within Local LLMs Management.

⸻

6. Relationship to OpenCode

Orca should not initially replace OpenCode.

Instead:

Orca
  ↓
OpenCode
  ↓
LiteLLM
  ↓
Local Qwen

OpenCode remains the coding agent while Orca becomes the higher-level coordinator.

This is especially useful because we already have experience configuring OpenCode against local Qwen models.

It also means Orca can be introduced without redesigning the existing inference infrastructure.

⸻

7. Relationship to Qwen Code

Qwen Code is another potential Orca worker.

The architecture could therefore support:

                    Orca
                      │
          ┌───────────┴───────────┐
          │                       │
      OpenCode                Qwen Code
          │                       │
          └───────────┬───────────┘
                      │
                   LiteLLM
                      │
                 Local Qwen

This should be tested rather than assumed.

The objective is to determine whether OpenCode and Qwen Code provide complementary agent behaviour when orchestrated by Orca.

⸻

8. Relationship to LiteLLM

LiteLLM should remain the preferred compatibility/routing layer.

The recommended principle is:

Agents should not need to know how the underlying local model is served.

For example:

Orca
  ↓
OpenCode
  ↓
LiteLLM endpoint
  ↓
mlx_lm.server
  ↓
Qwen

This allows the underlying model to be changed without redesigning the orchestration layer.

Potential future backends include:

* MLX
* llama.cpp
* Ollama
* vLLM
* remote local-LLM servers
* additional Mac or Linux inference nodes

⸻

9. Mac Mini M4 Pro

The Mac Mini M4 Pro remains an important local inference target.

A first implementation should therefore be deliberately simple:

Mac Mini M4 Pro
┌─────────────────────────────────────┐
│                                     │
│  Orca                               │
│    │                                │
│    └── OpenCode / Qwen Code         │
│             │                       │
│          LiteLLM                    │
│             │                       │
│       mlx_lm.server                 │
│             │                       │
│          Qwen model                 │
│                                     │
└─────────────────────────────────────┘

Do not introduce distributed inference prematurely.

First establish reliable local operation.

⸻

10. Resource Considerations

Parallel agents create a fundamentally different resource profile from a single local coding agent.

If three agents simultaneously invoke a large Qwen model:

Agent A ─┐
Agent B ─┼──► Local inference server
Agent C ─┘

the result may be:

* increased memory pressure;
* reduced tokens/sec;
* longer queue times;
* increased latency;
* increased likelihood of timeouts.

Therefore Orca should initially be configured with a small number of concurrent agents.

Recommended experimental sequence:

1 agent
   ↓
2 agents
   ↓
3 agents
   ↓
measure
   ↓
determine practical concurrency

Concurrency should be driven by measurements rather than by the maximum Orca configuration.

⸻

11. Timeout Investigation

Our existing Qwen/OpenCode timeout observations make this especially important.

Introducing Orca could either:

Improve the situation

because independent work is distributed across agents.

Or:

Make it worse

because multiple agents compete for the same local inference resources.

Therefore the integration must include telemetry for:

* request latency;
* time-to-first-token;
* tokens/sec;
* queue time;
* tool-call duration;
* total task duration;
* failed requests;
* aborted streams;
* timeout frequency;
* memory pressure.

⸻

12. Tool-Call Compatibility

Orca itself should not be assumed to solve the existing tool-call compatibility problems between local inference servers and coding agents.

In particular, the known issue around malformed or incomplete OpenAI-compatible tool-call responses remains a lower-level concern.

The architecture should therefore preserve:

Agent
  ↓
OpenAI-compatible API
  ↓
LiteLLM
  ↓
Inference server

Compatibility should be tested at every boundary.

Important test cases:

* normal text completion;
* streaming;
* tool calls;
* multiple tool calls;
* tool-call IDs;
* interrupted streams;
* malformed responses;
* retries;
* long-running tool execution;
* parallel requests.

⸻

13. Security Model

Local execution is an important advantage.

The proposed default should be:

Source code and model inference remain local unless explicitly configured otherwise.

Orca agents should operate inside controlled repositories and Git worktrees.

Potential safeguards:

* restrict agent filesystem access;
* use isolated worktrees;
* require approval before merging;
* keep Git history;
* log agent actions;
* avoid exposing secrets to agents;
* use separate credentials where possible;
* run tests before merging autonomous changes.

⸻

14. Recommended Proof of Concept

Create a small repository specifically for testing Orca with the existing local stack.

Test 1 — Single agent

Orca
 ↓
OpenCode
 ↓
LiteLLM
 ↓
Qwen

Verify:

* startup;
* model selection;
* normal coding task;
* file modifications;
* Git operation;
* tests.

Test 2 — Two agents

Run two independent agents against the same engineering problem.

Measure:

* completion time;
* inference throughput;
* memory usage;
* quality;
* failures.

Test 3 — Competing implementations

Ask multiple agents to solve the same issue independently.

Compare:

* correctness;
* test coverage;
* complexity;
* performance;
* maintainability.

Test 4 — Tool-heavy task

Use a task requiring:

* repository search;
* file changes;
* shell commands;
* tests;
* Git operations.

This will expose tool-call compatibility problems.

Test 5 — Failure recovery

Intentionally introduce:

* timeout;
* interrupted request;
* failed tool call;
* failed test.

Determine how Orca and the underlying agent recover.

⸻

15. Evaluation Criteria

Orca should be evaluated against:

Criterion	Goal
Local execution	Fully supported
OpenCode	Supported
Qwen Code	Supported
LiteLLM	Compatible
mlx_lm.server	Compatible through agent/API layer
Git worktrees	Reliable
Parallel agents	Reliable
Tool calls	Reliable
Streaming	Reliable
Failure recovery	Robust
Resource usage	Acceptable on M4 Pro
Security	Local-first
Observability	Sufficient
Developer experience	Better than single-agent workflow

⸻

16. Potential Open Engineering Integration

Although this memo belongs to Local LLMs Management, Orca has potential relevance to the wider Open Engineering ecosystem.

The architectural pattern could eventually become:

Open Engineering
        │
        ▼
Engineering Assistant
        │
        ▼
Agent Orchestration
        │
        ▼
       Orca
        │
   ┌────┼────┐
   ▼    ▼    ▼
 Agent Agent Agent
   │    │    │
   └────┼────┘
        ▼
 Local LLM infrastructure

This could support autonomous engineering investigations conducted by multiple independent agents.

For example, Code Smell Detective could eventually request:

Investigate this suspected architectural smell using three independent engineering agents and compare their evidence.

Orca would provide a natural execution mechanism for this pattern.

⸻

17. Recommended Architecture Decision

Adopt Orca as an experimental orchestration component.

Do not replace:

* Qwen;
* mlx_lm.server;
* LiteLLM;
* OpenCode;
* existing local model infrastructure.

Instead introduce Orca above the agent layer.

Target architecture

                    Developer
                       │
                       ▼
                     Orca
             Multi-Agent Orchestrator
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
     OpenCode       Qwen Code       Other
        │              │              │
        └──────────────┼──────────────┘
                       ▼
                    LiteLLM
                       │
                Model abstraction
                       │
                       ▼
                mlx_lm.server
                       │
                       ▼
                  Local Qwen
                       │
                       ▼
                Mac Mini M4 Pro

⸻

18. Implementation Principles

1. Local-first
    Keep inference and source code local wherever practical.
2. Layer separation
    Orca orchestrates; agents reason; LiteLLM routes; inference servers execute models.
3. Do not duplicate functionality
    Orca should complement rather than replace OpenCode or LiteLLM.
4. Measure concurrency
    Parallel agents must be benchmarked against available hardware.
5. Preserve Git isolation
    Use worktrees as the default boundary for parallel autonomous work.
6. Test tool calls explicitly
    Local LLM compatibility cannot be inferred from successful text generation.
7. Keep providers interchangeable
    Avoid coupling Orca directly to a single inference runtime.
8. Make failures observable
    Record latency, failures, timeouts and agent outcomes.

⸻

19. References

* Orca repository: https://github.com/stablyai/orca
* Orca documentation / README: https://github.com/stablyai/orca/blob/main/README.md
* OpenCode: https://github.com/anomalyco/opencode
* Qwen Code: https://github.com/QwenLM/qwen-code
* LiteLLM: https://github.com/BerriAI/litellm
* MLX: https://github.com/ml-explore/mlx
* MLX-LM: https://github.com/ml-explore/mlx-lm

⸻

20. Final Recommendation

Proceed with a Proof of Concept.

Orca is a strong candidate for the Local LLM ecosystem because it addresses a problem that our current stack does not directly solve: coordinating multiple coding agents and their isolated engineering work.

The preferred approach is therefore:

                    ORCA
                     │
             Agent orchestration
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
    OpenCode      Qwen Code     Future agents
        │            │
        └────────────┼────────────┘
                     ▼
                  LiteLLM
                     ▼
              Local inference
                     ▼
                  Qwen

The first milestone should be a reliable Orca → OpenCode → LiteLLM → mlx_lm.server → Qwen path on the Mac Mini M4 Pro.

Once that works reliably, parallel-agent experiments should determine whether Orca becomes a permanent part of the Local LLM Management architecture.
