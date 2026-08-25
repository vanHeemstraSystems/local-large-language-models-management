# Memo 6: Stabilising OpenAI-Compatible Tool Calling for MLXServe, Qwen3-Coder and OpenCode

Status: Investigation / implementation guidance
Date: 25 August 2026
Scope: Local LLM tool calling on Apple Silicon using Qwen3-Coder, MLX/MLXServe and OpenCode

#€ 1. Purpose

Our local development stack currently follows approximately this path:
```
OpenCode
   │
   │ OpenAI-compatible API
   ▼
MLXServe / mlx_lm.server
   │
   ▼
Qwen3-Coder-30B-A3B-Instruct-4bit
```
Normal inference works successfully.

The remaining blocker is reliable agentic/tool-calling operation.

We observed responses in which:
```
{
  "tool_calls": [
    {
      "id": null,
      "type": "function",
      "function": {
        "name": "...",
        "arguments": "..."
      }
    }
  ]
}
```
OpenCode expects an OpenAI-compatible tool-call structure with a usable tool-call ID. A null ID causes the agentic interaction to fail.

New upstream information substantially narrows where this problem should be solved and changes our preferred strategy.

The primary conclusion is:

Do not patch Qwen3-Coder or OpenCode first. Treat MLX’s OpenAI-compatibility boundary as the primary place to investigate and correct the behaviour.

Furthermore, current upstream mlx-lm already contains code intended to generate a tool-call ID when the model/parser does not supply one. This means our first objective is to determine why our running stack is nevertheless producing id: null.

⸻

## 2. New Finding: Current mlx_lm.server Already Handles Missing IDs

The most important new information comes from the current upstream implementation of mlx_lm.server.

Its ToolCallFormatter contains logic equivalent to:

tc_id = tc.pop("id", None) or str(uuid.uuid4())

and subsequently constructs:

{
    "function": tc,
    "type": "function",
    "id": tc_id,
}

For streaming responses it additionally supplies an index.

Reference:

* mlx-lm server.py

This is highly significant.

It means current upstream MLX explicitly recognizes that a model/parser may produce a tool call without an ID and compensates for that at the OpenAI compatibility boundary. (GitHub)

Therefore, under current upstream behaviour:

Qwen3 tool call
      │
      ▼
MLX tool parser
      │
      │ possibly no ID
      ▼
ToolCallFormatter
      │
      ├── missing ID?
      │       │
      │       └── generate UUID
      │
      ▼
OpenAI-compatible tool_call
      │
      └── id != null

This is almost exactly the behaviour required by OpenCode.

Our observed id: null therefore requires explanation.

⸻

3. Revised Root-Cause Hypothesis

Previously it was reasonable to suspect that Qwen3 simply failed to generate a field required by OpenCode.

That is now too simplistic.

A model-native tool call does not necessarily need to contain every piece of OpenAI protocol metadata. The compatibility server can normalize model-native output into the API contract expected by its client.

The likely failure is therefore somewhere in:

Qwen3-Coder
     │
     ▼
Qwen3 tool-call syntax
     │
     ▼
MLX parser
     │
     ▼
MLX ToolCallFormatter
     │
     ▼
MLXServe
     │
     ▼
SSE / OpenAI response
     │
     ▼
OpenCode

The immediate question is:

Is the version of mlx-lm actually used by MLXServe running the current ToolCallFormatter implementation?

There are several plausible explanations.

Hypothesis A — MLXServe contains an older mlx-lm

The MLXServe installation may depend on a version of mlx-lm predating the missing-ID fix.

If so, upgrading the dependency may solve the problem without maintaining any custom patch.

This is the preferred outcome.

Hypothesis B — MLXServe bypasses or modifies ToolCallFormatter

MLXServe may provide another OpenAI compatibility/streaming layer.

In that case upstream mlx_lm.server could generate a valid ID but MLXServe could subsequently lose, replace or reconstruct the object.

Hypothesis C — the streaming path behaves differently

The ID may exist in the non-streaming representation but be absent or malformed in one or more SSE deltas.

Since OpenCode operates agentically and consumes streamed responses, this distinction matters.

Hypothesis D — parser failure occurs before normalisation

There are known MLX issues where tool parsers reject otherwise meaningful model output. Current ToolCallFormatter catches parser errors and can discard the call rather than necessarily failing the HTTP request.

A July 2026 Qwen3-Coder issue demonstrates exactly this broader class of problem: an argument represented as 140.0 where an integer was expected caused the parser to reject the tool call. The server then returned a response indicating finish_reason: "tool_calls" without a usable tool call, causing an agent client to loop. (GitHub)

This tells us that ID normalization is important, but not sufficient. The entire model-native → OpenAI transformation must be robust.

⸻

4. What MLX Issue #607 Tells Us

