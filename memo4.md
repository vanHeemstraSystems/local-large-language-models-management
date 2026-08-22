Memo: Local LLM Development Stack with Eigent, MLX and Augment

Repository: vanHeemstraSystems/local-large-language-models-management  
File: memo4.md  
Status: Implementation proposal  
Date: 2026-08-13  

⸻

# 1. Purpose

This memo defines an implementable approach for building a local AI-assisted software engineering environment on an Apple Silicon Mac mini.

The primary objective is not to eliminate cloud AI services completely.

Instead, the objective is to:

Move routine and agentic software-engineering workloads to locally hosted LLMs, while retaining Augment Code Intent as a premium escalation path for work where its repository Context Engine and cloud models provide material additional value.

The target architecture combines:

* Eigent as a local agent/workspace and orchestration layer;
* Qwen3-30B-A3B as the initial local coding/reasoning model;
* an Apple-Silicon-optimized local inference server, preferably using MLX where practical;
* MCP and local tools for repository, filesystem, shell and other integrations;
* Augment Code Intent for difficult, context-heavy and cross-repository engineering work.

The implementation must be measurable. We should be able to determine how much work can safely be moved from paid cloud inference to local inference and what that saves.

⸻

# 2. Hardware Baseline

The initial implementation target is:

Mac mini
├── Apple M4 Pro
├── 14 CPU cores
│   ├── 10 performance
│   └── 4 efficiency
├── 24 GB unified memory
└── macOS

This is an important architectural constraint.

The system should therefore favor:

* Apple Silicon native software;
* Metal acceleration;
* MLX-compatible models;
* quantized models;
* memory-efficient inference;
* models with relatively small active parameter counts;
* services that can run without Docker where Docker adds unnecessary overhead.

The first model candidate is:

Qwen3-30B-A3B

Its mixture-of-experts architecture makes it particularly interesting because the total parameter count is much larger than the number of parameters activated for an individual token.

However, actual memory consumption and performance on the 24 GB machine must be benchmarked rather than assumed.

⸻

# 3. Strategic Architecture

The desired architecture is:

                         SOFTWARE ENGINEERING
                                  │
                     ┌────────────┴────────────┐
                     │                         │
                  LOCAL                     PREMIUM
                     │                         │
                  Eigent                  Augment Code
                     │                       Intent
              Agent orchestration              │
                     │                  Augment Context
              ┌──────┴──────┐                 Engine
              │             │                  │
          Local LLM        Tools           Cloud LLMs
              │             │
       Local inference     MCP
              │             │
       Qwen3-30B-A3B    ┌───┼────────────┐
                        │   │            │
                      Git  Shell      Filesystem

The key architectural decision is:

Do not make Augment the mandatory gateway to the local model.

The local environment should remain independently usable.

This produces two complementary engineering paths.

⸻

# 4. Local Path

The local path should eventually resemble:

Developer
    │
    ▼
Eigent
    │
    ├── Developer Agent
    ├── Repository Agent
    ├── Test Agent
    ├── Documentation Agent
    └── Research Agent
            │
            ▼
       Local LLM API
            │
            ▼
      Qwen3-30B-A3B
            │
            ▼
       Apple M4 Pro

Tools are exposed separately:

Eigent
   │
   └── MCP / Tools
        │
        ├── filesystem
        ├── Git
        ├── terminal
        ├── GitHub
        ├── browser
        └── future Open Engineering tools

This means Eigent should be viewed primarily as an agent orchestration and execution environment, not as the LLM runtime itself.

⸻

# 5. Premium Path

Augment Code Intent remains available:

Developer
    │
    ▼
Augment Code Intent
    │
    ▼
Augment Context Engine
    │
    ▼
Cloud models

This path should increasingly be reserved for situations such as:

* large repository understanding;
* complex dependency analysis;
* cross-repository changes;
* difficult debugging;
* architectural changes;
* large refactorings;
* unfamiliar codebases;
* tasks where local agents repeatedly fail;
* tasks where reviewer effort exceeds the savings from local inference.

The guiding principle is:

