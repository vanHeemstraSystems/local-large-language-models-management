# Memo 14: Evaluate Herdr for Local LLM Agent Sessions

## Objective

Evaluate whether Herdr can be incorporated into Local LLMs Management as a persistent execution/session layer for coding agents using local LLMs.

The primary motivation is to make long-running local coding-agent tasks resilient to:

* Warp disconnects
* iPad/macOS remote-session interruptions
* SSH disconnects
* terminal closure
* long-running local LLM inference
* agent sessions exceeding the lifetime of an interactive client

Herdr should not become the LLM runtime or model-selection layer. Its proposed responsibility is persistent execution of coding-agent sessions.

⸻

## References

* Herdr: https://herdr.dev/
* Herdr documentation: https://herdr.dev/docs/
* Herdr supported agents: https://herdr.dev/docs/agents/
* Herdr working model: https://herdr.dev/docs/how-to-work/
* Herdr GitHub: https://github.com/herdr-labs/herdr
* Local-agent infrastructure reference: https://huggingface.co/docs/hub/en/agents-local
* Project video:
    https://youtu.be/Shqtk_2Jd3c

⸻

## Concept

Herdr provides a persistent environment in which coding-agent sessions can continue running independently of the user’s interactive terminal or editor connection.

The architectural distinction should be:
```
                 Human Interface
                       │
                 Warp / iPad
                       │
                    Tailscale
                       │
                 ┌─────▼─────┐
                 │   Herdr   │
                 │ persistent│
                 │  sessions │
                 └─────┬─────┘
                       │
              Coding Agent Layer
                       │
              ┌────────┼────────┐
              │        │        │
           OpenCode  Qwen Code  ...
              │        │
              └────────┼────────┘
                       │
                 Model API Layer
                       │
                 ┌─────▼─────┐
                 │ MLXServe  │
                 └─────┬─────┘
                       │
                 Qwen3-Coder
```
Herdr therefore complements rather than replaces:

* MLXServe
* Qwen3-Coder
* OpenCode
* Qwen Code
* Jev
* Warp
* Tailscale

⸻

Proposed Responsibility Boundaries

Herdr

Responsible for:

* persistent agent sessions
* terminal/session lifecycle
* reconnecting to running work
* keeping long-running coding tasks alive
* remote access to running sessions
* isolating the interactive client from agent execution

Coding Agent

Responsible for:

* reading the repository
* planning changes
* editing files
* running tests
* invoking tools
* interacting with the model

Candidate agents include:

* OpenCode
* Qwen Code
* other compatible coding agents

Local LLM Runtime

Responsible for inference.

Current candidate:

MLXServe
    ↓
Qwen3-Coder-30B-A3B-Instruct-4bit

Current local endpoint:

127.0.0.1:11234

Model Router

Future responsibility of Local LLMs Management / Jev.

The router should decide which model/runtime is appropriate for a task.

For example:

Task
 │
 ▼
Jev / Local LLM Manager
 │
 ├── Local Qwen
 ├── another local model
 ├── cloud model
 └── human escalation

Herdr should remain below this decision layer.

⸻

Why Herdr Is Relevant

A significant problem encountered with the current local LLM workflow is that a coding-agent task may take considerably longer than an interactive client session.

The current workflow can effectively be:

Warp
  ↓
OpenCode
  ↓
local Qwen
  ↓
long inference/task
  ↓
connection timeout
  ↓
agent task interrupted

With a persistent session layer:

Warp
  ↓
Herdr
  ↓
OpenCode
  ↓
local Qwen
  ↓
long-running task

Warp can disconnect without necessarily terminating the underlying agent session.

The user can reconnect later and inspect the state of the task.

This is particularly relevant when the local model is slower than a cloud coding model.

⸻

Proposed Local Architecture

The first experiment should use the existing Mac mini rather than introducing a VPS.

┌───────────────────────────────────────────────┐
│ Mac mini M4 Pro                               │
│                                               │
│  ┌───────────────┐                            │
│  │ Herdr         │                            │
│  │               │                            │
│  │ persistent    │                            │
│  │ agent session │                            │
│  └───────┬───────┘                            │
│          │                                    │
│  ┌───────▼───────┐                            │
│  │ OpenCode      │                            │
│  └───────┬───────┘                            │
│          │                                    │
│  ┌───────▼───────┐                            │
│  │ MLXServe      │                            │
│  │ :11234        │                            │
│  └───────┬───────┘                            │
│          │                                    │
│  ┌───────▼───────────────┐                    │
│  │ Qwen3-Coder-30B-A3B   │                    │
│  │ 4-bit                 │                    │
│  └───────────────────────┘                    │
│                                               │
└───────────────────────────────────────────────┘
                     ▲
                     │
                  Tailscale
                     │
              ┌──────┴──────┐
              │ iPad mini   │
              │ Warp        │
              └─────────────┘

