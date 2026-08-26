# Memo 8 — Implement Composio in Warp

Status: Proposed for implementation
Date: 27 August 2026
Scope: Local Large Language Models Management
Decision area: Warp / MCP / Composio / local inference

Executive Summary

We should integrate Composio into Warp as the external action/tool layer for our local-first agent environment.

Warp now supports Composio directly through its MCP server configuration. Composio Connect presents a single MCP endpoint through which Warp can discover, authenticate, and execute actions across more than 1,000 external applications. Rather than loading thousands of individual tool definitions into the model context, Composio exposes a small set of meta-tools that dynamically discover and execute the required capabilities. (Composio)

This fits the architecture we have been developing:

                       Developer
                           │
                           ▼
                         Warp
                           │
                    ┌──────┴──────┐
                    │ Warp Agent  │
                    └──────┬──────┘
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
          "Brain"                     "Hands"
             │                           │
        Local LLM                    Composio
             │                           │
      MLX / MLXServe                MCP Connect
             │                           │
      Qwen3-Coder             External applications
                                      │
                         ┌────────────┼────────────┐
                         ▼            ▼            ▼
                       GitHub       Gmail        Slack
                         │
                        ...

The implementation should deliberately separate these two concerns:

* Inference: Qwen3-Coder running locally through MLX/MLXServe.
* Actions: Composio Connect exposed to Warp through MCP.

Warp therefore becomes the agent harness, the local model provides the reasoning, and Composio provides the hands.

This should first be implemented as a controlled proof of concept before broader application access is enabled.

⸻

1. Context

We already have a functioning local inference architecture on the Mac Mini M4 Pro using MLX/MLXServe and Qwen3-Coder.

The remaining challenge is not simply giving a local model intelligence. An effective software-engineering agent also needs controlled access to external systems.

Examples include:

* GitHub;
* Gmail;
* Google Calendar;
* Slack;
* Linear;
* Notion;
* cloud services;
* issue trackers;
* documentation systems;
* CI/CD platforms.

Adding bespoke integrations for each service would create considerable implementation and maintenance overhead.

Composio provides an abstraction over this problem.

Composio Connect is specifically intended for existing MCP-compatible clients. Its current endpoint is:

https://connect.composio.dev/mcp

Composio currently exposes a small group of meta-tools through this endpoint. These allow an agent to discover suitable tools, establish connections where necessary, and perform actions without presenting the entire integration catalogue to the model at once. (docs.composio.dev)

Warp has now added direct support for this integration. Composio’s Warp documentation instructs users to configure it under:

Warp
  → Settings
    → Agents
      → MCP servers
        → Composio

The first time a connected application is required, Composio can initiate the application’s OAuth authorization flow. (Composio)

⸻

2. Decision

We will adopt the following conceptual division of responsibilities:

Warp       = Agent harness
Qwen3      = Brain
MLX        = Local inference runtime
Composio   = Hands
MCP        = Tool interface
Skills     = Reusable procedures

Composio will initially be connected to Warp through Composio Connect, rather than building our own Composio SDK integration.

This is intentional.

For personal use with an existing MCP client, Composio itself recommends Composio Connect rather than creating programmatic SDK sessions. Session-based MCP endpoints are more appropriate when building an application that manages its own users and Composio sessions. (docs.composio.dev)

Therefore:

Phase 1
Warp
  ↓
Composio Connect
  ↓
External applications

not:

Warp
  ↓
Custom integration
  ↓
Composio SDK
  ↓
Managed session
  ↓
External applications

We should introduce the latter only if the Local LLM platform eventually needs programmatically controlled Composio sessions.

⸻

3. Target Architecture

The initial target architecture is:

Mac Mini M4 Pro
│
├── Warp
│   │
│   ├── Agent harness
│   │
│   ├── Agent conversations
│   │
│   ├── Skills
│   │
│   └── MCP clients
│       │
│       └── Composio Connect
│           │
│           └── HTTPS
│               │
│               ▼
│          Composio Cloud
│               │
│        ┌──────┼───────┬────────┐
│        │      │       │        │
│        ▼      ▼       ▼        ▼
│      GitHub  Slack   Gmail   Calendar ...
│
└── MLX / MLXServe
    │
    └── Qwen3-Coder-30B-A3B

