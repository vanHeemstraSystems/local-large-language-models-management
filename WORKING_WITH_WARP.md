# Working with Warp

In Augment Intent go to the workspace of Local Large Language Models (LLMs) Management:

```text
/Users/wvanheemstra/intent/favourite-coyote/local-large-language-models-management
```

On the (...) menu right side of the workspace's title (here: Local LLMs Management) choose "Open with Warp".

In Warp run the following command from a terminal in the Local LLMs Management repository you just arrived at:

```bash
.mlxlm/serve.sh stop
.mlxlm/serve.sh start
bash .mlxlm/health.sh
```

Back in Augmemnt Intent go to the workspace of another local repository (e.g. Pixstars Architecture Source):

On the (...) menu right of the workspace's title (here: Pixsstars Architecture Source) choose "Open with Warp".

In Warp run the following command from a terminal in the (here: Pixstars Architecture Source) repository you just arrived at:

```bash
/Users/willemvanheemstra/intent/workspaces/favourite-coyote/local-large-language-models-management/scripts/opencode-single-repo.sh
```

This will start Open Code for this repository only.

Now you can start using Open Code with the local LLM.

Example of a prompt:

```text
Use the built-in Read tool only. Read only the first 80 lines of README.md. Summarize them in no more than 3 bullets. Do not use MCP tools and do not modify files.
```

## Starting a fresh Warp/OpenCode session

When conversation context grows too large, responses become inconsistent, or you want a clean slate, start a fresh OpenCode session in the same Warp terminal (which is already opened in the target repository):

1. Exit or interrupt the current OpenCode process:
   - Type `/exit` (or `/quit`) at the OpenCode prompt, or
   - Press `Ctrl+C` to interrupt, then `Ctrl+D` if a prompt remains.
2. Launch a new session using the canonical single-repository wrapper:

   ```bash
   /Users/willemvanheemstra/intent/workspaces/favourite-coyote/local-large-language-models-management/scripts/opencode-single-repo.sh
   ```

A fresh OpenCode session resets the conversation context only; it does **not** require restarting the mlx-lm server. The loaded model and its weights stay in memory, so the new session starts immediately.

Restart the mlx-lm server (using the `.mlxlm/serve.sh stop` / `start` and `bash .mlxlm/health.sh` sequence shown above) only when the server itself is unhealthy, for example after:

- an out-of-memory (OOM) condition,
- generation hangs or stalls, or
- repeated failed or timed-out requests.
