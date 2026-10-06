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

### 3. Launch OpenCode via the single-repository guard wrapper

```sh
scripts/opencode-single-repo.sh
```

`scripts/opencode-single-repo.sh` is the recommended entry point for every OpenCode session. It verifies the current directory is inside a git worktree, resolves the repository root via `git rev-parse --show-toplevel`, `cd`s to it, and then `exec`s `opencode` with every argument preserved. Launching plain `opencode` from `~/intent/workspaces/` (the parent of every workspace) picks up the parent-level `~/intent/workspaces/opencode.json` and lets a single session read across every repository beneath it; the wrapper refuses that directory (and any non-git directory) with a non-zero exit before any opencode process starts.

Once the wrapper hands off, OpenCode reads the repo's `opencode.json`, connects to `http://127.0.0.1:8080/v1`, defaults to Qwen3-8B-4bit, and spawns the `augment-context-engine` MCP server via `auggie --mcp --mcp-auto-workspace`.

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

## Diagnostics

One command to exercise the full local coding stack against a running `mlx-lm.server` and get a PASS/FAIL table with timing telemetry (memo 11 §14, current stack).

```sh
.mlxlm/serve.sh start
bash .mlxlm/diag.sh
```

The ladder runs six short, sequential steps and prints one row per step:

| Step | What it exercises | Fails when the problem is in… |
| --- | --- | --- |
| health | `.mlxlm/health.sh` (venv versions, `/v1/models`, server RSS vs 18 GB cap) | server |
| basic | 1-sentence non-streaming completion | server |
| stream | short streaming completion; records TTFT and max inter-chunk gap | protocol |
| tool_call | single `get_current_directory` tool call, non-streaming | protocol |
| tool_loop | two-step tool loop: tool_call → tool result → final text answer | protocol |
| longctx | ~8K-token prompt with a short reply (bounded, below the 16K ceiling) | context |

Reading the table: `ttft(s)` is the wall-clock time to the first streamed content chunk (populated for `stream` only); `tok/s` is `completion_tokens` divided by elapsed generation time (approximate for non-streaming steps that cannot separate prefill from decode); `p_tok` is the server-reported `prompt_tokens`.

The server-side prompt cache is capped via two env vars read by `.mlxlm/serve.sh` and passed through to `mlx_lm.server`:

- `MLXLM_PROMPT_CACHE_BYTES` (default `6442450944`, 6 GB) → `--prompt-cache-bytes`.
- `MLXLM_PROMPT_CACHE_SIZE` (default `4`) → `--prompt-cache-size` (number of distinct sequences).

`.mlxlm/health.sh` reads the first variable and FAILs if the most recent `Prompt Cache: N sequences, X GB` line in `.mlxlm/mlxlm-serve.log` exceeds that cap by more than 10%.

On any failure, the final line names the first failing layer:

```
Likely failure domain: server | protocol | context
```

Exit code is 0 when all steps PASS and 1 otherwise. Raw per-step request bodies, responses, metrics (`NN_step.metrics.json`), a `summary.json`, and a server-log excerpt (`server_log_excerpt.log`) are written to `.mlxlm/probes/diag_<UTC-timestamp>/` (gitignored via `.mlxlm/`). The ladder is short and sequential by design — do not use it as a stress loop.

## Agentic edits with the local model

The diag ladder proves the server and tool-call protocol work; it does not prove that OpenCode can drive the local Qwen3-8B-4bit through a complete read → edit → verify cycle on a real file. The scripted acceptance test does:

```sh
.mlxlm/agent-edit-test.sh                      # default local model
.mlxlm/agent-edit-test.sh -m opencode-go/kimi-k3   # one-off comparison
```

It creates `.mlxlm/probes/agentedit_<ts>/greet.txt` (`hello\n`), runs `opencode run --format json` with a fixed prompt that asks the model to append `world` after `hello` and read the file back, bounds the run at 5 min / 15 OpenCode steps / any new `[METAL]` line in the server log, and prints a per-layer table (`tool_discovery`, `tool_call_emission`, `result_handling`, `interpretation_verification`, `natural_stop`) plus wall time, step count, and the first-turn envelope token count from `step_finish`. The file-content check accepts either `hello\nworld\n` or `hello world\n` — both are faithful interpretations of the prompt — and FAILs on anything else. Exit code is 0 on PASS, 1 on FAIL, 2 on usage. One `route-log.sh` entry is appended per run.

What works today (four local runs on 2026-10-06): under the exact-match file check (`hello\nworld\n`), **2 of 4 passed** — one failing run wrote one-line `hello world` (which fails the exact check), and one failing run called the Edit tool with a hallucinated path (`/path/to/greet.txt`). The passing runs were 2 steps, 46–54 s, envelope ≈6.56K tokens; the failing fourth run had an 8,463-token envelope (cause of the envelope variation undetermined).