This architecture should be tested before moving the agent infrastructure to a VPS.

⸻

Relationship With Tailscale

Tailscale should remain the preferred private network layer.

Potential workflow:

iPad mini
   │
   │ Tailscale
   ▼
Mac mini
   │
   ▼
Herdr
   │
   ▼
Coding Agent

This provides a potentially powerful remote development environment:

* iPad mini as client
* external monitor
* keyboard
* mouse
* Warp
* Tailscale
* persistent coding-agent sessions
* local inference on the Mac mini

The user should be able to disconnect the iPad while a coding task continues on the Mac mini.

⸻

Important Compatibility Question

The primary technical question is not whether Herdr supports coding agents.

The important question is:

Can a Herdr-managed coding-agent session reliably communicate with the existing MLXServe OpenAI-compatible endpoint?

Target architecture:

Herdr
   ↓
OpenCode
   ↓
OpenAI-compatible API
   ↓
MLXServe
   ↓
Qwen3-Coder

This must be validated experimentally.

⸻

Experiment 1 — Herdr + OpenCode + Local Qwen

Objective

Run an existing coding task through:

Herdr → OpenCode → MLXServe → Qwen3-Coder

Procedure

1. Install Herdr on the Mac mini.
2. Confirm Herdr can launch and maintain an OpenCode session.
3. Configure OpenCode to use the local MLXServe endpoint.
4. Start a small repository task.
5. Disconnect Warp.
6. Wait while the task continues.
7. Reconnect from Warp.
8. Confirm that the session and agent state remain available.
9. Inspect repository changes.
10. Run tests.

Acceptance criteria

The experiment succeeds if:

* Herdr keeps the agent session alive.
* OpenCode continues operating after client disconnection.
* MLXServe remains reachable.
* Qwen continues generating responses.
* the agent can continue tool execution.
* reconnecting exposes the same session.
* repository changes remain intact.
* no duplicate agent execution occurs after reconnect.

⸻

Experiment 2 — Long-Running Local Coding Task

Use a task deliberately long enough to expose the current timeout problem.

For example:

Analyze repository
    ↓
Identify required changes
    ↓
Modify multiple files
    ↓
Run tests
    ↓
Fix failures
    ↓
Run tests again

Measure:

* total execution time
* inference time
* tool-call time
* time spent waiting
* number of model requests
* context size
* failures
* timeouts
* memory usage

The objective is to determine whether Herdr solves the session persistence problem, independently of whether it solves the inference performance problem.

⸻

Important Distinction: Timeout vs Persistence

Herdr should not be treated as a direct solution to every timeout.

There are at least two different failure modes:

Client/session timeout

Client
  ↓
connection lost
  ↓
agent terminates

Herdr may substantially improve this situation.

Model/API timeout

Agent
  ↓
MLXServe
  ↓
Qwen inference
  ↓
request exceeds timeout

Herdr does not automatically solve this.

Therefore the diagnostic workflow should distinguish:

SESSION FAILURE
        vs
AGENT FAILURE
        vs
MODEL/API FAILURE
        vs
CONTEXT FAILURE
        vs
RESOURCE FAILURE

This distinction should become part of Local LLMs Management diagnostics.

⸻

Integration With the Existing Local LLM Timeout Investigation

The previous timeout investigation should be extended with Herdr as a separate variable.

Current variables include:

* Qwen context size
* maximum tokens
* KV cache
* MLX memory consumption
* MLXServe configuration
* OpenCode configuration
* tool-call duration
* network/client timeout
* prompt size

Add:

* Herdr session persistence
* agent process lifetime
* reconnect behavior
* session recovery
* terminal lifecycle

This makes it possible to establish whether the problem is:

Inference performance

or:

Interactive-session lifetime

rather than assuming both are the same problem.

⸻

Relationship With Jev

Jev should remain responsible for model selection.

Potential future architecture:

                         Task
                          │
                          ▼
                  Local LLM Manager
                          │
                    Jev Router
                          │
             ┌────────────┼────────────┐
             ▼            ▼            ▼
          Local Qwen    Cloud LLM    Human
             │
             ▼
          Herdr
             │
             ▼
        Coding Agent
             │
             ▼
          Repository

Herdr should therefore be considered an execution substrate, not an LLM router.

