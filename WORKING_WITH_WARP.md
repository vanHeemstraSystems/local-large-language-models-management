Working with Warp

In Augment Intent go to the workspace of Local Large Language Models (LLMs) Management:

/Users/wvanheemstra/intent/favourite-coyote/local-large-language-models-management

On the (…) menu right side of the workspace’s title (here: Local LLMs Management) choose “Open with Warp”.

In Warp run the following command from a terminal in the Local LLMs Management repository you just arrived at:

.mlxlm/serve.sh stop
.mlxlm/serve.sh start
bash .mlxlm/health.sh

This starts the local Qwen model served by mlx-lm.

Back in Augment Intent go to the workspace of another local repository (e.g. Pixstars Architecture Source).

On the (…) menu right of the workspace’s title (here: Pixstars Architecture Source) choose “Open with Warp”.

In Warp run the following command from a terminal in the (here: Pixstars Architecture Source) repository you just arrived at:

/Users/willemvanheemstra/intent/workspaces/favourite-coyote/local-large-language-models-management/scripts/opencode-single-repo.sh

This starts OpenCode for this repository only.

Using the local Qwen model

After OpenCode starts, use the local Qwen model as the normal/default model.

You can verify the available models with:

/models

OpenCode displays the models that are available to the current project and connected providers. Select the local Qwen model from this list.

The local Qwen model runs on the Mac mini through the mlx-lm server. The OpenCode Go subscription is not involved when this model is selected.

Example of a prompt:

Use the built-in Read tool only. Read only the first 80 lines of README.md. Summarize them in no more than 3 bullets. Do not use MCP tools and do not modify files.

⸻

Using Kimi K3 through OpenCode Go

OpenCode Go provides access to Kimi K3 as part of the Go subscription. The current OpenCode documentation identifies the model as Kimi K3, with the OpenCode model ID:

opencode-go/kimi-k3

OpenCode Go must first be connected to OpenCode.

Inside OpenCode run:

/connect

Choose:

OpenCode Go

and enter the API key obtained from the OpenCode Go subscription.

After connecting, run:

/models

The model picker should contain Kimi K3.

Select:

Kimi K3

The selection applies to the current OpenCode session. It does not replace the local Qwen configuration. (OpenCode)

Switching between Qwen and Kimi K3

Once both providers are available, switching is simple:

/models

Then select either:

Local Qwen

or:

Kimi K3

Conceptually:

                    OpenCode
                       │
                 /models
                       │
             ┌─────────┴─────────┐
             │                   │
             ▼                   ▼
       Local Qwen             Kimi K3
             │                   │
             ▼                   ▼
        Mac mini            OpenCode Go
        mlx-lm server        subscription

This means the same OpenCode session can use the local Qwen model when local/private/low-cost execution is preferred and Kimi K3 when a stronger cloud model is useful.

Important distinction

Switching models does not mean restarting the mlx-lm server.

The Qwen server can remain running while Kimi K3 is being used.

Likewise, selecting Kimi K3 does not stop Qwen:

mlx-lm
  │
  └── Qwen
       ↑
       │
       │ available whenever selected
       │
OpenCode
  │
  ├── Local Qwen
  │
  └── OpenCode Go → Kimi K3

The mlx-lm server therefore only needs to be running when you want to use the local Qwen model.

⸻

Selecting Kimi K3 when starting OpenCode

A model can also be selected when launching OpenCode rather than through the interactive /models picker.

The OpenCode model identifier for Kimi K3 through OpenCode Go is:

opencode-go/kimi-k3

For example:

opencode --model opencode-go/kimi-k3

This selects Kimi K3 for that OpenCode invocation.

The equivalent non-interactive run form is:

opencode run --model opencode-go/kimi-k3 "Explain the architecture of this repository."

OpenCode documents --model as the way to select a model for a particular invocation without changing the configured default. (OpenCode)

For normal interactive work, however, /models is preferable because it lets you choose from the models actually available in the current project rather than hard-coding a model identifier.

⸻

Recommended Open Engineering workflow

For the Local LLMs Management setup, use the models deliberately:

Local Qwen

Prefer Qwen when:

* the task is straightforward;
* the repository context is relatively small;
* you want local execution;
* you want to avoid cloud usage;
* you are testing prompts or tooling;
* the task does not require the strongest available reasoning.

Kimi K3 through OpenCode Go

Prefer Kimi K3 when:

* the task requires stronger reasoning;
* you are working through a complicated codebase;
* debugging becomes difficult;
* the local model is repeatedly failing;
* you want to escalate a task without moving to pay-per-token Kimi API usage.

This gives the workflow an explicit escalation path:

                    Task
                      │
                      ▼
                 Local Qwen
                      │
              ┌───────┴────────┐
              │                │
           succeeds          struggles
              │                │
              ▼                ▼
             Done        Switch to Kimi K3
                               │
                               ▼
                         OpenCode Go

The important point is that Kimi K3 through OpenCode Go is a subscription-based alternative to using the separate Kimi API on a pay-per-token basis. OpenCode Go currently includes Kimi K3 in its model lineup. (OpenCode)

⸻

Starting a fresh Warp/OpenCode session

When conversation context grows too large, responses become inconsistent, or you want a clean slate, start a fresh OpenCode session in the same Warp terminal (which is already opened in the target repository):

1. Exit or interrupt the current OpenCode process:
    * Type /exit (or /quit) at the OpenCode prompt, or
    * Press Ctrl+C to interrupt, then Ctrl+D if a prompt remains.
2. Launch a new session using the canonical single-repository wrapper:

/Users/willemvanheemstra/intent/workspaces/favourite-coyote/local-large-language-models-management/scripts/opencode-single-repo.sh

A fresh OpenCode session resets the conversation context only.

It does not require restarting the mlx-lm server.

The loaded Qwen model and its weights stay in memory, so a new session starts immediately.

If you were using Kimi K3, the new session can select Kimi K3 again through:

/models

or by launching OpenCode with:

opencode --model opencode-go/kimi-k3

⸻

When to restart the mlx-lm server

Restart the mlx-lm server only when the local Qwen server itself is unhealthy.

Use:

.mlxlm/serve.sh stop
.mlxlm/serve.sh start
bash .mlxlm/health.sh

Typical reasons include:

* an out-of-memory (OOM) condition;
* generation hangs or stalls;
* repeated failed local requests;
* repeated local request timeouts;
* the health check reports that the server is unhealthy.

Do not restart mlx-lm merely because you switched from Qwen to Kimi K3.

Kimi K3 is hosted through OpenCode Go and does not depend on the local mlx-lm server.

⸻

Quick reference

Goal	Action
Start local Qwen	.mlxlm/serve.sh start
Check local Qwen	bash .mlxlm/health.sh
Start OpenCode	opencode-single-repo.sh
See available models	/models
Switch to Qwen	/models → select local Qwen
Switch to Kimi K3	/models → select Kimi K3
Start directly with Kimi K3	opencode --model opencode-go/kimi-k3
Start a fresh OpenCode session	Exit OpenCode → run opencode-single-repo.sh
Restart Qwen	Stop → start → health check
Switch Qwen ↔ Kimi K3	No server restart required

The key operating principle is therefore:

Keep Qwen available locally, connect OpenCode Go once, and use /models to choose the appropriate model for each OpenCode session.
