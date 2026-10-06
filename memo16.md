Memo: Kimi Integration with OpenCode

Status: Proposed
Repository: Local LLMs Management
Date: 2026-10-06
Decision: Add Kimi as a subscription-based cloud escalation provider for OpenCode; do not replace the local Qwen model and do not use the pay-per-token Moonshot API for the default workflow.

⸻

1. Context

Local LLMs Management is being developed around a cost-conscious model-routing strategy:

1. Prefer a capable local model when practical.
2. Escalate to a stronger cloud model when the local model is unsuitable, fails, times out, or reaches a capability boundary.
3. Avoid unnecessary pay-per-token costs.
4. Keep OpenCode as the coding agent/orchestrator rather than introducing multiple competing coding agents.
5. Eventually allow an automated routing component such as Jev to select the appropriate model for each task.

The current local coding model is:

* Qwen3-Coder-30B-A3B-Instruct-4bit
* Served locally through MLXServe on the Mac mini.
* Used by OpenCode and related development workflows.

Kimi provides an attractive cloud escalation tier because Kimi coding models can be used through OpenCode’s provider system, while subscription-based access avoids making every escalation a separate pay-per-token purchase.

⸻

2. Decision

Integrate Kimi through OpenCode’s subscription-based offering as a cloud model provider.

Do not make Kimi the default model.

The preferred architecture is:

                         OpenCode
                            │
                    Model Routing Layer
                            │
          ┌─────────────────┼──────────────────┐
          │                 │                  │
        LOCAL             CLOUD              HUMAN
          │                 │                  │
 Qwen3-Coder-30B       Kimi coding models    Review /
    MLXServe          via OpenCode Go       escalation
          │                 │                  │
          └─────────────────┼──────────────────┘
                            │
                      Coding result

OpenCode remains the agent. Qwen and Kimi are models available to that agent.

⸻

3. Why Kimi

Kimi is useful as an escalation tier because it provides access to strong coding models without requiring the Local LLMs Management architecture to abandon local inference.

The important distinction is:

OpenCode is the coding agent; Kimi is a model provider.

The Kimi coding agent/CLI does not need to be introduced into the workflow.

This keeps the architecture provider-neutral and allows Local LLMs Management to make model selection independently from the agent implementation.

⸻

4. Subscription versus pay-per-token

The Moonshot Open Platform API provides pay-per-token access to Kimi models.

That is not the preferred solution for this project.

The preferred route is subscription-based access through OpenCode’s supported Kimi offering.

This aligns with the project’s objective of making AI expenditure predictable while reducing unnecessary per-token expenditure.

Therefore:

Preferred:
OpenCode
   │
   └── OpenCode Go
          │
          └── Kimi coding models
Not preferred as default:
OpenCode
   │
   └── Moonshot API
          │
          └── pay-per-token Kimi

The pay-per-token API can remain a potential future option for specialised workloads, but should not become the normal escalation path.

⸻

5. Proposed model hierarchy

The initial routing hierarchy should be:

                    Coding task
                         │
                         ▼
                  Local Qwen first
                         │
             ┌───────────┴───────────┐
             │                       │
          succeeds                fails
             │                       │
             ▼                       ▼
           Done              Escalate to Kimi
                                     │
                          ┌──────────┴──────────┐
                          │                     │
                    lower complexity       high complexity
                          │                     │
                          ▼                     ▼
                     Kimi Code              Kimi K3
                          │                     │
                          └──────────┬──────────┘
                                     │
                                  failure
                                     │
                                     ▼
                                Human review

The exact model ordering should remain configurable rather than hard-coded.

⸻

6. Local-first principle

The existence of a strong cloud model must not undermine the local-first objective.

Local Qwen should remain the preferred model whenever it satisfies the task.

Advantages include:

* no additional per-request cloud cost;
* local execution;
* better control over source-code privacy;
* independence from cloud connectivity;
* predictable infrastructure costs;
* continued development of the local inference stack.

Kimi should therefore be considered an escalation mechanism, not a replacement.

⸻

7. Escalation triggers

Local LLMs Management should eventually be able to escalate from Qwen to Kimi based on measurable conditions.

Potential triggers include:

Capability

The task requires capabilities beyond the locally available model.

Examples:

* very complex multi-file refactoring;
* difficult debugging;
* sophisticated architectural reasoning;
* large repository comprehension;
* tasks requiring stronger coding/reasoning performance.

Runtime failure

Examples:

* inference timeout;
* OpenCode timeout;
* MLXServe failure;
* model crash;
* context-length failure;
* insufficient output capacity.

Quality failure

Examples:

* generated patch does not compile;
* tests fail;
* repeated correction attempts fail;
* model enters an unproductive loop;
* repository validation rejects the result.

Resource constraints

Examples:

* local context window is insufficient;
* available RAM is insufficient;
* local inference becomes impractically slow.

⸻

8. Kimi should not hide local-model failures

An important architectural principle is that escalation should not simply conceal problems with the local stack.

For example:

Qwen timeout
    │
    ├── record failure
    ├── classify failure
    ├── collect diagnostics
    │
    └── escalate to Kimi

This allows Local LLMs Management to continuously improve the local environment.

The goal is therefore:

Use Kimi to keep the coding workflow productive while using every escalation to learn how to make the local stack better.

⸻

9. Relationship with Jev

This integration provides a concrete target for the planned model-selection layer.

Jev can eventually evaluate a task and select between:

Qwen local
Kimi coding model
Kimi higher-capability model
Human review

The routing decision could consider:

* task complexity;
* repository size;
* expected context size;
* programming language;
* requested operation;
* local model availability;
* previous model failures;
* estimated execution time;
* quality requirements;
* subscription availability;
* cost policy.

The router should return a model-selection decision, rather than directly implementing the coding task.

⸻

10. Recommended future architecture

                         User
                           │
                           ▼
                       OpenCode
                           │
                           ▼
                    Model Router / Jev
                           │
             ┌─────────────┼─────────────┐
             │             │             │
             ▼             ▼             ▼
        Local Qwen      Kimi Code      Kimi K3
        MLXServe       OpenCode Go    OpenCode Go
             │             │             │
             └─────────────┼─────────────┘
                           │
                           ▼
                    Validation layer
                           │
             ┌─────────────┴─────────────┐
             │                           │
           pass                        failure
             │                           │
             ▼                           ▼
           Done                    Retry / Escalate
                                         │
                                         ▼
                                  Human review

This architecture keeps model selection separate from coding orchestration and validation.

⸻

11. OpenCode configuration

OpenCode provides provider authentication and model selection.

The intended operational flow is:

opencode auth login
        │
        ▼
select Kimi / OpenCode Go
        │
        ▼
authenticate subscription
        │
        ▼
opencode
        │
        ▼
/models

The exact model availability should be checked against the active OpenCode subscription because model availability and usage allowances can change over time.

⸻

12. Important distinction

Kimi should not be treated as another agent in the architecture.

Agent

OpenCode

Responsible for:

* interacting with the repository;
* executing coding workflows;
* invoking tools;
* applying changes;
* running tests;
* managing the coding session.

Models

Examples:

* Qwen3-Coder locally;
* Kimi coding models through OpenCode.

Responsible for:

* reasoning;
* code generation;
* debugging;
* analysis.

This separation is important because it allows the model-routing layer to evolve without replacing the coding agent.

⸻

13. Cost policy

The preferred cost policy is:

1. Local inference
2. Included subscription capacity
3. Additional cloud expenditure only when explicitly justified
4. Human intervention when automated escalation is no longer economical

The system should therefore prefer subscription-based Kimi access over pay-per-token Moonshot access for routine escalation.

Any future pay-per-token provider should require an explicit routing policy before being used automatically.

⸻

14. Metrics

Local LLMs Management should record model-routing metrics.

Recommended metrics include:

* task type;
* selected model;
* reason for selection;
* local-model success/failure;
* execution time;
* timeout;
* context-length failure;
* validation result;
* retry count;
* escalation count;
* human intervention;
* estimated cloud usage;
* task completion quality.

This will allow the routing strategy to evolve based on evidence rather than intuition.

⸻

15. Success criteria

The Kimi integration is successful if:

1. OpenCode can use Kimi without introducing the Kimi agent/CLI.
2. Qwen remains the preferred local model.
3. Kimi can be selected as a cloud escalation model.
4. Local failures can trigger controlled escalation.
5. Subscription-based Kimi access avoids unnecessary pay-per-token expenditure.
6. Routing decisions can eventually be delegated to Jev.
7. Model selection remains independent from OpenCode’s coding-agent implementation.
8. Routing and validation metrics allow continuous improvement of the local stack.

⸻

16. Architectural principle

The resulting principle for Local LLMs Management is:

Use the cheapest capable model first, escalate only when necessary, and keep the agent independent from the model.

For the current stack this means:

OpenCode orchestrates. Qwen executes locally by default. Kimi provides subscribed cloud escalation. Jev eventually decides which model is appropriate. Human review remains the final escalation path.

⸻

References

OpenCode — Providers

OpenCode documentation describing provider configuration and model selection:

https://opencode.ai/docs/providers/

OpenCode — Go

OpenCode documentation for the subscription-based Go offering and its supported models:

https://dev.opencode.ai/docs/go/

OpenCode

Official OpenCode project:

https://opencode.ai/

Moonshot AI / Kimi

Official Kimi platform documentation for Kimi models and API access:

https://platform.moonshot.ai/

Kimi

Official Kimi website:

https://www.kimi.com/

⸻

Related Local LLMs Management work

This memo should be considered together with:

* the local Qwen3-Coder / MLXServe configuration;
* the Local LLM timeout investigation;
* the model-routing strategy;
* the Jev model-selection investigation;
* the OpenCode + Warp workflow;
* the cost-reduction strategy for AI coding services.

These should ultimately converge into one model-routing architecture rather than separate provider-specific solutions.