Use local inference by default where it is sufficiently capable; escalate to Augment where additional intelligence or context has measurable value.

⸻

# 6. Why Eigent

Eigent is attractive because it addresses a different layer from the LLM runtime.

It provides an agentic environment capable of coordinating models and tools.

Relevant characteristics include:

* open-source availability;
* local deployment;
* model independence;
* local model support;
* multi-agent orchestration;
* tool use;
* MCP integration;
* browser capabilities;
* developer-oriented workflows.

Reference:

https://www.eigent.ai/

Repository:

https://github.com/eigent-ai/eigent

Augment comparison:

https://www.eigent.ai/blog/augment-code-alternative

Eigent should therefore initially be evaluated as the agent/workspace layer above the local inference infrastructure.

⸻

# 7. Why Qwen3-30B-A3B

The initial model candidate is:

https://huggingface.co/Qwen/Qwen3-30B-A3B

The model is particularly interesting for constrained local hardware because it uses a mixture-of-experts architecture.

Conceptually:

Qwen3-30B-A3B
Total model
     │
     ├── many experts
     │
     └── only a subset activated per token
                    │
                    ▼
            ~3B active parameters

This does not mean the model consumes only the memory of a 3B model.

The model weights still need to be stored and made accessible.

Quantization is therefore essential for the 24 GB target machine.

The first implementation should use a proven MLX-compatible quantized version rather than converting the original model immediately.

⸻

# 8. Local Model Serving Layer

The model serving layer should be treated as replaceable infrastructure.

Eigent should ideally communicate through a standard interface:

Eigent
   │
   ▼
OpenAI-compatible API
   │
   ▼
Model server
   │
   ▼
Qwen

This makes it possible to evaluate multiple runtimes without redesigning the agent layer.

Candidates should include:

1. MLXServe;
2. MLX-LM server;
3. Ollama;
4. LM Studio;
5. another OpenAI-compatible Apple Silicon runtime if benchmarking demonstrates a clear advantage.

The preferred end-state is:

                  Eigent
                     │
             OpenAI-compatible
                     │
             localhost endpoint
                     │
              ┌──────┴──────┐
              │             │
          MLX runtime    alternative
              │
              ▼
       Qwen3-30B-A3B

MLX should receive particular attention because the hardware is Apple Silicon.

⸻

# 9. Why the API Boundary Matters

Avoid tightly coupling Eigent to a specific runtime.

Instead define a stable internal contract such as:

http://localhost:<port>/v1

with an OpenAI-compatible API.

Then:

Eigent
     │
     ▼
Local LLM API
     │
     ├── MLXServe
     │
     ├── MLX-LM
     │
     ├── Ollama
     │
     └── LM Studio

This permits experimentation without changing the rest of the system.

It also allows additional models to be introduced later.

⸻

# 10. Repository Structure

The local-large-language-models-management repository should become the source of truth for the local LLM environment.

A suggested structure is:

local-large-language-models-management/
│
├── README.md
├── memo.md
│
├── docs/
│   ├── architecture.md
│   ├── installation.md
│   ├── models.md
│   ├── runtimes.md
│   ├── eigent.md
│   ├── augment.md
│   ├── benchmarking.md
│   └── troubleshooting.md
│
├── config/
│   ├── models/
│   │   └── qwen3-30b-a3b.yaml
│   │
│   ├── runtimes/
│   │   ├── mlx.yaml
│   │   ├── ollama.yaml
│   │   └── lm-studio.yaml
│   │
│   └── eigent/
│       └── local.yaml
│
├── scripts/
│   ├── install.sh
│   ├── start-model.sh
│   ├── stop-model.sh
│   ├── status.sh
│   ├── benchmark.sh
│   └── healthcheck.sh
│
├── benchmarks/
│   ├── README.md
│   ├── tasks/
│   ├── results/
│   └── scorecards/
│
└── experiments/
    ├── mlxserve/
    ├── ollama/
    ├── lm-studio/
    └── eigent/

Do not create unnecessary abstraction before the first working implementation.

The initial objective is a reproducible vertical slice.

