## Memo 17: OpenCode Go with Kimi K3

Status: Proposed
Date: 2026-10-06
Target: Local LLMs Management
Decision area: Hosted model escalation / OpenCode integration

1. Objective

Evaluate whether subscribing to OpenCode Go and selecting Kimi K3 can provide hosted Kimi coding capability inside OpenCode without also subscribing separately to Kimi Code.

The goal is to minimize AI subscription costs while maintaining a practical escalation path when local models are insufficient.

2. Conclusion

Yes.

If OpenCode Go provides Kimi K3 through the OpenCode Go provider, a separate Kimi Code subscription is not required merely to use Kimi K3 from OpenCode.

The proposed configuration is:

OpenCode
   │
   └── OpenCode Go
          │
          └── Kimi K3

Kimi Code is therefore an alternative access route rather than a prerequisite for Kimi K3 through OpenCode Go.

3. Important distinction

There are three different ways Kimi models can potentially be used with OpenCode:

A. OpenCode Go

OpenCode
   ↓
OpenCode Go
   ↓
Kimi K3

This uses the OpenCode Go subscription and its included model access.

Additional Kimi Code subscription: not required.

B. Kimi Code

OpenCode
   ↓
Kimi Code
   ↓
Kimi model

This uses Kimi’s own coding service/subscription.

OpenCode Go subscription: not required for this route.

C. Kimi API / pay-per-token

OpenCode
   ↓
Kimi API
   ↓
Kimi model

This is usage-based rather than subscription-based.

For the Local LLMs Management cost-reduction strategy, this route should generally be treated cautiously because sustained coding workloads can make token-based billing less predictable.

4. Recommended role in the Local LLM architecture

Kimi K3 through OpenCode Go should be treated as a hosted escalation model, not as a replacement for the local model.

Proposed routing:

                     ┌──────────────────────┐
                     │       OpenCode       │
                     └──────────┬───────────┘
                                │
                         model routing
                                │
                ┌───────────────┴───────────────┐
                │                               │
        ┌───────▼────────┐             ┌────────▼────────┐
        │ Local Qwen      │             │ OpenCode Go     │
        │ Qwen3-Coder     │             │ Kimi K3         │
        │ 30B-A3B 4-bit   │             │ hosted          │
        └─────────────────┘             └─────────────────┘
                │                               │
          default work                    escalation
          low marginal cost              difficult work

The local Qwen model remains the preferred first-line model for tasks that can be handled locally.

Kimi K3 becomes a hosted fallback for tasks where additional model capability, reasoning quality, context handling, or coding performance justifies using the paid hosted service.

5. Why this fits the existing strategy

The objective of Local LLMs Management is not to use the strongest model for every prompt.

Instead:

Use the cheapest capable model first and escalate only when necessary.

This makes OpenCode Go particularly interesting because it can provide access to a strong hosted coding model through the same OpenCode workflow without requiring a second Kimi subscription.

The resulting strategy can therefore be:

1. Local Qwen — default.
2. Kimi K3 via OpenCode Go — hosted escalation.
3. Other hosted providers — additional escalation when justified.
4. Human review — final escalation for unresolved or high-risk tasks.

6. Subscription decision

If the primary requirement is:

“I want Kimi K3 available inside OpenCode without paying Kimi separately.”

then the preferred configuration is:

Subscribe to OpenCode Go and use Kimi K3 through the OpenCode Go provider.

Do not purchase a separate Kimi Code subscription solely for this purpose.

A separate Kimi subscription should only be considered if Kimi’s own service is required independently of OpenCode, or if its separate limits/features provide sufficient additional value.

7. Cost-management principle

Avoid duplicating subscriptions that provide substantially overlapping access.

For example, this should not be the default:

OpenCode Go
      +
Kimi Code
      +
Kimi API

unless there is a demonstrated need for all three.

Prefer:

Local models
     +
OpenCode Go / Kimi K3

and add another paid provider only when an actual workload demonstrates the need.

8. Verification before committing

Before making the subscription permanent, verify the current OpenCode Go terms for:

* Kimi K3 availability.
* Included usage/quota.
* Context limits.
* Rate limits.
* Whether Kimi K3 is available for the intended OpenCode coding workflow.
* What happens after the included quota is exhausted.
* Whether model availability or included models can change over time.

The configuration should be periodically re-evaluated because hosted model offerings and subscription terms can change.

9. References

OpenCode Go

OpenCode Go documentation:

https://dev.opencode.ai/docs/go/

The documentation describes OpenCode Go and its supported models, including Kimi K3.

Kimi Code / OpenCode integration

Kimi documentation for using Kimi Code with OpenCode:

https://www.kimi.com/code/docs/en/third-party-tools/opencode.html

This documents the alternative integration in which OpenCode connects to Kimi’s own coding service.

10. Decision

Recommended:

Use OpenCode Go + Kimi K3 as the hosted escalation layer for the Local LLMs Management architecture, and do not maintain a separate Kimi Code subscription unless an independent Kimi requirement emerges.

This keeps the architecture simple and supports the broader objective of reducing unnecessary AI subscription and token costs while retaining access to a capable hosted coding model.

⸻

Related Local LLMs Management concepts

* Local-first model routing
* Hosted-model escalation
* Cost-aware model selection
* OpenCode integration
* Kimi K3
* Qwen3-Coder-30B-A3B-Instruct-4bit
* Prompt/task-based model selection
* Jev-based LLM routing
* Human escalation
