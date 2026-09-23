# Memo 12: Jev-Based LLM Routing for Cost-Optimized Local and Cloud Coding

Status: Proposed
Target: Open Engineering Local Large Language Models Management
Purpose: Investigate and implement Jev as an intelligent routing layer for selecting the most appropriate LLM for each coding task.

⸻

1. Objective

Our objective is to reduce the cost of AI-assisted software development while retaining high productivity.

The current strategy already distinguishes between:

* local LLM inference;
* inexpensive cloud inference;
* powerful cloud models;
* human review.

The next step is to automate the decision about which model should handle each individual task.

Jev is a promising candidate for this routing layer.

Rather than asking an expensive reasoning model to decide which model should perform a task, Jev can make a structured routing decision before execution.

The proposed architecture is therefore:

                         Coding Task
                              |
                              v
                       +-------------+
                       |     Jev     |
                       |   Router    |
                       +------+------+
                              |
                    Routing decision
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
     Local Qwen         Cloud Balanced      Cloud Strong
          |                   |                   |
          +-------------------+-------------------+
                              |
                              v
                       Execute + Test
                              |
                              v
                         Success?
                        /        \
                      yes         no
                       |           |
                       v           v
                    Finish      Escalate

The important architectural principle is:

Jev recommends the execution tier; our routing policy decides what is permitted; the selected LLM performs the work.

⸻

2. Why Jev is relevant

Jev is not intended to be the model that writes the code.

It is a decision/routing model that can evaluate a task and return a structured choice.

Existing Jev-based routers demonstrate routing according to factors such as:

* task complexity;
* reasoning requirements;
* tool complexity;
* context size;
* confidence;
* available model tiers.

For example, an existing open-source Jev router exposes decisions resembling:

Task complexity     0.82
Reasoning required  0.91
Tool complexity     0.64
Context size        0.31
Recommended tier: SONNET
Confidence: 94%

This is particularly suitable for our objective because the routing decision is considerably cheaper than executing every task on a high-end coding model.

Reference implementation:

https://github.com/gargpratyush/jev-router

⸻

3. Do not use Jev as an unrestricted model selector

Jev should not directly control our infrastructure.

Instead, introduce a Routing Policy Layer between Jev and the execution models.

Prompt
  |
  v
Jev
  |
  | recommendation
  v
Routing Policy
  |
  +-- capability checks
  +-- availability checks
  +-- cost limits
  +-- context limits
  +-- tool compatibility
  +-- reliability history
  +-- security/risk rules
  |
  v
Selected execution model

This protects the system against a routing recommendation that is technically unsuitable for the actual environment.

For example, a model may be recommended because it has sufficient reasoning capability but may not support:

* the required context size;
* MCP tools;
* function/tool calling;
* the required API format;
* the repository’s coding workflow.

The routing policy must therefore verify these constraints before execution.

⸻

4. Proposed execution tiers

Initially define four execution tiers.

Tier 0 — Local Fast

Primary candidate: local Qwen

Suitable for:

* simple edits;
* renaming;
* formatting;
* straightforward bug fixes;
* small isolated changes;
* documentation;
* simple tests;
* deterministic transformations.

Primary objective:

Use local inference whenever the task is sufficiently simple and reliable.

⸻

Tier 1 — Local Code

Primary candidate: Qwen3-Coder-30B-A3B-Instruct-4bit running locally through MLX.

Suitable for:

* ordinary coding tasks;
* single-component implementation;
* small multi-file changes;
* test implementation;
* refactoring with limited blast radius.

The local model should be preferred when its historical success rate for the task category is sufficiently high.

This is important because our local inference has already demonstrated timeout/tool-call problems.

A task should therefore not be considered suitable for local execution solely because Jev considers it “easy”.

⸻

Tier 2 — Cloud Balanced

Suitable for:

* multi-file implementations;
* more complex debugging;
* unfamiliar APIs;
* moderate architectural changes;
* tasks requiring reliable tool use.

