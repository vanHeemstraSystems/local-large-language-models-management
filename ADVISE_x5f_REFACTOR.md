# ADVISE_REFACTOR.md — Refactor Local LLM Environment for Performance / Cost

> Operator: Willem Van Heemstra
> Machine: Mac mini M4 Pro 24GB unified / macOS 26.5.2
> Stack: mlx-lm.server 0.31.3 + OpenCode 1.18.18 + auggie 0.34.0 + Augment Intent desktop
> Workspace root: ~/intent/workspaces/<repo> (cloned repos for Intent GUI navigation)
> Entry: Intent GUI ... menu > "Open with Warp" > Warp terminal > `opencode`
> Goal: Zero Augment credit spend for model tokens, fix "timed out" on difficult challenges, keep 18GB RSS safety cap.

This file is an actionable work order for the Augment Intent BYOA/OpenCode agent. Apply it verbatim.

## 1. Root Cause Analysis (read before changing)

Current `opencode.json`:
- default model: `/Users/willemvanheemstra/.mlx-serve/models/mlx-community/Qwen3-8B-4bit` (8B)
- alternative: `gpt-oss-20b-MXFP4-Q8` (does NOT emit structured tool_calls[] in mlx_lm.server - Harmony commentary channel - confirmed in QUICK_START.md Known Errors)
- provider: `mlxlm` -> `http://127.0.0.1:8080/v1`, timeout 300000
- limits: context 16384, output 1536, compaction auto+prune, tool_output 200 lines / 16384 bytes
- MCP: `augment-context-engine` enabled via `auggie --mcp --mcp-auto-workspace`

Failure mode observed:
1. User opens `intent/workspaces/<repo>` from Intent GUI into Warp. If `opencode` is started from `intent/workspaces/` root or if MCP auto-workspace scans parent, codebase-retrieval payload = 20k-50k tokens.
2. Qwen3-8B <think> trace alone exceeds 1536 output cap -> server returns `finish=length` (P3 probe expected behavior) -> OpenCode retries -> 5min hang -> Warp reports "timed out".
3. Short answers = output clipping. Long waits + timeout = context + output cap + concurrent side-band requests triggering BatchRotatingKVCache merge path.

Billing context from QUICK_START.md:
- BYOA provider (OpenCode -> local mlx-lm.server) = $0
- Augment Context Engine retrieval = costs credits per retrieval
- Auggie native agents = costs credits
- Intent orchestration = no separate charge

## 2. Target State

- Primary local model for difficult tasks: `Qwen3-Coder-30B-A3B-Instruct-4bit` (MoE, 3B active, ~16-17GB RSS on 24GB Mac, fits under 18GB cap with max-kv-size 4096-8192). Fallback: `Qwen3-Coder-14B-4bit` (~8GB) if 30B exceeds cap.
- Keep validated `Qwen3-8B-4bit` as `small_model` for quick edits.
- Model IDs in `opencode.json` must be short IDs returned by `/v1/models`, NOT full filesystem paths. The server must be started with `--use-default-chat-template`.
- Two operating modes must be switchable:
  - Mode A: BYOA + Context Engine (default) - retrieval credits only, model $0
  - Mode B: Fully local zero-cost - MCP disabled, $0 total
- Context: 24576-32768 for 30B model, output 4096 for hard tasks. 8B stays at 16384/1536 to preserve validated baseline.
- Timeout: provider timeout 600000 (10m). Warp AI tool timeout also set to 300s.
- No parallel OpenCode sessions against single mlx-lm.server. Keep `agent.title.disable=true` and `agent.summary.disable=true` to serialize side-band.

## 3. Tasks to Execute

### 3.1 Download new models

```sh
mkdir -p ~/.mlx-serve/models/mlx-community
cd ~/.mlx-serve/models/mlx-community
huggingface-cli download mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit --local-dir Qwen3-Coder-30B-A3B-4bit --local-dir-use-symlinks False
huggingface-cli download mlx-community/Qwen3-Coder-14B-Instruct-4bit --local-dir Qwen3-Coder-14B-4bit --local-dir-use-symlinks False
```

Verify disk: need ~20GB free per model.

### 3.2 Refactor `.mlxlm/serve.sh`

Requirements:
- Support `serve.sh start [model-short-id]` where model-short-id is `qwen3-8b-4bit` | `qwen3-coder-14b-4bit` | `qwen3-coder-30b-a3b-4bit`
- Default remains `qwen3-8b-4bit` for baseline probes
- Launch command must be:
```
~/.mlxlm/venv/bin/python -m mlx_lm.server --model mlx-community/<HF_ID> --port 8080 --max-kv-size 8192 --use-default-chat-template --log-file <repo>/.mlxlm/mlxlm-serve.log
```
- For 30B-A3B, use `--max-kv-size 4096` to stay under 18GB RSS cap if 8192 exceeds. Make this adaptive: if RSS > 18GB in health.sh, restart with 4096.
- Ensure `/v1/models` returns short IDs matching opencode.json keys.

### 3.3 Refactor `opencode.json` at repo root