⸻

# 11. Phase 1 — Establish the Baseline

Before installing anything new, record the baseline.

Create:

docs/baseline.md

Record:

Hardware
OS version
available memory
available disk space
existing development tools
Python version
Homebrew version
Docker status
existing Ollama/LM Studio installations
Augment usage/cost baseline

The Augment baseline is especially important.

Record at least:

period
number of representative tasks
Augment expenditure
approximate prompts
types of tasks

Without this information, later cost savings cannot be demonstrated.

⸻

# 12. Phase 2 — Establish Local Qwen Inference

Do not introduce Eigent yet.

First prove that Qwen can run acceptably on the Mac.

Target:

Prompt
   │
   ▼
localhost API
   │
   ▼
Qwen3-30B-A3B
   │
   ▼
response

Success criteria:

* model loads reliably;
* no severe memory pressure;
* system remains usable;
* API is reachable locally;
* coding prompts work;
* generation speed is acceptable;
* long prompts do not destabilize the system.

Record:

model
quantization
runtime
RAM consumption
load time
time-to-first-token
tokens/second
context size
prompt size
temperature
result quality

Do not optimize prematurely.

First establish a reproducible working configuration.

⸻

# 13. Phase 3 — Runtime Bake-Off

Once one runtime works, compare alternatives.

For example:

Runtime	Model	RAM	TTFT	tok/s	Stability	Eigent compatibility
MLXServe	Qwen3	TBD	TBD	TBD	TBD	TBD
MLX-LM	Qwen3	TBD	TBD	TBD	TBD	TBD
Ollama	Qwen3	TBD	TBD	TBD	TBD	TBD
LM Studio	Qwen3	TBD	TBD	TBD	TBD	TBD

The winner should not simply be the runtime with the highest tokens per second.

Evaluate:

performance
+
memory consumption
+
reliability
+
API compatibility
+
context handling
+
operational simplicity
+
Eigent integration

If MLX provides substantially better Apple Silicon performance, prefer MLX.

If another runtime provides nearly equivalent performance with dramatically simpler operations, that trade-off should be considered.

⸻

# 14. Phase 4 — Standardize the Local API

Once the initial runtime is selected, define a stable configuration.

Conceptually:

provider:
  type: openai-compatible
  base_url: http://127.0.0.1:PORT/v1
model:
  id: qwen3-30b-a3b
runtime:
  type: mlx

Exact fields should reflect the selected software rather than forcing this example.

Credentials should never be committed.

For a local endpoint that requires a placeholder API key, place it in environment configuration.

For example:

.env

and:

.env.example

Commit only the example.

⸻

# 15. Phase 5 — Install Eigent

After local inference works independently, install Eigent.

Do not debug the model runtime and Eigent simultaneously.

Verify Eigent independently before connecting it to the local model.

Target:

Eigent starts
     │
     ▼
UI available
     │
     ▼
agent can be created
     │
     ▼
provider configuration accessible

Document the installation in:

docs/eigent.md

Include:

* version;
* installation mechanism;
* configuration;
* local storage;
* logs;
* startup;
* shutdown;
* update procedure;
* uninstall procedure.

Pin versions wherever practical.

⸻

# 16. Phase 6 — Connect Eigent to Qwen

Now connect the two systems:

Eigent
   │
   ▼
localhost OpenAI-compatible endpoint
   │
   ▼
Qwen3-30B-A3B

The first test should deliberately be simple.

For example:

Explain what this Python function does.

Then:

Create unit tests for this function.

Then:

Refactor this function while preserving its behavior.

Only after simple inference works should tools and repository access be introduced.

⸻

# 17. Phase 7 — Repository Agent

The next milestone is local repository understanding.

Target:

Eigent
   │
   ├── Qwen
   │
   └── Repository tools
           │
           ▼
        Git repo

The agent should be able to:

* list files;
* inspect repository structure;
* read source files;
* search text;
* inspect Git history where appropriate;
* understand build configuration;
* identify tests;
* propose changes.

Initially, changes should require human review.

Do not give the first experimental agent unrestricted autonomous write access to important repositories.