This tier acts as the normal escalation path when local inference is uncertain.

⸻

Tier 3 — Cloud Strong

Suitable for:

* difficult architecture;
* large refactoring;
* complex debugging;
* high-risk changes;
* tasks with high reasoning requirements;
* repeated failure at lower tiers.

This tier should be used sparingly because it is the expensive fallback.

⸻

Tier 4 — Human Review

Some tasks should not automatically escalate indefinitely.

Examples:

* ambiguous requirements;
* security-sensitive changes;
* destructive operations;
* architectural decisions with insufficient evidence;
* repeated model failure;
* changes that cannot be validated automatically.

The system should explicitly stop and request human intervention.

⸻

5. Routing decision

Jev should receive a task description and enough metadata to understand the execution context.

Example conceptual input:

task:
  description: "Implement memo #17 in the repository"
  type: implementation
  files_affected: unknown
  expected_tools:
    - filesystem
    - git
    - test_runner
repository:
  language: rust
  framework: pyo3
  size: medium
execution:
  local_model_available: true
  local_model: qwen3-coder
  local_context: 8192

The router can then produce a structured recommendation such as:

tier: local-code
confidence: 0.91
reasoning_required: 0.54
tool_complexity: 0.48
context_complexity: 0.42

The exact schema should be defined during implementation.

⸻

6. Local model reliability must be part of routing

This is especially important for our environment.

We are not merely choosing between models according to theoretical capability.

We are trying to determine:

Which model is most economically likely to successfully complete this particular task?

A theoretically capable local model is not economical if it repeatedly times out.

Therefore our router must collect execution telemetry.

For every task record:

routing:
  recommended_tier:
  selected_tier:
  confidence:
execution:
  model:
  duration:
  input_tokens:
  output_tokens:
  tool_calls:
  retries:
  timeout:
result:
  completed:
  tests_passed:
  human_intervention:
  escalated:

This data becomes the basis for improving the routing policy.

⸻

7. Feedback loop

The system should learn from actual execution outcomes.

              +----------------+
              |      Jev       |
              +-------+--------+
                      |
                      v
                Route decision
                      |
                      v
                Execute task
                      |
                      v
                Run validation
                      |
          +-----------+-----------+
          |                       |
        success                 failure
          |                       |
          v                       v
       record                  escalate
          |                       |
          +-----------+-----------+
                      |
                      v
                 Telemetry

Over time we can calculate empirical reliability.

For example:

Task category       Local Qwen success
---------------------------------------
Documentation             99%
Small edits               96%
Simple coding             91%
Multi-file coding         74%
Tool-heavy coding         61%
Large refactoring         42%

These numbers are examples only.

They must be measured from our own workload.

The router should eventually use these measurements as an additional signal.

⸻

8. Escalation policy

A key principle is:

Do not waste expensive tokens attempting work that has already demonstrated that the current model cannot reliably complete it.

Suggested initial policy:

Jev confidence < 0.70
    |
    +--> do not downgrade
    +--> maximum recommended tier = Balanced
Jev recommends Local
    |
    +--> execute locally
Local timeout
    |
    +--> retry once only if failure appears transient
    |
    +--> otherwise escalate
Local tool-call failure
    |
    +--> do not repeatedly retry
    +--> escalate
Local implementation fails tests
    |
    +--> allow one repair attempt
    +--> escalate if unsuccessful
Balanced failure
    |
    +--> Strong
Strong failure
    |
    +--> Human review

These thresholds should initially be configuration values rather than hard-coded rules.

⸻

9. Important distinction: routing versus escalation

Routing answers:

Which model should start this task?

Escalation answers:

What should happen when that model cannot finish it?

These should remain separate.

For example:

Jev
  ↓
Local Qwen
  ↓
timeout
  ↓
Cloud Balanced
  ↓
tests fail
  ↓
Cloud Strong
  ↓
human review

