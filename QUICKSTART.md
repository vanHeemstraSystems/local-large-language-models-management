# QUICKSTART — Using a local LLM with Augment Intent

Step-by-step operator guide for the validated `mlx-lm.server` + OpenCode + Augment Context Engine stack on a Mac mini M4 Pro (24 GB unified memory).

> Read STRATEGY.md first if you want the why. This file is only the how.

## Prerequisites

- **Hardware:** Apple Silicon Mac with ≥ 24 GB unified memory (validated on M4 Pro / macOS 26.5.2).
- **Homebrew** installed.
- **Python 3.9+** available for a dedicated venv at `~/.mlxlm/venv`.
- `opencode`** CLI** (Homebrew: `brew install opencode`). Verified against 1.18.18.
- `auggie`** CLI** (Augment Code) with an authenticated Intent session. Verified against 0.34.0.
- **~20 GB free disk** for model weights.

## Billing & credits

Intent by Augment is BYOA (Bring Your Own Agent). This stack routes the agent through **OpenCode** at a **local** `mlx-lm.server`, so model calls do not touch Augment infrastructure. Per the [Intent walkthrough](https://www.augmentcode.com/guides/intent-walkthrough-prompt-to-merge) and [Intent pricing guide](https://www.augmentcode.com/guides/intent-pricing):

| Component | Costs Augment credits? |
|---|---|
| Auggie native agents (Coordinator / Implementor / Verifier / specialists) | Yes — same rate as the Auggie CLI |
| Augment Context Engine (`auggie --mcp`, `codebase-retrieval`) | Yes — drawn from your credit pool per retrieval |
| BYOA provider (Claude Code / Codex / **OpenCode**) | No — billed to that provider directly (here: local, $0) |
| Intent orchestration (spec editing, worktrees, PR flow) | No separate charge |

### Selecting the BYOA path in Intent

1. In the Intent desktop app, **create a new Space** (agent provider is chosen at Space creation).
2. Select **OpenCode** as the agent provider — not Auggie.
3. Intent launches `opencode` in the workspace, which reads this repo's `opencode.json` and routes every LLM call to `http://127.0.0.1:8080/v1`.

Chat sessions started against an Auggie specialist (Coordinator, Implementor, PR Reviewer, etc.) still consume credits regardless of the Space's default provider. Drive the workflow from the Space's OpenCode agent, not from an Auggie chat, to keep model spend at zero.

### Two operating modes

| Mode | Configuration | Cost | Trade-off |
|---|---|---|---|
| **BYOA + Context Engine** (default in this repo) | Keep `mcp.augment-context-engine` in `opencode.json` | Only Context Engine retrieval credits; model tokens are free | Grounded semantic search stays available |
| **Fully local, zero-cost** | Remove or disable the `mcp.augment-context-engine` block in `opencode.json` | $0 | Loses Augment retrieval; OpenCode falls back to built-in file/grep/terminal tools |

### Verifying no credits are consumed

- Note your credit balance at `app.augmentcode.com` before a session.
- Run a BYOA/OpenCode Space session end-to-end.
- Re-check the balance. A Context-Engine-disabled session should show **zero** delta; a Context-Engine-enabled session should show only retrieval-call deltas (no chat/completion tokens).

### Caveats

- The public docs describe BYOA at Space creation but do not document a settings-panel path for switching provider on an *existing* Space. If Intent does not expose that toggle, create a fresh Space.
- Some Intent side-band agents (workspace title/summary generators, review helpers) may always call Augment-hosted models. Confirm from the credit dashboard rather than assumption.
- This QUICKSTART's stack still requires the A.1 venv patch to be in place before any tool-calling session (see below); a missing patch aborts BYOA sessions mid-stream on the first tool call.

## One-time setup

### 1. Create the mlx-lm venv

```sh
python3 -m venv ~/.mlxlm/venv
source ~/.mlxlm/venv/bin/activate
pip install --upgrade pip
pip install "mlx-lm==0.29.1"
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

### 3. Apply the A.1 venv patch — **required**

`mlx_lm.server` emits `tool_calls[].id: null`, which violates the OpenAI spec and causes OpenCode to abort mid-stream on any tool call. Patch it:

```sh
SRV=~/.mlxlm/venv/lib/python3.9/site-packages/mlx_lm/server.py
cp "$SRV" "$SRV.pre-A1.bak"
python3 - "$SRV" <<'PY'
import sys, re, pathlib
p = pathlib.Path(sys.argv[1])
src = p.read_text()
new = src.replace('                "id": None,',
                  '                "id": f"call_{uuid.uuid4().hex[:24]}",')
assert new != src, "A.1 patch anchor not found — inspect server.py manually"
p.write_text(new)
PY
grep -n 'call_{uuid' "$SRV"   # expect a single match near line 1074
```

Details and reversal steps live in `.mlxlm/PATCHES.md`.

> ⚠️ The patch does not survive pip install --upgrade mlx-lm. Re-apply after any venv rebuild or mlx-lm upgrade.

## Daily workflow

### 1. Start `mlx-lm.server`

```sh
.mlxlm/serve.sh start
.mlxlm/serve.sh status
```

You should see a process listening on `127.0.0.1:8080` and `/v1/models` returning JSON.

### 2. Verify the A.1 patch is in place

```sh
grep -n 'call_{uuid' ~/.mlxlm/venv/lib/python3.9/site-packages/mlx_lm/server.py
```

Expect exactly one match (near line 1074). If empty, re-apply the patch before running any agent loop.

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

## Known errors and their resolution

| Symptom | Root cause | Fix |
| --- | --- | --- |
| OpenCode aborts mid-stream: UnknownError: Expected 'id' to be a string. | A.1 patch missing (upstream returns tool_calls[].id: null) | Re-apply the A.1 patch (see setup step 3), restart the server |
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
grep -n 'call_{uuid' ~/.mlxlm/venv/lib/python3.9/site-packages/mlx_lm/server.py

# Terminal 2 — from repo root
cd /path/to/local-large-language-models-management
opencode
```

Inside OpenCode:

> Use codebase-retrieval to locate the file that documents the A.1 venv patch, then quote the exact diff block that shows the null → uuid change.

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
- `.mlxlm/PATCHES.md` — A.1 patch details and reversal.
- `.mlxlm/mlxlm-serve.log` — server output (look for `BatchRotatingKVCache`, OOM, IOGPU errors).
- `.mlxlm/probes/baseline_postmerge_20260824T001813/BASELINE.md` — the reference the current stack was validated against.
- `.mlxlm/probes/upstream_bug_report.md` and `.mlxlm/probes/upstream_fr_tool_calls.md` — drafted reports for `ml-explore/mlx-lm`, pending upstream filing.