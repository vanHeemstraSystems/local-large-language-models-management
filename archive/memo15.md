# Memo 15: Model Routing — The Good-Enough Model Principle

Repository: Local Large Language Models Management
Status: Proposed
Date: 2026-10-06
Related components: Jev, Model Selection, Local LLM Runtime, Agent Execution, Evaluation, Cost Management

⸻

1. Context

A common approach to using LLMs is to select the strongest available model and use it for every task.

This is often economically and operationally inefficient.

Many tasks do not require the strongest model available. Boilerplate generation, simple code modifications, repetitive agent operations, formatting, straightforward transformations, and other predictable tasks may be completed successfully by a considerably cheaper or locally hosted model.

The relevant question therefore should not be:

Which LLM is the best?

Instead:

Which is the least expensive model that has a sufficiently high probability of completing this particular task correctly?

This memo proposes adopting that principle throughout Local Large Language Models Management.

⸻

2. Source

The principle was prompted by an email from Tim discussing his comparison of Kimi K3 and Claude for coding tasks.

Referenced video:

* Tim — Kimi K3 vs Claude coding comparison
    https://www.youtube.com/watch?v=mq-rVs7oUXw

The email’s key observation is that Kimi K3 produced results surprisingly close to Claude on a number of coding tasks, while offering a different cost/speed profile.

The important architectural conclusion is not that Kimi K3 should replace Claude.

The important conclusion is that different tasks justify different models.

⸻

3. Principle

Adopt the following routing principle:

Use the least expensive model that has a sufficiently high probability of completing the task correctly. Escalate when evidence indicates that additional capability is required.

Model selection should therefore be treated as a routing problem rather than a permanent model preference.

                         TASK
                           │
                           ▼
                    ┌─────────────┐
                    │     Jev     │
                    │ Model Router│
                    └──────┬──────┘
                           │
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
        Local Qwen       Kimi K3       Claude
        low/no API       low-cost      high-cost
             │             │             │
             └─────────────┼─────────────┘
                           ▼
                    ┌─────────────┐
                    │  Evaluator  │
                    └──────┬──────┘
                           │
                 ┌─────────┴─────────┐
                 ▼                   ▼
              SUCCESS              FAILURE
                 │                   │
                 ▼                   ▼
                DONE              ESCALATE

⸻

4. Jev as Model Router

Jev should become responsible for selecting an appropriate model for each task.

The router should consider more than model intelligence.

Candidate routing dimensions include:

* task type
* task complexity
* required reasoning capability
* context size
* codebase size
* expected number of tool calls
* latency tolerance
* model availability
* API cost
* local execution cost
* historical success rate
* historical timeout rate
* historical correction rate
* verification requirements
* risk of an incorrect result

This creates a capability/cost decision, rather than a simple model ranking.

⸻

5. Candidate Model Portfolio

The initial portfolio should include:

Local Qwen

Current local model:

Qwen3-Coder-30B-A3B-Instruct-4bit

Current runtime:

MLXServe
127.0.0.1:11234

Primary advantages:

* no per-request API cost
* local/private execution
* excellent economics for repetitive workloads
* appropriate for experimentation and agent workloads
* potentially suitable for large numbers of calls

Current limitation:

* observed timeout/context limitations during coding workflows

The timeout problem should therefore be treated as a routing signal rather than evidence that the model has no value.

⸻

Kimi K3

Kimi K3 should be added as an experimental cloud/API candidate.

It should not automatically become the preferred model.

The purpose of adding it is to determine whether it occupies a useful point between:

Local Qwen
     │
     ▼
Kimi K3
     │
     ▼
Strong premium models

Its actual position must be established through measurements on representative workloads.

⸻

Claude

Claude should remain available as a high-capability fallback.

It is particularly appropriate when:

* architectural reasoning is difficult
* the codebase is large
* the task is ambiguous
* an incorrect implementation would be expensive
* repeated local attempts have failed
* verification indicates that the lower-cost model is not succeeding

The goal is not to eliminate Claude.

The goal is to avoid spending Claude-level cost when Claude-level capability is unnecessary.

⸻

6. Routing Examples

Simple task

Task:
Rename a variable across one file.
Preferred:
Local Qwen

There is little reason to pay for a premium model.

⸻

Repetitive agent workload

Task:
Agent performs hundreds of predictable repository operations.
Preferred:
Local Qwen or inexpensive API model

The economics become especially important because even a small per-call difference compounds across hundreds or thousands of calls.

⸻

Complex debugging

Task:
Diagnose a subtle architectural failure involving multiple
modules and asynchronous runtime behaviour.
Preferred:
Strong model

The expected cost of an incorrect answer is high enough to justify a stronger model.

⸻

Failed local attempt

Qwen
  │
  ├── timeout
  ├── compilation failure
  └── tests fail
          │
          ▼
       Jev escalation
          │
          ▼
       Kimi K3
          │
          ▼
       Claude if necessary

This is preferable to repeatedly asking the same model to solve a problem it has already demonstrated difficulty with.

⸻

7. Evaluation Before Escalation

Model routing should be evidence-based.

A model response should ideally be evaluated using deterministic signals wherever possible.

For coding tasks these may include:

* compilation
* linting
* unit tests
* integration tests
* type checking
* repository-specific validation
* diff inspection
* tool-call success
* timeout detection
* patch size
* regression detection

A successful model response should therefore mean:

The requested outcome was successfully verified.

Not merely:

The model produced a plausible-looking answer.

⸻

8. Historical Model Performance

Jev should eventually maintain model performance statistics.

Example:

model: local-qwen
task_class: single_file_code_change
statistics:
  attempts: 100
  successful: 91
  failed: 9
  timeouts: 4
  escalations: 9
  average_latency_seconds: 38

This enables adaptive routing.

If Qwen succeeds on 91% of a task category, Jev should have a strong reason to try Qwen first.

If another model succeeds on 99% but costs substantially more, the router can make an explicit economic decision.

⸻

9. Expected Cost

Routing should consider expected total task cost, not merely model price.

Conceptually:

Expected Cost =
    model_cost
  + expected_retry_cost
  + expected_escalation_cost
  + expected_human_correction_cost
  + expected_delay_cost

A more expensive model can therefore be cheaper overall if it dramatically reduces failures.

Conversely, a cheap model can be preferable when its success probability is already sufficiently high.

⸻

10. Model Selection Should Be Dynamic

Model routing must not be based permanently on today’s model hierarchy.

Models change rapidly.

A model that is currently considered inexpensive or mediocre may become highly capable.

A model that is currently excellent may become economically unattractive.

Therefore the architecture should represent models as interchangeable providers with measured capabilities.

                    ┌───────────────┐
                    │      Jev      │
                    └───────┬───────┘
                            │
                     Model Selection
                            │
        ┌───────────┬───────┼───────┬───────────┐
        ▼           ▼       ▼       ▼           ▼
      Qwen        Kimi    Claude   Other      Human
      Local        API      API     Models     Review

The routing policy should remain stable even when individual models are replaced.

⸻

11. Benchmarking Strategy

Before promoting Kimi K3 into production routing, benchmark it against existing candidates.

Use identical prompts and identical repositories where possible.

Suggested benchmark dimensions:

Dimension	Measurement
Correctness	Tests / evaluator
Code quality	Static + human review
Latency	Seconds
API cost	€ / task
Tool reliability	Successful tool calls
Context handling	Maximum useful context
Timeout rate	%
Retry rate	%
Escalation rate	%
Human correction	Minutes/task
Overall task cost	€ / successful task

The most important metric should be:

Cost per successfully completed task

rather than cost per API call.

⸻

12. Benchmark Workloads

The benchmark should use realistic Local LLM Management and Open Engineering workloads rather than generic benchmark prompts.

Candidate workloads:

1. Single-file code modification
2. Multi-file refactoring
3. Test creation
4. Bug diagnosis
5. Repository exploration
6. Architecture analysis
7. Documentation generation
8. Repetitive agent operation
9. Tool-driven implementation
10. Memo implementation
11. Code Smell Detective work
12. Open Engineering Architecture changes

Each task should be executed against multiple candidate models.

⸻

13. Relationship to Local-First Strategy

This principle strengthens rather than weakens the Local LLM strategy.

The objective is not:

Always use a local model.

The objective is:

Use local inference whenever it provides an acceptable probability of successful completion, and escalate when doing so is economically or technically justified.

This gives local inference a natural first-class position without turning it into a dogmatic requirement.

⸻

14. Recommended Routing Policy

Initial policy:

1. Classify task.
2. Estimate:
   - complexity
   - risk
   - context requirements
   - expected tool calls
   - verification availability
3. Determine cheapest viable model.
4. Prefer local Qwen when:
   - task complexity is low/moderate
   - verification is available
   - latency is acceptable
   - historical success rate is sufficient
5. Prefer inexpensive API models such as Kimi K3 when:
   - local execution is unsuitable
   - task does not justify premium-model cost
   - benchmark results demonstrate sufficient quality
6. Prefer strong premium models when:
   - task complexity is high
   - failure cost is high
   - ambiguity is high
   - local/low-cost attempts fail
7. Verify the result.
8. Escalate when verification fails.
9. Record the outcome.
10. Feed performance data back into Jev.

⸻

15. Important Architectural Consequence

Jev should not simply contain a static rule such as:

hard → Claude
easy → Qwen

Instead, Jev should evolve toward:

Task
  ↓
Classification
  ↓
Candidate models
  ↓
Expected success/cost calculation
  ↓
Model selection
  ↓
Execution
  ↓
Verification
  ↓
Success?
  ├── yes → record outcome
  └── no  → escalate

This creates a feedback loop:

          ┌──────────────────────────────┐
          │                              │
          ▼                              │
      Task → Jev → Model → Result → Evaluation
              ▲                         │
              │                         │
              └──── Performance data ───┘

Over time, the system should become better at determining which model is appropriate for which type of work.

⸻

16. Decision

Adopt the Good-Enough Model Principle.

Add Kimi K3 to the Local LLM Management model portfolio as an experimental candidate.

Do not replace Claude.

Do not assume Kimi K3 is superior to the current local Qwen strategy.

Instead, establish a benchmark and allow Jev to determine whether Kimi K3 provides a meaningful cost/capability middle tier.

The strategic objective is:

Maximum useful engineering output per euro, while preserving the ability to escalate to stronger intelligence when the task requires it.

⸻

17. References

Primary reference

Tim — Kimi K3 vs Claude coding comparison:

https://www.youtube.com/watch?v=mq-rVs7oUXw

Related concepts

* Jev model routing and LLM selection
* Local Qwen3-Coder deployment via MLXServe
* Local LLM timeout investigation
* Cost-aware agent execution
* Verification-driven escalation
* Local-first AI engineering

⸻

18. Proposed Follow-up

Create a Jev Model Routing Benchmark that runs identical representative tasks against:

Local Qwen
Kimi K3
Claude

and records:

correctness
latency
cost
timeouts
retries
escalations
human corrections
cost per successful task

Use these results to establish the first empirical Jev routing policy.

The long-term goal is not to find the best LLM.

It is to build a system that reliably chooses the right LLM for each task.