Use a disposable branch or test repository.

⸻

# 18. Phase 8 — Shell and Test Agent

Introduce controlled command execution.

Desired flow:

Developer
    │
    ▼
Eigent
    │
    ▼
Developer Agent
    │
    ├── inspect source
    ├── modify source
    └── request tests
             │
             ▼
         Test Agent
             │
             ▼
           shell
             │
             ▼
          results

Allow-listed operations should initially include common safe development commands such as:

git status
git diff
git log
find
grep
rg
pytest
npm test
deno test

Adapt the list to the repository under test.

Destructive commands should require explicit approval.

⸻

# 19. Phase 9 — MCP

MCP should become the preferred integration boundary for external capabilities where suitable.

Conceptually:

Eigent
   │
   ▼
MCP
   │
   ├── Filesystem
   ├── Git/GitHub
   ├── Browser
   ├── Documentation
   └── Open Engineering

The benefit is architectural separation:

Agent reasoning
      │
      ▼
tool contract
      │
      ▼
implementation

This avoids hard-coding every capability into an individual agent.

⸻

# 20. Phase 10 — Agent Roles

Do not begin with a large agent hierarchy.

Start with three roles.

Developer Agent

Responsibilities:

* source inspection;
* implementation;
* refactoring;
* debugging;
* code explanation.

Test Agent

Responsibilities:

* determine appropriate tests;
* generate tests;
* run tests;
* interpret failures;
* return evidence.

Documentation Agent

Responsibilities:

* README updates;
* architecture documentation;
* comments where appropriate;
* change summaries;
* migration documentation.

Later introduce specialized agents only when evidence demonstrates their usefulness.

Potential future agents:

Repository Agent
Architecture Agent
Security Agent
Release Agent
Research Agent
Review Agent

⸻

# 21. Human-in-the-Loop Requirement

The initial environment should operate as:

Agent proposes
      │
      ▼
Human reviews
      │
      ▼
Agent executes

rather than:

Agent decides
      │
      ▼
Agent modifies everything
      │
      ▼
Agent pushes

In particular, require approval before:

* deleting files;
* installing packages;
* modifying infrastructure;
* accessing credentials;
* committing;
* pushing;
* opening pull requests;
* executing arbitrary shell commands;
* changing remote systems.

Autonomy can be increased later based on evidence.

⸻

# 22. The Augment Escalation Policy

The environment needs a clear rule for when to stop using the local agent.

A local task should be escalated to Augment when one or more of the following occurs:

local agent fails twice
OR
repository context appears incomplete
OR
cross-repository reasoning is required
OR
architectural implications are unclear
OR
generated change fails review
OR
local context window becomes limiting
OR
review effort exceeds expected Augment cost

This produces:

                 TASK
                   │
                   ▼
             Local first?
                   │
              yes  │
                   ▼
                Eigent
                   │
             successful?
               /       \
             yes        no
              │          │
              ▼          ▼
           accept      Augment

This policy should be refined using benchmark data.

⸻

# 23. Benchmark Against Augment

This is one of the most important phases.

Do not judge Eigent/local Qwen using toy prompts.

Select approximately ten genuine software-engineering tasks.

They should include a mixture of:

1. explain existing code;
2. locate an implementation;
3. fix a small bug;
4. add tests;
5. implement a small feature;
6. refactor several files;
7. update documentation;
8. understand a dependency;
9. perform a repository-wide change;
10. perform a difficult context-heavy task.

Run equivalent tasks through:

A. Eigent + local Qwen
B. Augment Code Intent

Avoid using the result of one system to improve the prompt given to the other.

⸻

# 24. Scorecard

For every task record:

task:
system:
model:
runtime:
quality:
  correctness:
  repository_understanding:
  dependency_awareness:
  code_quality:
  test_quality:
performance:
  elapsed_time:
  retries:
  interventions:
cost:
  cloud_cost:
  local_cost_estimate:
review:
  reviewer_minutes:
  corrections_required:
  accepted:

Use a simple 1–5 score for subjective dimensions.

Example:

1 = unacceptable
2 = poor
3 = usable
4 = good
5 = excellent

⸻

# 25. The Metric That Matters

Do not optimize only for token price.

The actual economic metric should approximate:

Effective Cost
    =
AI expenditure
    +
review effort
    +
correction effort
    +
failure/retry cost

For example, a local task costing effectively zero in API charges but requiring 30 minutes of repair can be more expensive than an Augment task costing €1 and requiring two minutes of review.

Therefore measure:

€ per accepted task

and ideally:

€ per accepted engineering outcome

rather than simply:

€ per token

⸻

# 26. Augment Cost Reduction

Once sufficient measurements exist, classify work.

For example:

Class A — Local preferred
documentation
unit tests
simple refactors
code explanations
boilerplate
small functions
Class B — Try local first
bug fixes
multi-file refactors
feature additions
dependency upgrades
Class C — Augment preferred
large architectural work
large monorepo changes
complex debugging
cross-repository changes
high-risk modifications

The target is to increase Class A and Class B over time.

⸻

# 27. Cost Dashboard

The repository should eventually maintain monthly measurements.

For example:

Month: 2026-09
Engineering AI tasks:             120
Local:
    tasks                           82
    percentage                    68%
    API expenditure                 €0
Augment:
    tasks                           38
    percentage                    32%
    expenditure                  €XXX
Estimated all-Augment cost:      €YYY
Actual AI expenditure:           €XXX
Estimated saving:                €ZZZ

This turns local LLM adoption into a measurable engineering investment.

⸻

# 28. Local Operating Cost

Local inference should not literally be recorded as zero cost.

Track at least:

electricity
hardware depreciation
storage
maintenance time
setup time

For day-to-day routing decisions these costs can initially be simplified.

The key distinction is:

Local inference:
low marginal cost
Cloud inference:
variable marginal cost

That is the economic advantage we are exploiting.

⸻

# 29. Model Routing

Qwen3-30B-A3B should be the first model, not necessarily the only model.

Eventually:

                   Eigent
                      │
                 Model Router
                      │
        ┌─────────────┼─────────────┐
        │             │             │
      Small          Qwen          Cloud
      model        30B-A3B         model
        │             │             │
      cheap          main         escalation
      fast           local

Example policy:

classification / formatting
        ↓
small local model
coding / reasoning
        ↓
Qwen3-30B-A3B
very difficult task
        ↓
Augment

This is a later optimization.

Do not introduce routing until the single-model implementation works reliably.

⸻

# 30. Context Is the Main Research Problem

The largest gap between the local stack and Augment is unlikely to be raw text generation.

It is likely to be:

repository context acquisition and retrieval.

Therefore experiments should explicitly investigate:

* repository indexing;
* semantic code search;
* symbol search;
* dependency graphs;
* Git history;
* documentation retrieval;
* embeddings;
* RAG;
* AST-based retrieval;
* language-server information;
* cross-repository context.

Long-term architecture may become:

                 Eigent
                    │
             Developer Agent
                    │
          ┌─────────┴─────────┐
          │                   │
      Local Qwen        Context Service
                              │
                   ┌──────────┼──────────┐
                   │          │          │
                 AST       embeddings   Git
                   │          │          │
                   └──────────┼──────────┘
                              │
                          repository

This should be considered a strategic workstream.

⸻

# 31. Security

All local services should default to:

127.0.0.1

rather than:

0.0.0.0

unless remote access is deliberately required.

Do not expose the local inference API directly to the public network.

Secrets should use:

environment variables
macOS Keychain
approved secret stores

Never commit:

API keys
tokens
credentials
private keys
personal access tokens

⸻

# 32. Logging

Every experiment should be reproducible.

Record:

timestamp
model
model version
quantization
runtime
runtime version
Eigent version
context size
generation settings
task
elapsed time
result
errors

Do not log secrets or sensitive source material unnecessarily.

⸻

# 33. Health Check

Provide:

scripts/healthcheck.sh

Conceptually it should verify:

[✓] model server running
[✓] API reachable
[✓] model loaded
[✓] test inference successful
[✓] Eigent reachable
[✓] disk space acceptable
[✓] memory pressure acceptable

The desired developer experience should eventually be:

./scripts/healthcheck.sh

followed by a clear status report.

⸻

#34. Start and Stop

Aim for:

./scripts/start-model.sh
./scripts/status.sh
./scripts/stop-model.sh

Eventually a higher-level command may start the complete local environment:

./scripts/start.sh

producing:

Starting local AI environment...
✓ model runtime
✓ Qwen3-30B-A3B
✓ API
✓ Eigent
Local AI environment ready.

Do not implement convenience wrappers until the underlying commands are understood and documented.

⸻

# 35. Reproducibility

The repository should contain enough information to rebuild the environment from scratch.

A successful implementation means:

fresh compatible Mac
       │
       ▼
clone repository
       │
       ▼
follow installation
       │
       ▼
download model
       │
       ▼
start services
       │
       ▼
run healthcheck
       │
       ▼
Eigent can perform repository task

No critical setup step should exist only in someone’s memory.

⸻

# 36. Implementation Order

Follow this order strictly:

1. Record baseline
        ↓
2. Install/test local Qwen
        ↓
3. Benchmark local runtimes
        ↓
4. Select serving runtime
        ↓
5. Standardize local API
        ↓
6. Install Eigent
        ↓
7. Connect Eigent → local Qwen
        ↓
8. Add repository access
        ↓
9. Add shell/test capabilities
        ↓
10. Add MCP integrations
        ↓
11. Define agent roles
        ↓
12. Benchmark against Augment
        ↓
13. Define escalation policy
        ↓
14. Measure savings
        ↓
15. Optimize context retrieval

Do not begin by constructing the complete architecture.

Each step must leave behind a working system.

⸻

# 37. First Milestone

The first milestone is deliberately modest.

Milestone M1 — Local Coding Model

Demonstrate:

Mac mini M4 Pro
      │
      ▼
local runtime
      │
      ▼
Qwen3-30B-A3B
      │
      ▼
OpenAI-compatible localhost API
      │
      ▼
coding response

Acceptance criteria:

* reproducible installation;
* stable inference;
* documented model;
* documented quantization;
* documented memory use;
* documented tokens/sec;
* API health check works.

⸻

# 38. Second Milestone

Milestone M2 — Eigent Local Agent

Demonstrate:

Eigent
   │
   ▼
Local API
   │
   ▼
Qwen

Acceptance criteria:

* no paid model required for test;
* Eigent can invoke Qwen;
* multi-turn interaction works;
* configuration survives restart;
* installation is documented.

⸻

#39. Third Milestone

Milestone M3 — Repository Task

Demonstrate:

Eigent
   │
   ├── Qwen
   │
   └── repository
          │
          ▼
      inspect code
          │
          ▼
      propose change
          │
          ▼
       run tests

Use a disposable branch.

The output must result in an inspectable Git diff.

⸻

# 40. Fourth Milestone

Milestone M4 — Augment Bake-Off

Complete ten representative tasks using both environments.

Produce:

benchmarks/results/<date>/

containing:

local-results.md
augment-results.md
comparison.md
cost-analysis.md

The final report should answer:

What percentage of current development work can be moved to the local stack without unacceptable loss of quality or productivity?

⸻

# 41. Fifth Milestone

Milestone M5 — Local-First Workflow

Based on benchmark evidence, adopt:

                   New task
                       │
                       ▼
                Classification
                  /          \
             suitable       unsuitable
                │               │
                ▼               ▼
             Eigent          Augment
                │
             success?
             /      \
           yes       no
            │         │
            ▼         ▼
          Done      Augment

This marks the transition from experimentation to operational use.

⸻

# 42. Success Criteria

The project is successful when:

* local Qwen inference is reliable;
* Eigent can use the local model;
* Eigent can inspect real repositories;
* agents can execute controlled development tools;
* generated changes can be tested;
* the workflow remains human-supervised;
* Augment remains available as escalation;
* representative tasks are benchmarked;
* cost and reviewer effort are measured;
* a meaningful percentage of paid Augment usage is replaced;
* developer productivity does not materially decline.