Ultimately Warp should combine both sides:

                     Warp Agent
                         │
             ┌───────────┴───────────┐
             │                       │
             ▼                       ▼
       Reasoning request        Tool request
             │                       │
             ▼                       ▼
         MLXServe                 Composio
             │                       │
             ▼                       ▼
      Qwen3-Coder              External system

This is a local-first, rather than entirely local, architecture.

The prompts and reasoning workload can be handled by the local model, but use of Composio necessarily communicates with Composio and whichever external service is being operated.

⸻

4. Warp Local Inference

Warp now supports custom inference endpoints compatible with the OpenAI Chat Completions API.

Warp explicitly states that these endpoints may point to self-hosted inference systems. Configuration is available through:

Warp
  → Settings
    → AI
      → Custom inference endpoint

This provides the architectural opening we need for MLXServe. (Warp)

Our desired configuration therefore becomes:

Warp Agent
   │
   ├── inference ──► MLXServe ──► Qwen3-Coder
   │
   └── tools ──────► MCP ───────► Composio

These integrations should be tested independently before combining them.

That distinction is important because failures then become easy to classify:

Reasoning failure?
    ↓
Qwen / prompt / MLXServe
Tool discovery failure?
    ↓
model ↔ MCP interaction
Authentication failure?
    ↓
Composio OAuth / account configuration
Action failure?
    ↓
Composio ↔ target application
Agent orchestration failure?
    ↓
Warp

⸻

5. Implementation Phase 1 — Connect Composio to Warp

Open:

Warp
→ Settings
→ Agents
→ MCP servers

Add:

Composio

Warp and Composio should then establish the Composio Connect MCP integration. Composio documents this exact Warp workflow. (Composio)

Where manual MCP endpoint configuration is required, the current Composio Connect endpoint is:

https://connect.composio.dev/mcp

(docs.composio.dev)

Do not introduce the Composio SDK during this phase.

⸻

6. Implementation Phase 2 — Connect One Low-Risk Application

Do not immediately authorize every available Composio integration.

Begin with one application.

GitHub is the preferred initial candidate because it maps directly onto our software-engineering use case and provides easily observable operations.

Start with read-oriented activities wherever possible.

For example:

Ask Warp:
Using Composio, inspect my GitHub repositories
and find repositories related to local LLM management.
Do not modify anything.

The expected sequence is:

Warp
  │
  ▼
Qwen determines external information is needed
  │
  ▼
Composio tool discovery
  │
  ▼
GitHub tool identified
  │
  ▼
OAuth requested if necessary
  │
  ▼
User approves authorization
  │
  ▼
GitHub queried
  │
  ▼
Result returned to Warp
  │
  ▼
Qwen interprets result

Composio states that application authorization can be performed on demand: the first attempted use can produce an OAuth authorization link which the user approves in the browser. (Composio)

⸻

7. Implementation Phase 3 — Validate Tool Discovery

We specifically want to test semantic tool discovery, not merely prove that a predetermined API call works.

For example:

Find my recent GitHub activity related to local language models.

The model should infer approximately:

Need external information
        ↓
Search Composio tools
        ↓
GitHub capability discovered
        ↓
Select relevant operation
        ↓
Execute operation
        ↓
Interpret response

This capability matters because Composio Connect does not expose thousands of application tools simultaneously.

Its meta-tool architecture avoids unnecessarily consuming the local model’s context with huge tool schemas. (docs.composio.dev)

That is particularly valuable for local models, where context size and inference efficiency are more constrained than with large hosted frontier models.

⸻

8. Implementation Phase 4 — Validate a Write Operation

Only after read access works reliably should we allow the agent to perform an observable, reversible write operation.

A suitable example could be:

Create a GitHub issue titled:
"Composio integration verification"
in the local-large-language-models-management repository.
Before creating it, tell me exactly what you intend to do
and request my approval.