This creates a controlled execution ladder rather than a single model choice.

⸻

10. Tool calls require special treatment

Our local Qwen environment has previously exhibited problems involving tool-call compatibility, including:

tool_calls[].id: null

and interaction problems between MLX serving and coding agents.

Consequently, tool capability must become an explicit routing property.

Example:

capabilities:
  tool_calling: true
  mcp: true
  streaming: true
  structured_output: true

A model must not be selected merely because it has adequate reasoning capability.

It must also be compatible with the execution protocol.

This is particularly important for:

* OpenCode;
* Warp;
* MCP;
* Composio;
* filesystem tools;
* shell execution;
* test runners.

⸻

11. Context size must be an explicit constraint

Our local Qwen configuration currently uses an approximately 8K context configuration.

The router must therefore account for:

prompt size
+
repository context
+
tool definitions
+
conversation history
+
expected output

A task that appears simple may nevertheless be unsuitable for local execution if the required context exceeds the available window.

The routing layer should therefore perform a context feasibility check before execution.

⸻

12. Long conversations require special handling

Model switching can have economic consequences beyond the nominal per-token price.

A long conversation may contain substantial cached or reusable context.

Switching models can invalidate or reduce the benefit of that cached context.

Therefore:

Short task
    → aggressive cost optimisation
Long conversation
    → favour continuity
Large existing context
    → avoid unnecessary downgrade
Expensive context reconstruction
    → include in routing economics

The router should eventually consider total task cost, not simply model input/output pricing.

⸻

13. Jev failure must never block development

The routing layer should be fail-open.

If Jev is:

* unavailable;
* slow;
* incorrectly configured;
* returning an invalid response;
* temporarily unavailable;

the coding workflow should continue using a safe fallback model.

Conceptually:

Jev available?
     |
   yes
     ↓
 route normally
   no
     ↓
 safe default

The fallback should initially be the currently selected/default execution model rather than silently choosing a more expensive model.

This principle is used by existing Jev routers as well. (GitHub)

⸻

14. Security and privacy

Jev routing introduces an important consideration:

The prompt used for routing may be sent to an external routing service.

The current jev-router implementation explicitly documents that prompt text is sent to TypeSafe for the routing decision. (GitHub)

Therefore we must establish a policy for proprietary Open Engineering source code.

Potential approaches:

Option A — Full prompt routing

Send the original task to Jev.

Advantages:

* best routing information.

Disadvantage:

* source/task information leaves the local environment.

Option B — Sanitised routing description

Generate a minimal task descriptor locally:

Task type: Rust implementation
Files: approximately 6
Estimated complexity: multi-file
Tool requirements: filesystem + tests
Risk: medium

Send only that information to Jev.

This improves privacy but may reduce routing accuracy.

Option C — Hybrid

Use local preprocessing to remove source code while retaining structural/task metadata.

This should be the preferred architecture for sensitive repositories unless Jev’s data-handling guarantees meet our requirements.

⸻

15. Existing open-source implementations

Several projects demonstrate practical Jev routing.

gargpratyush/jev-router

Automatic per-turn routing for Claude Code and OpenAI Codex.

It preserves the native CLI interfaces and uses abstract routing tiers such as:

Fast
Balanced
Strong
Long

It also demonstrates confidence thresholds, fallbacks, tool-loop handling and model availability checks.

Reference:

https://github.com/gargpratyush/jev-router (GitHub)

⸻

satviksinha/jev-model-router

A Claude Code-oriented Jev model router where routing policy is explicitly represented as tier criteria.

Reference:

https://github.com/satviksinha/jev-model-router (GitHub)

⸻

its-panzer/jev-model-router

A Python implementation that separates the routing decision from downstream execution.

This architecture is particularly interesting for Local Large Language Models Management because the router does not need to own the actual LLM invocation.

It returns a model decision and leaves execution to the caller.

Reference:

https://github.com/its-panzer/jev-model-router (GitHub)

