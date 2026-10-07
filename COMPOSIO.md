Composio

What is Composio?

Composio is an integration and tool-execution platform for AI agents.

It sits between an AI agent and external applications, giving the agent access to tools that can perform real actions rather than merely generate text.

Composio provides:

* Toolkits — integrations with 1,000+ / 1,500+ applications and services, depending on the current Composio catalogue.
* Tool discovery — agents can discover the tools they need instead of loading every available tool into their context.
* Authentication — OAuth, API keys, token management and connected accounts are managed by Composio.
* Sessions — tools and authentication can be scoped to a particular user and agent session.
* Triggers — external events can initiate agent workflows.
* Workspaces / Workbench — multi-step agent tasks can execute code and work with intermediate results in an isolated environment.
* MCP support — Composio can expose its tools through the Model Context Protocol.
* SDKs — official Python and TypeScript SDKs.
* Provider adapters — integrations with agent frameworks such as OpenAI, Anthropic, LangChain, LlamaIndex, CrewAI, Google and others.

The important conceptual distinction is:

An LLM provides intelligence; Composio provides the hands that allow an agent to act.

For Open Engineering, this makes Composio a candidate implementation for the Hands part of a Pico: the AI agent decides what should happen, while Composio provides authenticated access to external systems.

⸻

What can Composio be used for?

Composio is particularly useful when an AI agent needs to interact with systems outside its own runtime.

1. Software development

An agent can interact with development systems such as:

* GitHub
* Linear
* issue trackers
* CI/CD systems
* monitoring systems
* documentation systems
* Slack

For example, an agent could:

1. inspect unresolved production errors,
2. retrieve additional diagnostic information,
3. classify the errors,
4. create Linear issues for critical problems,
5. notify the engineering team in Slack.

This is significantly more powerful than asking an LLM to merely describe what a developer should do.

⸻

2. Email and calendar automation

Composio can connect agents to services such as Gmail, Outlook and Google Calendar.

An agent could:

* inspect incoming email,
* identify messages requiring action,
* draft responses,
* inspect calendar availability,
* schedule meetings,
* update calendar events.

The agent can therefore perform a complete workflow rather than producing instructions for a human to execute manually.

⸻

3. Documents and knowledge systems

Agents can work with systems such as:

* Google Drive
* Google Docs
* Notion
* Slack
* other supported knowledge-management systems.

For example:

“Find the decisions from Monday’s architecture meeting and add the resulting action items to the project tracker.”

The agent can retrieve the meeting information, interpret it and then perform the corresponding actions.

⸻

4. Multi-application workflows

One of Composio’s strongest use cases is connecting several applications into one agentic workflow.

For example:

GitHub
   ↓
inspect pull request
   ↓
Sentry
   ↓
inspect related errors
   ↓
LLM
   ↓
classify findings
   ↓
Linear
   ↓
create issues
   ↓
Slack
   ↓
notify team

The agent does not need a separate bespoke integration for every application.

⸻

5. Event-driven agents

Composio supports triggers, allowing external events to initiate workflows.

For example:

New GitHub issue
       ↓
     Agent
       ↓
Analyse issue
       ↓
Create response / task
       ↓
Notify Slack

This moves an agent from a purely conversational system toward an autonomous service.

⸻

6. Coding agents

Composio can also provide a tool surface to coding agents.

Its CLI can search for and execute tools directly from a terminal, while MCP support allows compatible AI clients to consume Composio tools through the Model Context Protocol.

This makes Composio relevant to development environments where an agent needs capabilities beyond manipulating the local filesystem.

⸻

Examples

Example 1 — Python: create a Composio session

Install the Python SDK:

pip install composio

Then create a session:

from composio import Composio
composio = Composio()
session = composio.create(
    user_id="user_123"
)
tools = session.tools()

The session associates the agent with a user and provides access to the tools available to that session.

Composio deliberately supports runtime tool discovery so that an agent does not necessarily have to load hundreds of tool definitions into its context. (GitHub)

⸻

Example 2 — Python: expose tools to an agent

A simplified agent integration can look like:

from composio import Composio
composio = Composio()
session = composio.create(
    user_id="user_123"
)
tools = session.tools()
# Pass `tools` to the agent framework.
agent = create_agent(
    instructions="You are an engineering assistant.",
    tools=tools,
)
result = agent.run(
    "Find the unresolved production issues and summarize them."
)
print(result)

The exact agent construction depends on the framework being used. Composio provides provider adapters for several popular agent frameworks. (GitHub)

⸻

Example 3 — Restrict an agent to specific toolkits

Instead of exposing everything to an agent, tools can be restricted to the systems that the agent actually needs.

For example:

from composio import Composio
composio = Composio()
session = composio.create(
    user_id="user_123"
)
tools = session.tools(
    toolkits=["GITHUB", "LINEAR", "SLACK"]
)

This is an important architectural pattern:

Agent
  │
  ├── GitHub
  ├── Linear
  └── Slack

rather than:

Agent
  │
  └── every available application