Relevant upstream issue:

* mlx-lm #607 — mlx_lm.server crashes when tool_calls aren’t JSON

Issue #607 involved Codex/OpenCode clients and a GLM model.

The model generated a tool invocation using its own XML-like representation rather than the JSON representation expected by the server.

The server attempted to parse that representation as JSON, resulting in a JSONDecodeError and termination of the request. (GitHub)

The issue is closed against #711.

This is not exactly our id: null bug.

However, it confirms the architectural problem that matters to us:

Model-native tool representation
             │
             ▼
      MLX parser/adapter
             │
             ▼
     OpenAI representation
             │
             ▼
        Agent client

The model and the agent client do not inherently speak exactly the same tool-calling dialect.

mlx_lm.server is therefore not merely an HTTP wrapper around inference.

It is an adapter.

That adapter must normalize the model’s representation into the protocol expected by OpenCode.

⸻

5. Missing IDs Are Already an Explicit MLX Concern

A second MLX issue provides particularly strong evidence.

Reference:

* mlx-lm #1375 — generated tool-call UUIDs conflict with Mistral templates

That issue reports that when a tool call arrives without an ID, mlx_lm.server generates one using:

str(uuid.uuid4())

The reported problem is actually that these generated IDs are too long for certain Mistral templates, which require nine-character alphanumeric IDs. (GitHub)

For our investigation, the important part is not the Mistral limitation.

The important part is that MLX upstream has already adopted this design:

If a model’s tool call does not provide an ID, the OpenAI compatibility server generates one.

That validates the architecture we want.

We therefore should not introduce Qwen-specific ID generation unless evidence shows it is unavoidable.

⸻

6. OpenAI Aborted Tool-Call Discussion

Reference:

* OpenAI Developer Community — handling aborted tool calls

This discussion describes a different but related problem.

A valid tool call can be persisted into conversation state, after which execution is interrupted before its corresponding tool result is recorded.

This creates:

assistant
    │
    └── tool_call(id=A)
             │
             X execution aborted
             │
             └── no tool result for A

Subsequent interaction may then fail because the conversation contains an orphaned tool call.

The discussion describes race conditions around repairing that state, and a later contribution points to an openai-python issue covering stream cancellation and conversation state becoming inconsistent. (OpenAI Developer Community)

This is useful background, but it should not be treated as the primary fix for our problem.

Our failure occurs earlier:

Qwen3
  │
  ▼
MLX
  │
  ▼
tool_call
  │
  └── id: null
           │
           ▼
        OpenCode
           X

Trying to repair conversation state after this would treat a symptom rather than fixing the protocol boundary.

The OpenAI discussion does, however, reinforce an important design requirement:

Tool-call identity must be valid and stable throughout the complete tool-call lifecycle.

⸻

7. Required Compatibility Contract

We should define the MLXServe/OpenCode boundary explicitly.

A tool call leaving our local inference server should satisfy at least:

tool_call
├── id
│   └── non-null and stable
│
├── type
│   └── "function"
│
├── function
│   ├── name
│   └── arguments
│       └── valid serialized JSON
│
└── index
    └── correct when streaming

The same ID must remain associated with the call during:

tool-call stream
       │
       ▼
assembled tool call
       │
       ▼
tool execution
       │
       ▼
tool result
       │
       └── tool_call_id = original ID

We should think of this as an invariant rather than an implementation detail.

⸻

8. Desired Architecture

The preferred architecture is:

┌──────────────────────────────┐
│ Qwen3-Coder                  │
│                              │
│ model-native tool syntax     │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Qwen3 Tool Parser            │
│                              │
│ understands model output     │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ Protocol Normalizer          │
│                              │
│ • tool-call ID               │
│ • function name              │
│ • JSON arguments             │
│ • streaming index            │
│ • stable streamed ID         │
│ • finish reason              │
│ • parser failure handling    │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ OpenAI-compatible API        │
│                              │
│ /v1/chat/completions         │
│ SSE streaming                │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ OpenCode                     │
└──────────────────────────────┘

The protocol normalizer should ideally be upstream mlx_lm.server, rather than software maintained by us.

⸻

9. Strategy

We should pursue the following options in order.

Strategy 1 — Upgrade, Don’t Patch

Preferred strategy.

Determine exactly which versions are running:

python - <<'PY'
import mlx_lm
print(mlx_lm.__version__)
PY

Also identify the MLXServe version and its dependency declaration for mlx-lm.

Then inspect the actual installed formatter:

python - <<'PY'
import inspect
import mlx_lm.server
print(inspect.getsource(mlx_lm.server.ToolCallFormatter))
PY

We specifically want to determine whether it contains:

tc_id = tc.pop("id", None) or str(uuid.uuid4())

If not, compare the installed version with current upstream MLX.