The repository also explicitly identifies retry/escalation after execution as a separate layer, which matches the proposed architecture here. (GitHub)

⸻

hyspacex/jev-router

An OpenAI-compatible routing implementation.

This is particularly relevant to our MLX/OpenAI-compatible local serving architecture because it demonstrates a router sitting in front of an OpenAI-style endpoint.

Reference:

https://github.com/hyspacex/jev-router (GitHub)

The project itself warns that its model names and evaluation evidence should not automatically be interpreted as equivalent performance for another model pool. That is an important principle for our implementation.

⸻

16. Evidence and limitations

Jev should be treated as an experiment rather than an assumed optimal router.

One public Jev routing experiment reports promising cost/accuracy results, but its own analysis notes that an ablation without Jev achieved the same result in one benchmark, indicating that the observed gain came from retrieval rather than Jev’s difficulty signal. (GitHub)

Therefore:

We must benchmark Jev against simpler routing strategies using our own coding workload.

Candidate baselines:

1. always local;
2. always cheap cloud;
3. always strong cloud;
4. static task-category routing;
5. Jev routing;
6. Jev + telemetry;
7. Jev + telemetry + escalation.

The goal is not to prove that Jev is universally superior.

The goal is to determine whether Jev improves the cost/productivity/reliability frontier of our own development workflow.

⸻

17. Proposed implementation architecture

Create a new routing component inside Local Large Language Models Management:

local-large-language-models-management
│
├── routing/
│   ├── jev/
│   ├── policy/
│   ├── telemetry/
│   ├── escalation/
│   └── adapters/
│
├── models/
│   ├── local/
│   │   └── qwen/
│   ├── cloud/
│   │   ├── balanced/
│   │   └── strong/
│
└── evaluations/
    ├── routing/
    ├── local-vs-cloud/
    └── jev/

The most important abstraction should be:

Router
   ↓
RouteDecision
   ↓
ExecutionAdapter
   ↓
ExecutionResult
   ↓
Telemetry

This prevents Jev from becoming tightly coupled to a particular coding agent.

⸻

18. RouteDecision

Define a common internal representation:

RouteDecision:
  task_id:
  recommended_tier:
  selected_tier:
  model:
  confidence:
  reasoning_required:
  tool_complexity:
  context_complexity:
  estimated_cost:
  fallback_tier:
  reason:

This allows the same routing system to drive:

* OpenCode;
* Warp;
* future coding agents;
* direct API calls;
* automated Memo Implementation Engine tasks.

⸻

19. ExecutionAdapter

Each model provider should be hidden behind an adapter.

ExecutionAdapter
    |
    +-- MLX/Qwen
    +-- OpenAI-compatible API
    +-- Anthropic
    +-- other cloud provider

The router should not need to know how an individual model is invoked.

This is particularly important because our local Qwen endpoint is served through MLX and may have compatibility differences from standard OpenAI APIs.

⸻

20. Relationship with the Memo Implementation Engine

Jev should become one component of the previously proposed Memo Implementation Engine.

The resulting architecture becomes:

memo.md
   |
   v
Memo Implementation Engine
   |
   v
Task decomposition
   |
   v
Jev Router
   |
   v
Routing Policy
   |
   +------ Local Qwen
   |
   +------ Cloud Balanced
   |
   +------ Cloud Strong
   |
   +------ Human
   |
   v
Implementation
   |
   v
Tests / validation
   |
   v
Telemetry
   |
   v
Learning / routing improvement

This gives the Open Engineering ecosystem a consistent mechanism for deciding how AI-assisted implementation should be performed.

⸻

21. Initial implementation phases

Phase 1 — Observe

Do not automatically route yet.

For existing coding tasks:

1. send task descriptions to Jev;
2. record its recommendation;
3. continue using the current model;
4. compare recommendation with actual outcome.

Goal:

Establish whether Jev’s decisions correlate with task difficulty in our environment.