This separation allows the same persistent-agent infrastructure to be used regardless of which model is selected.

⸻

Potential Future Architecture

┌────────────────────────────────────────────────────┐
│ Local LLM Management                               │
│                                                    │
│                    Task                            │
│                     │                              │
│                     ▼                              │
│              Prompt / Task Analysis                │
│                     │                              │
│                     ▼                              │
│               Jev / Router                         │
│                     │                              │
│          ┌──────────┼──────────┐                   │
│          ▼          ▼          ▼                   │
│       Local       Remote     Human                  │
│        LLM         LLM      Review                  │
│          │          │                              │
│          └──────────┼──────────┐                   │
│                     ▼          │                   │
│                  Herdr         │                   │
│                     │          │                   │
│                     ▼          │                   │
│               Coding Agent     │                   │
│                     │          │                   │
│                     ▼          │                   │
│                Repository      │                   │
└────────────────────────────────────────────────────┘

⸻

Potential Role in Memo Implementation Engine

Herdr may also be useful for the proposed Memo Implementation Engine.

A memo-driven task could become:

memo-042.md
     │
     ▼
Memo Implementation Engine
     │
     ▼
Jev
     │
     ▼
Select execution model
     │
     ▼
Herdr
     │
     ▼
Coding Agent
     │
     ▼
Implementation
     │
     ▼
Tests / Evidence
     │
     ▼
Human Review if required

This is particularly useful for long-running implementation memos because the execution environment can persist independently of the user’s active session.

⸻

Security Considerations

Herdr should not automatically be exposed to the public Internet.

Preferred initial configuration:

Internet
   X
   │
   │ no direct exposure
   ▼
Mac mini
   │
Tailscale
   │
   ▼
Herdr

Evaluate:

* authentication
* authorization
* terminal/session isolation
* filesystem permissions
* repository permissions
* secrets exposure
* API credentials
* model endpoint exposure
* Tailscale ACLs
* agent command execution permissions

The local MLXServe endpoint should preferably remain bound to the local machine unless remote access is explicitly required.

⸻

Resource Considerations

The Mac mini has finite memory and compute resources.

Herdr itself is expected to be relatively lightweight compared with:

Qwen3-Coder
MLX
KV cache
OpenCode
repository tooling
build/test processes

However, running multiple persistent coding agents could create significant resource contention.

Initially enforce:

1 persistent local coding-agent session

Then experimentally evaluate:

2 sessions
3 sessions
...

Monitor:

* unified memory
* CPU utilisation
* GPU utilisation
* inference latency
* context throughput
* swap
* MLX memory
* filesystem activity

Do not optimize for the maximum number of simultaneous sessions before establishing reliable single-session performance.

⸻

Success Definition

Herdr should be adopted into Local LLMs Management if experimentation demonstrates that it can provide:

1. Persistent local coding-agent sessions.
2. Reliable reconnect after Warp/iPad disconnection.
3. Compatibility with OpenCode or Qwen Code.
4. Reliable communication with the local MLXServe endpoint.
5. No degradation that outweighs the persistence benefit.
6. A clean separation between session management and model selection.
7. A useful foundation for long-running Memo Implementation Engine tasks.

⸻

Proposed Decision

Do not replace MLXServe, OpenCode, Qwen, Warp, or Tailscale.

Instead, prototype Herdr as an additional layer:

Tailscale
    ↓
Herdr
    ↓
OpenCode
    ↓
MLXServe
    ↓
Qwen3-Coder

If successful, incorporate Herdr into the Local LLM Management architecture as the persistent Agent Execution Layer.

Jev remains the Model Selection Layer.

MLXServe remains the Local Inference Layer.

Warp remains the Interactive Development Interface.

This produces a modular architecture in which each component has a clearly defined responsibility.

⸻

Next Actions

* [ ]	Inspect Herdr installation and supported-agent documentation.
* [ ]	Install Herdr on the Mac mini.
* [ ]	Start an OpenCode session through Herdr.
* [ ]	Configure OpenCode for the existing MLXServe endpoint.
* [ ]	Run a controlled local Qwen coding task.
* [ ]	Disconnect Warp.
* [ ]	Reconnect through Tailscale.
* [ ]	Verify agent/session persistence.
* [ ]	Measure inference versus session timeout behavior.
* [ ]	Document failures separately as session, agent, API, context, or resource failures.
* [ ]	Evaluate Herdr for Memo Implementation Engine workloads.
* [ ]	Add Herdr to the Local LLM Management architecture if the experiment succeeds.