Replace provider.models block. DO NOT use filesystem paths as keys.

Target:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "mlxlm/qwen3-coder-30b-a3b-4bit",
  "small_model": "mlxlm/qwen3-8b-4bit",
  "enabled_providers": ["mlxlm"],
  "mcp": {
    "augment-context-engine": {
      "type": "local",
      "command": ["auggie", "--mcp", "--mcp-auto-workspace"],
      "enabled": false
    }
  },
  "compaction": {
    "auto": true,
    "prune": true,
    "reserved": 2000,
    "preserve_recent_tokens": 8000
  },
  "tool_output": {
    "max_lines": 500,
    "max_bytes": 32768
  },
  "agent": {
    "title": { "disable": true },
    "summary": { "disable": true }
  },
  "provider": {
    "mlxlm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local mlx-lm M4 Pro",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "timeout": 600000
      },
      "models": {
        "qwen3-coder-30b-a3b-4bit": {
          "name": "Qwen3 Coder 30B A3B 4-bit (primary for hard tasks)",
          "limit": { "context": 32768, "output": 4096 }
        },
        "qwen3-coder-14b-4bit": {
          "name": "Qwen3 Coder 14B 4-bit (fallback, 8GB RSS)",
          "limit": { "context": 24576, "output": 4096 }
        },
        "qwen3-8b-4bit": {
          "name": "Qwen3 8B 4-bit (validated baseline, quick edits)",
          "limit": { "context": 16384, "output": 1536 }
        }
      }
    }
  }
}
```

Note: For probes/baseline reproduction, revert `model` to `mlxlm/qwen3-8b-4bit` and set `mcp.augment-context-engine.enabled=true` temporarily. For daily difficult coding, use config above.

### 3.4 Fix `intent/workspaces/` context explosion

- Ensure operator runs `opencode` from `~/intent/workspaces/<single-repo>` NOT from `~/intent/workspaces/`.
- Add `.opencodeignore` at `~/intent/workspaces/` root containing `*` and in each repo add nothing, OR ensure opencode.json is only in repo root and not in parent.
- Document in QUICK_START.md: "cd into repo before opencode".

### 3.5 Update `.mlxlm/health.sh`

Checks:
- venv version 0.31.3
- /v1/models returns JSON and contains expected short ID
- server RSS < 18GB (ps -o rss)
- log does not contain BatchRotatingKVCache traceback
- If any check fails, print remediation: `.mlxlm/serve.sh stop && .mlxlm/serve.sh start <model>`

### 3.6 Update QUICK_START.md prompting guidance for hard tasks

Add section:

> For difficult coding challenges with local model:
> - Disable Context Engine: set `mcp.augment-context-engine.enabled=false` to save 5-10K context and credits.
> - Use one focused change per exchange. Add to prompt: "Do not use <think> reasoning. Provide diff only. Keep output under 4000 tokens."
> - If `finish=length`, increase output cap to 4096 or switch to 30B-A3B model.
> - If `Prompt exceeds maximum context length`, end session, restart server, start clean - do not retry.

### 3.7 Cost verification

Implement steps from QUICK_START.md Billing & credits:
- Note credit balance before/after BYOA session
- Confirm zero delta when Context Engine disabled
- Confirm only retrieval deltas when enabled

### 3.8 Probes

Run:
```sh
bash .mlxlm/probes/run_probes.sh
cat .mlxlm/probes/summary.txt
```
Expected with 8B: P1,P2,P4 stop, P3 length. With 30B-A3B, P3 should return stop due to larger output cap. Document new baseline in `.mlxlm/probes/baseline_<timestamp>/BASELINE.md`.

## 4. Acceptance Criteria

- [ ] `mlx_lm.server` starts with 30B-A3B model and stays <18GB RSS for 10min under idle
- [ ] `/v1/models` returns short IDs
- [ ] `opencode` in `intent/workspaces/<repo>` does NOT time out on prompt: "Explain this repo's structure in 5 bullets"
- [ ] Difficult task (e.g., refactor a function with tests) completes with `finish=stop` and output <4096 tokens, no BatchRotatingKVCache error in log
- [ ] Credit balance shows zero delta in fully local mode
- [ ] QUICK_START.md updated, serve.sh supports model switch, health.sh passes
- [ ] Probes produce expected summary

## 5. Do NOT Do

- Do not use gpt-oss-20b for tool calling (Harmony channel not parsed by mlx_lm.server)
- Do not run parallel OpenCode sessions against single server
- Do not paste large files into prompt (bypass tool_output caps)
- Do not delegate `git commit/push` to model
- Do not increase max-kv-size beyond 8192 on 24GB machine

## 6. Rollback

If 30B-A3B exceeds memory cap or causes IOGPU/Metal errors:
- `.mlxlm/serve.sh stop`
- `.mlxlm/serve.sh start qwen3-coder-14b-4bit`
- Revert opencode.json model to `mlxlm/qwen3-coder-14b-4bit`
- Capture log per STRATEGY.md stop-rule

End of work order.