If a supported upgrade gives us the current implementation, upgrade and retest before making any source modifications.

Success condition

A streamed Qwen3-Coder tool call reaches OpenCode with:

{
  "id": "<non-null-value>",
  "type": "function",
  "function": {
    "name": "...",
    "arguments": "..."
  }
}

and OpenCode successfully executes the tool and continues the agent turn.

⸻

10. Strategy 2 — Determine Exactly Where the ID Disappears

If the installed ToolCallFormatter already generates IDs, instrument the pipeline.

Capture the tool call at four points:

1. Qwen/parser output
2. ToolCallFormatter output
3. MLXServe HTTP/SSE output
4. OpenCode received representation

This gives us a simple fault-isolation test.

If:

parser            id = None
formatter         id = UUID
HTTP/SSE          id = UUID
OpenCode          id = UUID

the ID problem is solved and another tool-calling incompatibility is responsible.

If:

formatter         id = UUID
HTTP/SSE          id = null

the problem is in MLXServe’s serialization/streaming layer.

If:

HTTP/SSE          id = UUID
OpenCode          id = null

investigate OpenCode.

We should only patch the component where the information is actually lost.

⸻

11. Strategy 3 — Minimal MLX Compatibility Patch

If upgrading is impossible and the installed formatter does not provide an ID, introduce the smallest possible patch at the MLX compatibility boundary.

Conceptually:

tc_id = tc.pop("id", None) or str(uuid.uuid4())

The critical requirement is that the generated ID is created once per logical tool call, not independently for every streamed chunk.

Incorrect:

delta 1 → UUID A
delta 2 → UUID B
delta 3 → UUID C

Correct:

logical tool call → UUID A
delta 1 → A
delta 2 → A
delta 3 → A
tool result → A

We should keep such a patch small enough that it can later be removed when MLXServe incorporates the relevant upstream behaviour.

⸻

12. Strategy 4 — Compatibility Proxy

Only introduce a proxy if MLXServe cannot be corrected cleanly.

The architecture would become:

OpenCode
   │
   ▼
OpenAI Compatibility Proxy
   │
   ├── validate tool calls
   ├── generate missing IDs
   ├── normalize arguments
   ├── preserve streaming IDs
   ├── validate indexes
   └── normalize finish reasons
   │
   ▼
MLXServe
   │
   ▼
Qwen3-Coder

This has one strategic advantage: it could normalize multiple local model families.

However, it also adds:

* another service;
* another failure point;
* additional maintenance;
* potential streaming complexity;
* possible latency.

Therefore:

Do not introduce a proxy merely to solve id: null if current MLX upstream already solves it.

A proxy becomes attractive only if we discover a broader and recurring incompatibility between OpenCode’s OpenAI expectations and multiple local inference backends.

⸻

13. Do Not Patch OpenCode First

OpenCode is correctly useful to us precisely because it can consume an OpenAI-compatible endpoint.

Making OpenCode tolerate malformed responses would invert responsibility:

Bad:
server violates contract
        │
        ▼
every client compensates

versus:

Preferred:
model-native output
        │
        ▼
server normalizes
        │
        ▼
standards-compatible clients

We want the latter.

This also means other OpenAI-compatible clients can subsequently use the same local endpoint.

⸻

14. Test Harness

Before declaring the problem solved, create a minimal repeatable interoperability test.

It should define a harmless tool such as:

{
  "type": "function",
  "function": {
    "name": "get_current_directory",
    "description": "Return the current working directory",
    "parameters": {
      "type": "object",
      "properties": {}
    }
  }
}

Ask Qwen3-Coder something that unambiguously requires the tool.

Test both:

stream = false

and:

stream = true

Validate:

1. a tool call is detected;
2. id exists;
3. id is non-null;
4. type == "function";
5. function name is correct;
6. arguments are valid JSON;
7. streaming deltas reconstruct one coherent call;
8. the ID remains stable;
9. the tool result references the same ID;
10. the model successfully processes the result;
11. OpenCode continues rather than aborting.

The streaming test is especially important because a non-streaming success does not prove that OpenCode’s normal operating path is fixed.

⸻

15. Add Protocol Regression Tests

Once fixed, capture the failure as a regression test.

At minimum test:

tool call without model-generated ID
tool call with model-generated ID
single tool call
multiple tool calls
streamed tool call
non-streamed tool call
empty arguments
structured arguments
parser rejection
aborted generation
tool execution failure
follow-up turn containing tool result

A particularly important assertion is:

assert tool_call["id"] is not None

For streaming:

assert all_observed_ids_refer_to_same_logical_call

This turns the current debugging exercise into a permanent compatibility guarantee.

⸻

16. Broader Lesson from Recent MLX Issues

Recent MLX reports show that tool calling remains an active interoperability area.