⸻

Phase 2 — Shadow routing

Run Jev beside the existing workflow.

Example:

Actual model: Qwen
Jev recommendation: Balanced
Result: timeout

Collect enough samples to determine whether routing could have avoided failures.

⸻

Phase 3 — Controlled local routing

Allow Jev to select between:

Local Qwen
Cloud Balanced

with strict fallback rules.

This is the first phase where meaningful cost savings can be measured.

⸻

Phase 4 — Add Strong escalation

Introduce:

Local
  ↓
Balanced
  ↓
Strong
  ↓
Human

based on execution results.

⸻

Phase 5 — Optimise using telemetry

Use accumulated data to adjust:

* confidence thresholds;
* local-model eligibility;
* task categories;
* escalation thresholds;
* context thresholds;
* timeout limits.

⸻

22. Success metrics

The project should measure more than token cost.

Primary metrics:

Cost per successfully completed task
Task completion rate
Time to successful completion
Local execution percentage
Cloud escalation percentage
Timeout rate
Tool-call failure rate
Test-pass rate
Human intervention rate

A useful overall metric is:

Total AI Cost
-------------------------------
Successfully Completed Tasks

A second important metric:

Median Time to Successful Completion

A routing strategy that saves tokens but makes development substantially slower may not be economically beneficial.

⸻

23. Target outcome

The desired end state is not:

“Always use the cheapest model.”

It is:

Use the least expensive execution path that has a sufficiently high probability of successfully completing the task within acceptable time and quality constraints.

Conceptually:

                 Cheapest
                    |
                    v
             Can it succeed?
               /          \
             yes           no
              |             |
              v             v
           execute       escalate
                            |
                            v
                     next capability tier

This is the fundamental principle for Local Large Language Models Management.

⸻

24. Decision

Proceed with a Jev routing prototype.

Do not immediately make Jev the production routing authority.

First implement:

1. Jev observation;
2. routing telemetry;
3. local Qwen reliability measurement;
4. shadow evaluation;
5. controlled Local-vs-Cloud routing;
6. escalation;
7. cost/productivity comparison.

The prototype should be deliberately provider-independent.

Jev should be treated as the routing intelligence, while Local Large Language Models Management owns:

* policy;
* model capabilities;
* availability;
* security;
* cost constraints;
* reliability history;
* escalation;
* telemetry.

⸻

25. Key architectural principle

The resulting system can be summarized as:

Jev decides
Policy governs
LLM executes
Tests validate
Telemetry learns
Human controls

This gives us a path toward an AI coding infrastructure that can increasingly rely on local inference without blindly forcing difficult tasks through a local model that cannot reliably complete them.

The ultimate objective remains:

Maximise coding productivity per euro by automatically using local LLMs whenever they are sufficiently capable and reliable, while escalating to cloud models only when the expected value justifies the additional cost.

⸻

References

1. Jev Router — automatic per-turn routing for Claude Code and OpenAI Codex
    https://github.com/gargpratyush/jev-router (GitHub)
2. Jev Model Router — Claude Code routing implementation
    https://github.com/satviksinha/jev-model-router (GitHub)
3. Jev Model Router — policy-based Python implementation
    https://github.com/its-panzer/jev-model-router (GitHub)
4. Jev Router — OpenAI-compatible routing implementation
    https://github.com/hyspacex/jev-router (GitHub)
5. Jev routing benchmark / RouterArena experiment
    https://github.com/TokenTrim/jev-routing-experiment (GitHub)
6. JevRouter — model, tool and subagent routing architecture
    https://github.com/BillionsBobby/JevRouter (GitHub)

⸻

Next implementation memo: Define the concrete Jev Router + Qwen + Cloud Escalation prototype, including the API contract, routing-policy YAML, MLX adapter, OpenCode/Warp integration, telemetry schema, timeout thresholds, and an evaluation dataset derived from real Open Engineering coding tasks.