The test should verify:

Intent
  ↓
Tool discovery
  ↓
Proposed action
  ↓
Human confirmation
  ↓
Tool execution
  ↓
External state changed
  ↓
Agent verifies result

The confirmation stage is an architectural requirement we should preserve for consequential operations.

⸻

9. Human-in-the-Loop Policy

An agent being technically capable of executing an action does not mean it should execute that action autonomously.

We should establish three action classes.

Class A — Read

Examples:

search
inspect
list
retrieve
summarize
query

These may normally execute without additional confirmation.

Class B — Reversible Write

Examples:

create draft
create issue
add comment
create branch
create calendar draft

These should generally require explicit confirmation while we validate the architecture.

Class C — High-Consequence Action

Examples:

delete
merge
publish
send
deploy
transfer
change permissions
modify credentials
remove infrastructure

These should always require explicit user authorization unless a narrowly scoped and separately approved automation has intentionally been established.

The rule should be:

READ
  → allowed
WRITE
  → propose → approve → execute
DESTRUCTIVE / EXTERNAL COMMUNICATION
  → explain → approve → execute → verify

⸻

10. Authentication and Secret Management

Composio should own authentication to external systems rather than giving application credentials directly to the local model.

The desired trust boundary is:

Qwen
 │
 │ intent / structured tool call
 ▼
Warp
 │
 ▼
Composio
 │
 │ authenticated operation
 ▼
External service

rather than:

Qwen
 │
 ├── GitHub token
 ├── Gmail token
 ├── Slack token
 └── ...

Credentials must never be:

* embedded in prompts;
* committed to Git;
* written into skill.md;
* stored in repository documentation;
* supplied as local-model context;
* printed in logs.

Composio’s consumer Connect flow associates connected applications with the member who authorized them. These connections are not automatically shared with other workspace members. (docs.composio.dev)

This is desirable for the initial implementation.

⸻

11. Start With Least Privilege

The initial implementation should follow:

one agent
    +
one Composio connection
    +
one application
    +
minimum permissions

and expand only after validation.

Recommended progression:

Stage 1
GitHub read
Stage 2
GitHub controlled writes
Stage 3
Additional development tooling
Stage 4
Calendar / productivity tooling
Stage 5
Messaging
Stage 6
Email
Stage 7
Multi-application workflows

Email and messaging should come later because an erroneous action can communicate externally on the user’s behalf.

⸻

12. Implementation Phase 5 — Local Model Verification

After Composio works correctly using Warp’s normal inference, switch Warp to our local inference endpoint.

Warp currently supports OpenAI Chat Completions-compatible custom endpoints, including self-hosted inference systems. (Warp)

The desired path is:

Warp
  │
  ▼
Custom OpenAI-compatible endpoint
  │
  ▼
MLXServe
  │
  ▼
Qwen3-Coder-30B-A3B

Then repeat exactly the same Composio acceptance tests.

This separates two questions:

1. Can Warp + Composio operate successfully?
2. Can our local Qwen model reason sufficiently well to operate Composio through Warp?

That distinction will greatly simplify troubleshooting.

⸻

13. Critical Compatibility Test

Our previous Local LLM work identified an important interoperability problem around malformed OpenAI-compatible tool calls, notably tool-call identifiers.

Therefore the combined architecture must explicitly test:

Qwen
 ↓
MLXServe
 ↓
OpenAI-compatible streaming response
 ↓
Warp
 ↓
tool_calls[]
 ↓
Composio MCP

We must verify that MLXServe emits valid tool calls that Warp accepts during an actual Composio invocation.

The most important test is therefore not:

Can Qwen answer a prompt?

but:

Can Qwen successfully complete:
reason
  → select MCP capability
  → emit valid tool call
  → receive tool result
  → continue reasoning
  → produce final answer?

This becomes a regression test for the Local LLM environment.

⸻

14. Recommended Acceptance Test

The following test should become our first end-to-end acceptance scenario:

