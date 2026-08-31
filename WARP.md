# Warp

You don't need to set up a Warp Agent. Your setup deliberately keeps the two AI systems separate, and your `~/.warp/settings.toml` already contains the one piece of Warp configuration that matters.

## How the pieces relate

**Warp Agent** (the `[agents.warp_agent]` section) is Warp's own built-in, cloud-backed assistant. It cannot be pointed at your local mlx-lm server in any way that's relevant here — and your whole BYOA strategy exists to avoid depending on it.

**OpenCode is just a CLI program** running in a Warp tab. Warp doesn't need to "know" about your local LLM at all — the entire chain `opencode` → `http://127.0.0.1:8080/v1` → mlx-lm → Qwen3-8B-4bit, plus the `auggie --mcp` context engine) is wired through the repo's `opencode.json`, not through Warp. Warp's only job is being the terminal, per your QUICKSTART: "Treat Warp as a plain terminal with tabs — no other Warp features are assumed."

## What your settings.toml already does right

This section is the relevant one, and it's already in place:

```toml

[agents.third_party.cli_agent_toolbar_enabled_commands]

'^opencode(\s.*)?$' = "OpenCode"

```

That tells Warp to recognize `opencode` as a third-party CLI agent and render its agent toolbar around the session — a UI nicety, nothing more. Also helpful: `default_session_mode = "terminal"` means new sessions start as plain terminals rather than Warp-AI prompt mode, which fits the two-tab workflow.

## Optional tightening (not required)

- If you want zero chance of accidentally invoking Warp's cloud AI while doing local-only work, you could set `is_any_ai_enabled = false` under `[agents.warp_agent]` and `nld_in_terminal_enabled = false` under `[agents.warp_agent.input]`. That's a preference, not a requirement — the two systems don't interfere.
- Note that the `[agents.execution_profiles.default]` denylist (no `curl`, `bash`, `rm`, etc.) applies to **Warp Agent's** command execution, not to what you or OpenCode run in a plain terminal tab. Your preflight `curl` checks and `serve.sh` work unaffected.

So the answer to "what do I do": nothing in Warp. Tab 1 `.mlxlm/serve.sh start`, Tab 2 `opencode` from the repo root — you're already fully configured.