Limiting the available tool surface improves control, reduces unnecessary context and makes the agent’s capabilities easier to reason about.

⸻

Example 4 — TypeScript

Install the TypeScript SDK:

npm install @composio/core

A basic client can then be created with:

import { Composio } from "@composio/core";
const composio = new Composio();
const session = await composio.create(
  "user_123"
);
const tools = await session.tools();

Composio also provides TypeScript provider packages for frameworks such as OpenAI Agents, Anthropic, LangChain, Vercel AI SDK, Google and others. (GitHub)

⸻

Example 5 — A development workflow

A more realistic engineering agent could conceptually implement:

issues = run_composio_tool(
    "SENTRY_LIST_ISSUES",
    project="api-prod",
    status="unresolved",
)
for issue in issues:
    issue["trace"] = run_composio_tool(
        "SENTRY_GET_EVENT",
        issue_id=issue["id"],
    )
ranked = invoke_llm(
    f"""
    Classify these {len(issues)} production errors.
    Return P0, P1 and P2 classifications with reasoning.
    """
)
for error in ranked["P0"]:
    run_composio_tool(
        "LINEAR_CREATE_ISSUE",
        title=error["title"],
        team_id="ENG",
        priority=1,
    )

The important pattern is the separation of responsibilities:

Composio → access and execute tools
LLM      → reason about information
Agent    → decide which actions to perform

Composio itself demonstrates this type of Sentry → LLM → Linear workflow. (Composio)

⸻

Composio and MCP

Composio can also be used through the Model Context Protocol (MCP).

This is particularly interesting when the agent framework already understands MCP.

Conceptually:

┌──────────────────────┐
│       AI Agent       │
└──────────┬───────────┘
           │
          MCP
           │
┌──────────▼───────────┐
│       Composio       │
│                      │
│ Tool discovery       │
│ Authentication       │
│ Tool execution       │
│ Sessions             │
└──────────┬───────────┘
           │
     ┌─────┼─────┐
     ▼     ▼     ▼
   GitHub Slack Gmail

This means Composio does not have to be tightly coupled to a particular LLM or agent framework.

Composio explicitly supports connecting through MCP when a framework-specific provider is not appropriate. (GitHub)

⸻

Composio CLI

Composio also provides a command-line interface.

Installation:

curl -fsSL https://composio.dev/install | sh

Typical operations include:

composio login
composio search
composio execute
composio link
composio run

The CLI is particularly interesting for coding-agent workflows because it provides a local tool surface that an agent can use from the shell. (GitHub)

⸻

Composio in Open Engineering

Within the Open Engineering architecture, Composio can naturally occupy the Hands role of a Pico.

A Pico can therefore be conceptualized as:

┌────────────────────────────────────┐
│               Pico                 │
│                                    │
│  Python face                       │
│       │                            │
│       ▼                            │
│  Agent / reasoning                 │
│       │                            │
│       ▼                            │
│  Composio Hands                    │
│       │                            │
│       ├── GitHub                   │
│       ├── Slack                    │
│       ├── Gmail                    │
│       ├── Linear                   │
│       └── other external systems  │
│                                    │
│  Rust/PyO3 muscles                 │
│  Celld SQLite memory               │
└────────────────────────────────────┘

This gives Open Engineering a useful architectural boundary:

The Pico decides what it wants to accomplish; Composio provides authenticated capabilities for acting on the outside world.

Composio therefore does not need to become the canonical Open Engineering model or memory system. It can instead be treated as an external capability layer.

A possible OE abstraction could be:

hands:
  provider: composio
  capabilities:
    - github
    - slack
    - linear

The actual Composio implementation could then be hidden behind the OE Hands abstraction.

This would allow the Open Engineering agent architecture to remain independent of a particular integration provider.

⸻

Where to learn more?

Official website

Composio

The main site describes the platform, supported applications, agent integrations and current capabilities. (Composio)

Documentation

Composio Documentation

The documentation covers the SDKs, sessions, authentication, tools, triggers, MCP and agent integrations. (Composio Docs)

Examples

Composio Examples

The examples contain complete Python and TypeScript projects, including coding agents, Slack agents, email-triggered agents and multi-tool workflows. (Composio Docs)

GitHub

Composio GitHub repository

The repository contains the TypeScript and Python SDKs, CLI and provider integrations. (GitHub)

API reference

Composio API Reference

Useful when implementing Composio as infrastructure rather than simply following a quickstart. (Composio Docs)

⸻

Summary

Composio is best understood as an action and integration layer for AI agents.

LLM
 │
 │ reasoning
 ▼
Agent
 │
 │ tool selection
 ▼
Composio
 │
 ├── authentication
 ├── tool discovery
 ├── sessions
 ├── triggers
 └── execution
 │
 ▼
External systems

For Open Engineering, the most interesting role is therefore Composio as Hands: a replaceable external capability provider that allows Picos and other AI agents to interact with real-world software systems without embedding every integration directly into the Open Engineering codebase.