Given:
Warp is running on the Mac Mini M4 Pro
And:
Warp uses the locally hosted Qwen3-Coder model
And:
Composio is configured as an MCP server
And:
GitHub has been authorized
When:
I ask Warp to identify the most recently updated
repository related to local LLM management
Then:
Qwen identifies the need for GitHub information
And:
Qwen discovers the appropriate Composio capability
And:
Warp produces a valid MCP tool request
And:
Composio queries GitHub
And:
the tool result returns to Warp
And:
Qwen interprets the result
And:
Warp answers the original request
And:
no hosted inference provider has been used.

Successful completion proves the core architecture:

LOCAL REASONING
      +
EXTERNAL ACTION

⸻

15. Implementation Phase 6 — Skills

Once a useful multi-step workflow operates reliably, convert it into a Warp skill.

Composio’s Warp guide explicitly demonstrates turning a working multi-application workflow into a reusable skill.md. (Composio)

For example:

skills/
└── github-repository-investigation/
    └── skill.md

Conceptually:

User intent
    │
    ▼
Warp Skill
    │
    ▼
Local Qwen
    │
    ▼
Composio
    │
    ▼
GitHub

The skill describes how work should be performed.

Composio provides the capabilities required to perform it.

This distinction should remain explicit:

Skill
 = procedure
Composio
 = capability
Qwen
 = reasoning
Warp
 = orchestration

⸻

16. Relationship to Open Engineering Pico

Although this implementation belongs initially to Local LLM management, it provides a direct proof of concept for the architecture we have recently defined for Open Engineering Pico.

Our Pico metaphor now maps remarkably closely onto this system:

                  PICO
                    │
       ┌────────────┼────────────┐
       │            │            │
       ▼            ▼            ▼
    Python         Rust       Composio
     Face          Body         Hands
                                  │
                                  ▼
                             MCP / Tools

For the local coding agent:

              Agent
                │
        ┌───────┴───────┐
        │               │
      Brain           Hands
        │               │
      Qwen           Composio
        │               │
       MLX             MCP

The Warp experiment can therefore serve as the reference implementation proving that the Composio-as-hands concept works in practice.

⸻

17. Future Architecture — Composio Sessions

We should deliberately postpone Composio’s SDK/session architecture.

It becomes relevant when Open Engineering itself starts constructing agents rather than merely configuring Warp.

Composio’s newer Sessions architecture allows an application to create a user-specific session and expose it as an MCP endpoint:

Open Engineering application
        │
        ▼
Composio Session
        │
        ├── identity
        ├── tool restrictions
        ├── authentication
        ├── connected accounts
        └── MCP endpoint

Composio recommends sessions for applications that need programmatic control, while Composio Connect remains appropriate for connecting an existing MCP client. (docs.composio.dev)

That provides a possible future Pico architecture:

Pico
 │
 ▼
Pico Runtime
 │
 ▼
Composio Session
 │
 ├── permitted toolkits
 ├── permitted tools
 ├── connected accounts
 └── MCP endpoint

Each Pico could eventually have its own explicitly bounded set of hands.

⸻

18. Future Capability Scoping

Composio sessions also provide a useful mechanism for restricting exactly which tools an agent receives.

For example, a session can expose only explicitly selected capabilities rather than all discoverable tools. Composio documents a direct-tools session preset that can expose a fixed MCP tool set. (docs.composio.dev)

Conceptually:

Documentation Pico
    │
    └── GitHub read
        GitHub create PR
        Notion read
Release Pico
    │
    └── GitHub release
        package registry
        CI/CD
Support Pico
    │
    └── GitHub issues
        Gmail drafts
        Slack

This is preferable to:

Every Pico
    ↓
Every external capability

and aligns with least-privilege architecture.

⸻

19. Observability

Tool execution should be treated as observable infrastructure.

For every external operation we eventually want to understand:

Who requested it?
What reasoning initiated it?
Which tool was selected?
Which application was accessed?
Was authentication required?
What parameters were supplied?
What happened?
Was external state changed?
Did the operation succeed?