Issue #607 demonstrates model-specific tool syntax causing parser failure. (GitHub)

Issue #1375 demonstrates missing IDs being generated by the server but subsequently conflicting with a model-specific template constraint. (GitHub)

A recent Qwen3-Coder report demonstrates valid-looking arguments being rejected by the parser and the resulting tool call silently disappearing, potentially causing agent loops. (GitHub)

Other MLX reports similarly describe valid model tool calls being dropped when the parser does not recognize the representation. (GitHub)

The implication for our Local LLM stack is important:

“OpenAI-compatible” must be tested at the agent/tool protocol level, not merely by confirming that /v1/chat/completions returns text.

Our compatibility acceptance tests should therefore cover both:

Inference compatibility

and:

Agentic protocol compatibility

⸻

17. Recommended Immediate Work

Proceed in this order:

1. Record MLXServe version
          │
          ▼
2. Record installed mlx-lm version
          │
          ▼
3. Inspect installed ToolCallFormatter
          │
          ▼
4. Compare against current upstream server.py
          │
          ▼
5. Test raw non-streaming tool call
          │
          ▼
6. Test raw streaming tool call
          │
          ▼
7. Capture SSE response
          │
          ▼
8. Determine exact point where ID becomes null
          │
          ▼
9. Upgrade mlx-lm/MLXServe if possible
          │
          ▼
10. Retest OpenCode
          │
          ├── works → regression tests
          │
          └── fails
                │
                ▼
          minimal boundary patch
                │
                ▼
             retest

Only if that fails should we consider an independent compatibility proxy.

⸻

18. Decision

Our working decision is:

Treat the Qwen3-Coder → MLX → OpenCode problem as a protocol-normalisation issue at the OpenAI-compatible server boundary.

Specifically:

1. Do not modify Qwen3-Coder merely because its native tool representation lacks an OpenAI tool-call ID.
2. Do not modify OpenCode merely to tolerate id: null.
3. First determine whether MLXServe is using an outdated or modified mlx-lm.
4. Prefer upgrading to current upstream behaviour.
5. If necessary, patch the MLX compatibility boundary minimally.
6. Introduce a standalone compatibility proxy only if broader interoperability problems justify one.
7. Add tool-protocol regression tests so future MLX/model upgrades cannot silently reintroduce the problem.

⸻

19. References

Primary

* MLX-LM server.py
    https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/server.py
    Current ToolCallFormatter implementation, including generation of an ID when one is absent. (GitHub)
* MLX-LM Issue #607 — mlx_lm.server crashes when tool_calls aren’t JSON
    https://github.com/ml-explore/mlx-lm/issues/607
    Demonstrates OpenCode/Codex interoperability failure caused by model-native tool-call syntax not being normalized correctly. (GitHub)
* MLX-LM Issue #1375 — generated UUID tool-call IDs and Mistral constraints
    https://github.com/ml-explore/mlx-lm/issues/1375
    Confirms that mlx_lm.server generates an ID when a tool call does not contain one. (GitHub)
* OpenAI Developer Community — safely handling aborted tool calls
    https://community.openai.com/t/how-to-safely-handle-aborted-tool-calls-when-using-openai-conversations-api/1372554
    Relevant to maintaining consistent tool-call/tool-result state after interruption, but downstream of our current id: null problem. (OpenAI Developer Community)

Additional evidence

* MLX-LM Issue #1627 — Qwen3-Coder parser rejects float-formatted integer arguments
    https://github.com/ml-explore/mlx-lm/issues/1627
    Demonstrates that parser-level incompatibilities can silently remove Qwen3-Coder tool calls and destabilize agent clients. (GitHub)
* MLX-LM Issue #1374 — valid Mistral tool calls dropped by parser
    https://github.com/ml-explore/mlx-lm/issues/1374
    Additional evidence that model-native tool representations must be correctly normalized before reaching an agent client. (GitHub)

⸻

20. Target Outcome

The target is not merely to make one OpenCode command succeed.

The target is:

                    LOCAL AGENT STACK
              ┌────────────────────┐
              │      OpenCode      │
              └─────────┬──────────┘
                        │
                 OpenAI contract
                        │
              ┌─────────▼──────────┐
              │ MLX compatibility  │
              │      boundary      │
              └─────────┬──────────┘
                        │
                model-native
                 tool protocol
                        │
              ┌─────────▼──────────┐
              │   Qwen3-Coder      │
              │  Local inference   │
              └────────────────────┘

Once this boundary is reliable, OpenCode should be able to perform local agentic coding with Qwen3-Coder without depending on cloud inference merely because of tool-protocol incompatibilities.

That is the appropriate foundation for the Local LLMs project: local inference behind a well-tested OpenAI-compatible agent interface, rather than client-specific workarounds.
