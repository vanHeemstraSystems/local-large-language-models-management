# QUICKSTART — Using a local LLM with Augment Intent

Step-by-step operator guide for the validated `mlx-lm.server` + OpenCode + Augment Context Engine stack on a Mac mini M4 Pro (24 GB unified memory).

> Read STRATEGY.md first if you want the why. This file is only the how.

## Prerequisites

- **Hardware:** Apple Silicon Mac with ≥ 24 GB unified memory (validated on M4 Pro / macOS 26.5.2).
- **Homebrew** installed.
- **Python 3.10+** (validated on 3.12.13) available for a dedicated venv at `~/.mlxlm/venv`.
- `opencode`** CLI** (Homebrew: `brew install opencode`). Verified against 1.18.18.
- `auggie`** CLI** (Augment Code) with an authenticated Intent session. Verified against 0.34.0.
- **~20 GB free disk** for model weights.

## Billing & credits

Intent by Augment is BYOA (Bring Your Own Agent). This stack routes the agent through **OpenCode** at a **local** `mlx-lm.server`, so model calls do not touch Augment infrastructure. Per the [Intent walkthrough](https://www.augmentcode.com/guides/intent-walkthrough-prompt-to-merge) and [Intent pricing guide](https://www.augmentcode.com/guides/intent-pricing):

| Component | Costs Augment credits? |
| --- | --- |
| Auggie native agents (Coordinator / Implementor / Verifier / specialists) | Yes — same rate as the Auggie CLI |
| Augment Context Engine (auggie --mcp, codebase-retrieval) | Yes — drawn from your credit pool per retrieval |
| BYOA provider (Claude Code / Codex / OpenCode) | No — billed to that provider directly (here: local, $0) |
| Intent orchestration (spec editing, worktrees, PR flow) | No separate charge |

### Selecting the BYOA path in Intent

1. In the Intent desktop app, **create a new Space** (agent provider is chosen at Space creation).
2. Select **OpenCode** as the agent provider — not Auggie.
3. Intent launches `opencode` in the workspace, which reads this repo's `opencode.json` and routes every LLM call to `http://127.0.0.1:8080/v1`.

Chat sessions started against an Auggie specialist (Coordinator, Implementor, PR Reviewer, etc.) still consume credits regardless of the Space's default provider. Drive the workflow from the Space's OpenCode agent, not from an Auggie chat, to keep model spend at zero.

### Two operating modes

| Mode | Configuration | Cost | Trade-off |
| --- | --- | --- | --- |
| BYOA + Context Engine (default in this repo) | Keep mcp.augment-context-engine in opencode.json | Only Context Engine retrieval credits; model tokens are free | Grounded semantic search stays available |
| Fully local, zero-cost | Remove or disable the mcp.augment-context-engine block in opencode.json | $0 | Loses Augment retrieval; OpenCode falls back to built-in file/grep/terminal tools |

### Verifying no credits are consumed

- Note your credit balance at `app.augmentcode.com` before a session.
- Run a BYOA/OpenCode Space session end-to-end.
- Re-check the balance. A Context-Engine-disabled session should show **zero** delta; a Context-Engine-enabled session should show only retrieval-call deltas (no chat/completion tokens).

### Caveats

- The public docs describe BYOA at Space creation but do not document a settings-panel path for switching provider on an *existing* Space. If Intent does not expose that toggle, create a fresh Space.
- Some Intent side-band agents (workspace title/summary generators, review helpers) may always call Augment-hosted models. Confirm from the credit dashboard rather than assumption.

## One-time setup

### 1. Create the mlx-lm venv

```sh
python3 -m venv ~/.mlxlm/venv
source ~/.mlxlm/venv/bin/activate
pip install --upgrade pip
pip install "mlx-lm==0.31.3"
deactivate
```

### 2. Download the default model

Qwen3-8B-4bit is the validated default because it uses the standard `<tool_call>` idiom that `mlx_lm.server` parses correctly (see *Known errors* below for why `gpt-oss-20b` is not the default).

```sh
mkdir -p ~/.mlx-serve/models/mlx-community
cd ~/.mlx-serve/models/mlx-community
huggingface-cli download mlx-community/Qwen3-8B-4bit \
  --local-dir Qwen3-8B-4bit --local-dir-use-symlinks False
```

### 3. Confirm the installed mlx-lm version

`mlx-lm` 0.31.3 ships an upstream `ToolCallFormatter` that emits an OpenAI-spec-compliant `tool_calls[].id` on its own, so no venv patch is required. Verify the pinned version is installed:

```sh
~/.mlxlm/venv/bin/python -m pip show mlx-lm | grep -i '^Version:'
# expect: Version: 0.31.3
```

Historical A.1 patch context (retired as of mlx-lm 0.31.3) and its rollback path live in `.mlxlm/PATCHES.md`.

## Daily workflow

### 1. Start `mlx-lm.server`

```sh
.mlxlm/serve.sh start
.mlxlm/serve.sh status
```

You should see a process listening on `127.0.0.1:8080` and `/v1/models` returning JSON.

### 2. Verify the installed mlx-lm version

```sh
~/.mlxlm/venv/bin/python -m pip show mlx-lm | grep -i '^Version:'
```

Expect `Version: 0.31.3`. Older versions (0.29.1) required the retired A.1 venv patch — see `.mlxlm/PATCHES.md` if you need to roll back.

### 3. Launch OpenCode from the repository root

```sh
opencode
```

OpenCode reads `opencode.json`, connects to `http://127.0.0.1:8080/v1`, defaults to Qwen3-8B-4bit, and spawns the `augment-context-engine` MCP server via `auggie --mcp --mcp-auto-workspace`.

### 4. Confirm the loop is live

Inside OpenCode, ask a grounded repository question, for example:

> Using the augment-context-engine, find where the safety baseline caps are enforced in this repo and quote the exact lines.

A healthy round-trip:

1. Model requests the `codebase-retrieval` tool.
2. OpenCode executes it via the MCP server.
3. Model reasons over the result and answers with `finish_reason=stop`.
4. Server log shows no `BatchRotatingKVCache` traceback.

### 5. Optional — run the four-probe suite

To reproduce the committed baseline before starting real work:

```sh
bash .mlxlm/probes/run_probes.sh
cat .mlxlm/probes/summary.txt
```

Expected: P1, P2, P4 exit 0 with `finish=stop`; P3 exits 0 with `finish=length` (documented Qwen3 behavior, not a regression — see `.mlxlm/probes/baseline_postmerge_20260824T001813/BASELINE.md`).

### 6. Shut down cleanly

```sh
.mlxlm/serve.sh stop
```

## Coding with Warp

Day-to-day coding from Warp uses two terminal tabs and one focused OpenCode session at a time. Treat Warp as a plain terminal with tabs — no other Warp features are assumed.

### Two-tab Warp layout

| Tab | Working directory | Purpose | Commands |
| --- | --- | --- | --- |
| 1 | anywhere | mlx-lm.server control | .mlxlm/serve.sh start / status / stop; tail -f .mlxlm/mlxlm-serve.log |
| 2 | repository root | OpenCode agent loop | opencode |

Keep Tab 1 visible while working in Tab 2 so server errors (`BatchRotatingKVCache`, OOM, IOGPU) surface immediately in the log.

### Two `.mlxlm/` directories

Two distinct locations share the name — commands in this guide assume the second:

- `~/.mlxlm/` (home) — holds ONLY the mlx-lm venv (Python 3.12 + mlx-lm 0.31.3) at `~/.mlxlm/venv/`.
- `<repo>/.mlxlm/` (this repo) — tooling and evidence: `serve.sh`, `health.sh`, `PATCHES.md`, `probes/`, and disk-only `mlxlm-serve.log`.

All `serve.sh` and `health.sh` invocations run from the **repository root** (for example `.mlxlm/serve.sh start`). One-command preflight: `bash .mlxlm/health.sh` — checks the venv versions, `/v1/models`, and server RSS against the 18 GB safety cap.

### Starting a coding session

Preflight checklist — run in order, do not skip:

1. Server up: `.mlxlm/serve.sh status` shows a live PID and `/v1/models` returns JSON.
2. mlx-lm version correct: `~/.mlxlm/venv/bin/python -m pip show mlx-lm | grep -i '^Version:'` reports `Version: 0.31.3` (upstream `ToolCallFormatter` supplies the tool-call id natively).
3. `cd` into the repository you want to work on and run `opencode` from that directory. OpenCode reads that repo's `opencode.json` and routes model calls to `http://127.0.0.1:8080/v1`.
4. Working in a different repository? Copy this repo's `opencode.json` there first as a template (provider URL, default model, MCP wiring, context/output caps, `tool_output` caps).

### How to prompt for coding work

The context budget is **16,384 tokens with a ~1,536-token output cap** (per-model `limit` in `opencode.json`). Ask for one focused change per exchange — do not bundle unrelated asks.

Grounded exploration via the `augment-context-engine` MCP tool:

> Use codebase-retrieval to find where <symbol or behavior> is defined in this repo. Quote the file and the exact lines. Do not summarize other files.

A small scoped edit:

> Modify function <X> in <path/to/file> to <Z>. Show the diff only. Do not touch other files.

Running tests or commands via OpenCode's built-in terminal tool:

> Run <tests|lint|build command> from the repo root and report only the failing lines.

Keep retrieval payloads focused and let compaction do its job (`compaction.auto=true` in `opencode.json`).

### Session hygiene (green / amber / red)

Follows STRATEGY.md's session lifecycle. React early — do not push through amber.

| State | Signals | Action |
| --- | --- | --- |
| Green | Requests complete normally; no GPU-memory warnings; no BatchRotatingKVCache traceback in the log | Continue |
| Amber | Repeated retrieval dominates history; context approaches 16K; compaction fires repeatedly; GPU gate starts rejecting reasonable requests | Preserve conclusions to notes, end the OpenCode session, restart it from a clean context; restart the server between heavy sessions |
| Red | GPU stall, server hang, severe memory pressure, IOGPU/Metal errors, abnormal process termination, kernel panic | Stop immediately. Capture the log. Do not reproduce the workload. |

Restart the OpenCode session as soon as you see `Prompt exceeds maximum context length: N requested, 16384 available` — that is the hard context cap, not a transient hiccup. Stop-rule triggers mean abort, not retry.

### Reviewing and committing

The local model proposes edits; the operator owns git. Review and commit from Warp:

```sh
git status
git diff <path>          # review each change
git add -p <path>        # stage hunks you accept
git commit -m "<message>"
```

Do not delegate `git commit` or `git push` to the model. Reject any edit you would not commit yourself.

### What NOT to do

- **Do not paste large files into the prompt.** Tool output is already capped at 200 lines / 16 KB (`tool_output` in `opencode.json`); manual pastes bypass that cap and blow the context.
- **Do not run parallel OpenCode sessions against a single **`mlx-lm.server`**.** Concurrent requests with different prompt lengths trigger the W4 `BatchRotatingKVCache.merge` crash. The `agent.title.disable` / `agent.summary.disable` settings in `opencode.json` serialize one session's own traffic; they do not protect against a second client.
- **Do not use **`gpt-oss-20b`** for tool-calling work.** `mlx_lm.server` does not parse its Harmony `commentary` channel into structured `tool_calls[]`, so MCP tool loops never fire. Keep the default `Qwen3-8B-4bit`.

## Known errors and their resolution

| Symptom | Root cause | Fix |
| --- | --- | --- |
| OpenCode aborts mid-stream: UnknownError: Expected 'id' to be a string. | Running an old mlx-lm (<0.31.x) where tool_calls[].id is null | Upgrade the venv to mlx-lm 0.31.3 (upstream ToolCallFormatter supplies a non-null id); see setup step 3 |
| Server 500 during normal use; log shows BatchRotatingKVCache.merge traceback | W4: concurrent requests with different prompt lengths crash the batch decoder | Confirm opencode.json has both agent.title.disable=true and agent.summary.disable=true (already set on origin/main) |
| gpt-oss-20b selected → tool calls never fire, model emits `< | channel | >commentary` text |
| P3 probe returns finish=length, output=1536 | Qwen3's <think> reasoning trace exceeds the 1536-token safety cap for this specific prompt | Expected — not a regression. Real MCP tool loops with normal prompts complete cleanly |
| Request rejected with Prompt exceeds maximum context length: N requested, 16384 available | Hard context cap hit | Restart the OpenCode session; keep retrieval payloads focused; let compaction do its job |
| Request rejected with requires ~XMB GPU memory but only ~YMB available | Per-request GPU memory gate — warm cache fragmentation | Restart the server (.mlxlm/serve.sh stop && start), then retry |
| /v1/models returns nothing / server unreachable | Server not running or wrong port | .mlxlm/serve.sh status; check .mlxlm/mlxlm-serve.log; restart |

Stop-rule triggers (kernel panic, IOGPU errors, sustained memory pressure) require immediate abort per `STRATEGY.md` — capture evidence, do not push through.

## Example: end-to-end Intent + local LLM session

Concrete sequence to smoke-test the full stack:

```sh
# Terminal 1 — start the server
.mlxlm/serve.sh start
.mlxlm/serve.sh status
~/.mlxlm/venv/bin/python -m pip show mlx-lm | grep -i '^Version:'

# Terminal 2 — from repo root
cd /path/to/local-large-language-models-management
opencode
```

Inside OpenCode:

> Use codebase-retrieval to locate the file that documents the retired A.1 venv patch, and quote the retirement note that explains why the patch is no longer required on mlx-lm 0.31.3.

Expected outcome:

- Tool call `codebase-retrieval` fires with a focused query.
- Result returns `.mlxlm/PATCHES.md`.
- Model responds with the diff block from that file and stops naturally.
- No `BatchRotatingKVCache` errors in `.mlxlm/mlxlm-serve.log`.
- Server RSS stays well below the 18 GB safety ceiling (typically 1–2 GB with Qwen3-8B-4bit warm).

If that succeeds, the local LLM + Augment Intent loop is proven working on your machine and matches the `origin/main` baseline.

## Where to look when something is off

- `STRATEGY.md` — architecture, safety baseline, failure-mode taxonomy, root-cause discipline.
- `opencode.json` — authoritative for context/output caps, default model, W1 side-band disable, MCP wiring.
- `.mlxlm/PATCHES.md` — retired A.1 patch: history, rationale, and rollback (via the preserved `~/.mlxlm/venv-py39-mlxlm0291.bak` venv).
- `.mlxlm/mlxlm-serve.log` — server output (look for `BatchRotatingKVCache`, OOM, IOGPU errors).
- `.mlxlm/probes/baseline_postmerge_20260824T001813/BASELINE.md` — the reference the current stack was validated against.
- `.mlxlm/probes/upstream_bug_report.md` and `.mlxlm/probes/upstream_fr_tool_calls.md` — drafted reports for `ml-explore/mlx-lm`, pending upstream filing.