Composio’s current platform provides tool execution information, including selected tools, inputs, responses, and timing through its logging facilities. (docs.composio.dev)

This should ultimately feed the Open Engineering concepts of:

Observation
Investigation
Execution
Events
Evidence
Reporting

rather than treating tool calls as invisible side effects.

⸻

20. Repository Documentation

The local-large-language-models-management repository should eventually record the architecture approximately as:

docs/
├── warp/
│   ├── README.md
│   ├── inference.md
│   ├── composio.md
│   └── troubleshooting.md
│
├── mlxserve/
│   └── ...
│
├── models/
│   └── qwen3-coder.md
│
└── architecture/
    ├── agent-harness.md
    ├── local-inference.md
    └── tools.md

The Composio documentation should record configuration and architecture but must never contain credentials or OAuth tokens.

⸻

21. Definition of Done

The implementation is complete when all of the following are true:

* Composio appears as an active MCP server in Warp.
* One external application has been connected successfully.
* Warp can discover a relevant Composio tool from natural-language intent.
* A read-only operation succeeds.
* The result is returned to and interpreted by the Warp agent.
* A controlled write operation succeeds after explicit user confirmation.
* No credentials are exposed to Qwen or stored in Git.
* Warp uses the local MLXServe endpoint for inference.
* Qwen can initiate a Composio operation using a valid tool call.
* The tool result can be returned into the same agent conversation.
* Qwen can continue reasoning after receiving the result.
* No OpenAI/Anthropic/etc. hosted inference is required for the acceptance test.
* At least one successful workflow has been captured as a reusable Warp skill.
* Architecture and troubleshooting notes have been committed to the Local LLM management repository.

⸻

22. Recommended Implementation Sequence

1. Add Composio MCP to Warp
          │
          ▼
2. Connect GitHub
          │
          ▼
3. Test GitHub read
          │
          ▼
4. Test controlled GitHub write
          │
          ▼
5. Confirm Composio path independently
          │
          ▼
6. Configure local MLXServe inference
          │
          ▼
7. Repeat GitHub read with Qwen
          │
          ▼
8. Test full tool-call round trip
          │
          ▼
9. Repeat controlled write
          │
          ▼
10. Capture workflow as skill.md
          │
          ▼
11. Document known limitations
          │
          ▼
12. Add further applications incrementally

This sequence keeps failure domains isolated and gives us a known-good baseline before introducing local-model tool-calling behavior.

⸻

23. Strategic Outcome

This implementation is more important than simply adding another Warp plugin.

It establishes a reusable agent architecture:

                    AGENT
                      │
        ┌─────────────┼─────────────┐
        │             │             │
        ▼             ▼             ▼
     Reasoning     Procedure      Action
        │             │             │
        ▼             ▼             ▼
      Qwen           Skill       Composio
        │                           │
        ▼                           ▼
       MLX                          MCP
                                     │
                                     ▼
                              Outside world

This allows us to avoid building a monolithic agent platform in which models, procedures, integrations, authentication, and execution are tightly coupled.

Instead:

Qwen thinks.

Skills explain how.

Composio provides the hands.

MCP provides the contract.

Warp orchestrates the whole interaction.

That is the architecture we should now implement and validate on the Mac Mini M4 Pro.

References

* Warp, “Bring your own inference to Warp,” 20 May 2026 — Warp supports custom OpenAI Chat Completions-compatible inference endpoints, including self-hosted inference. (Warp)
* Composio, “How to Use Composio with Warp,” 10 July 2026 — documents native Warp configuration, application authorization, multi-app workflows and conversion into reusable skill.md workflows. (Composio)
* Composio, “Composio Connect” — documents the shared MCP endpoint, meta-tool architecture and on-demand OAuth model. (docs.composio.dev)
* Composio, “Using sessions via MCP” — documents programmatically scoped MCP sessions and direct-tool restrictions for future application-level integration. (docs.composio.dev)
* Composio, “Migrating from MCP servers to Sessions” — distinguishes application-level Sessions from the simpler Connect approach intended for existing agents/MCP clients. (docs.composio.dev)