## Routing telemetry

Record one JSON line per task so local-vs-cloud escalation decisions become measurable before any automated router is considered (memo 12 §6, memo 16 §14). The log lives at `.mlxlm/routing/decisions.jsonl` and is gitignored via the existing `.mlxlm/` rule. No automation, no external calls — append by hand or from a wrapper script when a task finishes.

Append a record:

```sh
scripts/route-log.sh add --category small-edit --model qwen3-8b-4bit \
  --outcome completed --duration 42 --notes "renamed one symbol"
```

Record a local timeout that was escalated to a cloud model:

```sh
scripts/route-log.sh add --category multi-file --model qwen3-8b-4bit \
  --outcome timeout --escalated --escalated-to kimi-k3 --duration 310
```

`--outcome` must be one of `completed | timeout | tool_failure | tests_failed | context_overflow`. The script is Bash 3.2-compatible and uses `jq` only when it is already installed; otherwise it falls back to plain `printf`.

Review per-model success/timeout/escalation counts:

```sh
scripts/route-log.sh summary
```

## Escalating to a cloud model

Qwen3-8B-4bit stays the default. Escalate to a subscribed cloud model only when the local run hits one of the STRATEGY.md escalation triggers (repeated tool-loop failures, context overflow on a task that cannot be scoped down, or a reasoning depth the 16,384-token / 1,536-output envelope cannot support — see STRATEGY.md's session lifecycle and routing policy).

Prerequisite (one-time, performed outside this guide): subscribe to **OpenCode Go** and run `opencode auth login` to store the credential in `~/.local/share/opencode/auth.json`. Nothing secret is written to this repo. `opencode.json` enables the `opencode-go` provider and exposes `Kimi K3 (escalation)` as the only cloud model.

Switch inside a running OpenCode session:

1. Type `/models` and select `opencode-go / Kimi K3 (escalation)`. The top-level default in `opencode.json` is unchanged, so the switch applies to the current session only.
2. Run the one escalation prompt. Keep the exchange narrow — pass only the files and quotes the local model could not resolve.
3. Type `/models` again and reselect the local `mlxlm / Qwen3 8B 4-bit (fallback)` entry to return to zero-cost local inference for the next prompt.
4. Append a routing-telemetry line so the escalation is measurable: `scripts/route-log.sh add --category <category> --model qwen3-8b-4bit --outcome <outcome> --escalated --escalated-to kimi-k3 --duration <seconds>`.

**Included usage limits.** OpenCode Go is a flat-rate subscription that includes a fixed monthly token allowance for Kimi K3 (see memo17 §3; current rate per the user's plan: Kimi K3 ≈ $15/month included). Re-check the live limit on the OpenCode Go billing page (`opencode.ai/auth` → account) before planning a batch of escalations; the subscription page is the source of truth, not this file. Do not enable Extra Usage.

## Composio (external actions)

Composio is **enabled by default** in this repo (`mcp.composio.enabled=true` in `opencode.json`; user decision 2026-10-06). With the Composio MCP attached and no per-agent filter, the first-turn envelope measures ≈14.6–15.2K of the 16,384 local context, so the operating rule is enforced in config via two primary agents in `opencode.json`: the default **`local`** agent (Qwen3-8B-4bit, `permission.composio_*: deny`) keeps Composio tools out of the manifest — measured first-turn envelope ≈6.5K — and the **`escalation`** agent (`opencode-go/kimi-k3`, `permission.composio_*: allow`) is used when a session needs Composio tools; switch between them with Tab in the TUI or `--agent escalation` on `opencode run`. The 2026-10-06 read-only PoC still stands as the worst-case data point — a +6,768-token tool-manifest envelope drove the prompt cache to 11.42 GB and triggered a Metal `kIOGPUCommandBufferCallbackErrorOutOfMemory` on this 24 GB machine; the server's `--prompt-cache-bytes` 6 GB cap now bounds that failure mode.

Composio Connect, when enabled, attaches as an MCP server so OpenCode can call external applications (initially GitHub, read-only) through a single OAuth-managed endpoint. Model inference stays local; only the tool-call envelope and any returned payload transit Composio's cloud (STRATEGY.md Decisions, 2026-10-06).

Configuration lives in `opencode.json` alongside `augment-context-engine`:

```json
"composio": {
  "type": "remote",
  "url": "https://connect.composio.dev/mcp",
  "enabled": false
}
```

OpenCode 1.18.31 auto-detects the OAuth flow on first use; manually trigger or inspect it with:

```sh
opencode mcp auth composio    # one-time browser sign-in to Composio
opencode mcp list             # confirm status
opencode mcp debug composio   # inspect connection / OAuth discovery
```

After Composio sign-in, authorize **one** application (GitHub) through Composio's connected-apps browser flow. Follow memo 8 §11 (least privilege): one agent, one connection, one application, minimum permissions; expand only after validation.

**Action-class policy (STRATEGY.md "Action classes (memo 8 §9)").** Every Composio-mediated call is classified before execution:

- **Class A — Read** (search, inspect, list, retrieve, summarize, query): executes without additional confirmation.
- **Class B — Reversible write** (create a draft, open an issue, add a comment, create a branch): `propose → approve → execute`.
- **Class C — High-consequence / destructive / external communication** (delete, merge, publish, send, deploy, transfer, change permissions, modify credentials, remove infrastructure): `explain → approve → execute → verify`; never autonomous without a separately approved, narrowly scoped automation.

The initial PoC is **Class A only** — refuse or skip any write.

**Credential rule.** Composio owns authentication to external systems; the local model never sees application tokens. Credentials (Composio tokens, GitHub OAuth tokens, any derived bearer) MUST NOT be:

- embedded in prompts or copied into the chat;
- committed to Git or any tracked file (`opencode.json` included);
- written into skills, notes, or repository documentation;
- supplied as local-model context;
- printed in logs or server-log excerpts (redact before saving under `.mlxlm/probes/`).

OAuth tokens issued by `opencode mcp auth` are stored under `~/.local/share/opencode/mcp-auth.json`, outside the repo. Remove them with `opencode mcp logout composio` when a connection is retired.

**Controlled-write outcome (2026-10-06, task DoD).** Phase 4 of memo 8 was executed end-to-end on `opencode-go/kimi-k3` in a single OpenCode session across 3 turns: proposal → re-authorization link → write. The user approval was delivered as a distinct session turn after the proposal, and `GITHUB_CREATE_AN_ISSUE` was called exactly once; the model then read the issue back via `GITHUB_GET_AN_ISSUE`. Issue [#13](https://github.com/vanHeemstraSystems/local-large-language-models-management/issues/13) ("Composio integration verification") was created at 22:26:53Z and closed by the user at 22:29:38Z. First-turn prompt tokens 14,588 (proposal); 1,208 at the final step of the write turn. `.mlxlm/health.sh` PASS before and after; METAL log-line count 7 → 7 (delta 0).

## Coding with Warp

Day-to-day coding from Warp uses two terminal tabs and one focused OpenCode session at a time. Treat Warp as a plain terminal with tabs — no other Warp features are assumed.

### Two-tab Warp layout

| Tab | Working directory | Purpose | Commands |
| --- | --- | --- | --- |
| 1 | anywhere | mlx-lm.server control | .mlxlm/serve.sh start / status / stop; tail -f .mlxlm/mlxlm-serve.log |
| 2 | repository root | OpenCode agent loop | scripts/opencode-single-repo.sh |

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
3. `cd` into the repository you want to work on and run `scripts/opencode-single-repo.sh` from that directory (or any subdirectory of the repository). The wrapper refuses `~/intent/workspaces/` and any non-git directory before opencode starts, then hands off from the resolved repository root. OpenCode reads that repo's `opencode.json` and routes model calls to `http://127.0.0.1:8080/v1`.
4. Working in a different repository? Copy this repo's `opencode.json` there first as a template (provider URL, default model, MCP wiring, context/output caps, `tool_output` caps), and run the same wrapper from that repository. The wrapper does not require the working repo to be this one; it only requires that you are inside some git worktree.

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
- **Do not raise **`tool_output.max_lines`** above 200 (or **`max_bytes`** above 16384).** The V2 experiment at `max_lines=300` produced a ~12.38 GB prompt-cache spike and a Metal IOGPU OOM. Those values are hard safety defaults, not tuning knobs.
- **Do not create **`.opencodeignore`**.** OpenCode's ripgrep integration does not honour it, so the file is not a protection. Rely on `scripts/opencode-single-repo.sh` (single-repo scoping) and `tool_output` caps instead.
- **Do not download **`mlx-community/Qwen3-Coder-8B-4bit`**.** No such model exists on `mlx-community`. Any documentation, script, or note that recommends it is stale — keep the default `Qwen3-8B-4bit`, or use the declared alternate `gpt-oss-20b-MXFP4-Q8` per the *Fallback path* in `README.md`.
- **Do not change **`timeout=300000`** or **`compaction.reserved=5000`** / **`preserve_recent_tokens=4000`**.** Isolated increases/decreases were measured and showed no benefit; they are not accepted changes.
- **Do not attempt Qwen3-Coder-30B on this stack.** It is excluded from the current safety baseline (18 GB RSS / 16,384-context envelope) and was the panicked-task workload on the pre-migration `mlx-serve` stack; see the *Rejected V2 refactor proposals (archived)* section in `README.md`.

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

# Terminal 2 — from repo root (via the guard wrapper)
cd /path/to/local-large-language-models-management
scripts/opencode-single-repo.sh
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