⸻

# 43. Non-Goals

Initially, do not attempt to:

* replace Augment completely;
* reproduce the entire Augment Context Engine;
* build a custom LLM;
* train Qwen;
* construct a large multi-agent organization;
* expose local inference publicly;
* automate production deployments;
* allow autonomous pushes to important repositories;
* optimize every possible model;
* build a sophisticated model router.

These can be considered after the core hypothesis has been proven.

⸻

# 44. Guiding Principle

The architecture should remain deliberately modular:

Agent layer
    Eigent
       │
       ▼
Inference contract
    OpenAI-compatible API
       │
       ▼
Runtime layer
    MLX / Ollama / LM Studio / other
       │
       ▼
Model layer
    Qwen / future models

And separately:

Premium engineering path
        │
        ▼
Augment Code Intent

Every layer should be replaceable without rebuilding the entire stack.

⸻

# 45. Expected End State

The eventual development environment should feel approximately like this:

                       DEVELOPER
                           │
                           ▼
                  Engineering Task
                           │
                           ▼
                     Local First
                           │
                           ▼
                        Eigent
                    ┌──────┴──────┐
                    │             │
                 Agents          MCP
                    │             │
                    ▼             ▼
                  Qwen        Repository
                    │          Git / Shell
                    ▼
                 M4 Pro
                    │
                    ▼
                acceptable?
                 /       \
               yes        no
                │          │
                ▼          ▼
              Done      Augment
                           │
                           ▼
                    Context Engine
                           │
                           ▼
                      Cloud model

The local machine therefore becomes an AI engineering compute resource, rather than merely the computer from which cloud AI services are accessed.

⸻

# 46. Decision

Proceed with the architecture.

Specifically:

1. retain Augment Code Intent;
2. establish Qwen3-30B-A3B as the first local-model candidate;
3. evaluate MLX-based serving first on Apple Silicon;
4. maintain an OpenAI-compatible API boundary where possible;
5. introduce Eigent only after local inference is stable;
6. use Eigent as the agent and orchestration layer;
7. introduce repository and tool access incrementally;
8. retain human approval for consequential operations;
9. perform a controlled local-versus-Augment bake-off;
10. use measured results to establish a local-first routing policy.

The central hypothesis is:

A substantial portion of routine AI-assisted software engineering can be executed locally on the Mac mini at very low marginal inference cost, while Augment Code Intent can be reserved for the smaller subset of tasks where premium repository context and cloud-model capability justify their variable cost.

If the benchmark confirms that hypothesis, the architecture should substantially reduce recurring AI development expenditure while simultaneously creating a reusable, private and increasingly capable local agent infrastructure.

⸻

# 47. Immediate Next Action

Do not start with Eigent.

Start by proving the lowest layer:

Qwen3-30B-A3B
        +
Apple M4 Pro / 24 GB
        +
MLX
        +
OpenAI-compatible API

Once that is stable and benchmarked, connect Eigent.

The first concrete implementation deliverable should therefore be:

experiments/
└── qwen3-30b-a3b-mlx/
    ├── README.md
    ├── install.sh
    ├── start.sh
    ├── test.sh
    └── results.md

results.md should capture:

model variant
quantization
model size
peak memory
load time
time-to-first-token
tokens/second
tested context sizes
stability
coding quality observations

Only after this experiment passes should the implementation proceed upward toward Eigent.

⸻

# References

* Eigent: https://www.eigent.ai/
* Eigent GitHub repository: https://github.com/eigent-ai/eigent
* Eigent — Augment Code Alternative: https://www.eigent.ai/blog/augment-code-alternative
* Qwen3-30B-A3B: https://huggingface.co/Qwen/Qwen3-30B-A3B
* MLX: https://github.com/ml-explore/mlx
* MLX-LM: https://github.com/ml-explore/mlx-lm
* MLXServe: https://mlxserve.com/
* Augment Code: https://www.augmentcode.com/

⸻

End of memo.
