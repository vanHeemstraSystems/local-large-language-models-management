# OPENCODE_REFACTOR.md — Refactored opencode.json for M4 Pro 24GB

This is the drop-in replacement for `<repo>/opencode.json` and for `~/.config/opencode/opencode.json` template. It fixes the timeout on difficult challenges in `intent/workspaces/` -> Warp -> `opencode` workflow.

## Root Cause Fixed

Current file:
- `model: /Users/.../Qwen3-8B-4bit` (full path as ID) + `gpt-oss-20b-MXFP4-Q8` (Harmony channel not parsed by mlx_lm.server) + limits `context:16384 output:1536` + `augment-context-engine` enabled
- Result: Qwen3 <think> exceeds 1536 -> `finish=length` -> retry loop -> 300s timeout

Refactored file:
- Short IDs matching `/v1/models` (not filesystem paths)
- Primary: `qwen3-coder-30b-a3b-4bit` (30B MoE, 3B active, ~16GB RSS, fits 18GB cap) with `output:4096`
- Fallback: `qwen3-coder-14b-4bit` (~8GB) and `qwen3-8b-4bit` (validated baseline)
- MCP disabled by default for zero-cost mode, enable only for retrieval tasks
- Timeout 600s, tool_output enlarged, compaction tuned to preserve recent tokens

## Installation

```sh
# Backup
cp opencode.json opencode.json.bak
cp ~/.config/opencode/opencode.json ~/.config/opencode/opencode.json.bak 2>/dev/null || true

# Overwrite repo root opencode.json with JSON block below
# Then copy same file to global template if you use it for new repos:
cp opencode.json ~/.config/opencode/opencode.json
```

## File: opencode.json

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["@sveltejs/opencode"],
  "permission": {
    "edit": "allow",
    "bash": "allow"
  },
  "model": "mlxlm/qwen3-coder-30b-a3b-4bit",
  "small_model": "mlxlm/qwen3-8b-4bit",
  "enabled_providers": ["mlxlm"],
  "mcp": {
    "augment-context-engine": {
      "type": "local",
      "command": [
        "auggie",
        "--mcp",
        "--mcp-auto-workspace"
      ],
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
    "title": {
      "disable": true
    },
    "summary": {
      "disable": true
    }
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
          "limit": {
            "context": 32768,
            "output": 4096
          }
        },
        "qwen3-coder-14b-4bit": {
          "name": "Qwen3 Coder 14B 4-bit (fallback, 8GB RSS)",
          "limit": {
            "context": 24576,
            "output": 4096
          }
        },
        "qwen3-8b-4bit": {
          "name": "Qwen3 8B 4-bit (validated baseline, quick edits)",
          "limit": {
            "context": 16384,
            "output": 1536
          }
        }
      }
    }
  }
}
```

## Variant: With Context Engine Enabled (for retrieval tasks)

When you need grounded search and are willing to spend retrieval credits (per QUICK_START.md billing table), use this overlay. Create `opencode.with-context.json` or toggle via command:

```json
{
  "mcp": {
    "augment-context-engine": {
      "enabled": true
    }
  }
}
```

Toggle at runtime inside OpenCode TUI:
```
/mcp
> enable augment-context-engine
```

For zero-cost mode:
```
/mcp
> disable augment-context-engine
```

## Variant: For Baseline Probe Reproduction

To reproduce QUICK_START.md baseline `origin/main` (P1,P2,P4 stop, P3 length):

```json
{
  "model": "mlxlm/qwen3-8b-4bit",
  "provider": {
    "mlxlm": {
      "models": {
        "qwen3-8b-4bit": {
          "limit": { "context": 16384, "output": 1536 }
        }
      }
    }
  },
  "mcp": {
    "augment-context-engine": { "enabled": true }
  }
}
```

Run:
```sh
bash .mlxlm/probes/run_probes.sh
cat .mlxlm/probes/summary.txt
```

## Why these numbers

- `context: 32768` for 30B-A3B: Allows one retrieval payload (5-10K) + file + conversation without hitting `Prompt exceeds maximum context length` immediately. Your 24GB can handle 32K KV with max-kv-size 4096.
- `output: 4096`: Qwen3-Coder reasoning <think> is smaller than base Qwen3, but still needs >1536 for hard tasks. 4096 prevents `finish=length` loop that caused timeout.
- `reserved: 2000` (was 5000): Less reserved = more usable context. `preserve_recent_tokens: 8000` (was 4000) = keep last 2 exchanges intact during auto-compaction.
- `tool_output: 500 lines / 32768 bytes`: Up from 200/16384 so test failures don't get truncated and cause retry loops.
- `timeout: 600000`: 10min, up from 300000. Warp also has its own timeout - set Warp Settings > AI > Tool timeout to 300s.
- `title.disable + summary.disable`: Prevents OpenCode from firing parallel title/summary requests that trigger W4 `BatchRotatingKVCache.merge` crash on mlx_lm.server.

## How to use in your workflow

1. Intent GUI: Keep repos under `intent/workspaces/` for navigation
2. `... > Open with Warp` -> `cd` into single repo (critical - not parent)
3. Tab1: `.mlxlm/serve.sh start qwen3-coder-30b-a3b-4bit` + `serve.sh status`
4. Tab2: `opencode` -> prompt: "Do not use <think> reasoning. Provide diff only." for hard tasks
5. If task needs codebase-retrieval: `/mcp enable augment-context-engine` then ask grounded question
6. Commit via Warp shell, not via model: `git diff`, `git add -p`, `git commit`

## Verification

```sh
# 1. Server returns short IDs
curl -s http://127.0.0.1:8080/v1/models | python3 -m json.tool

# 2. OpenCode picks up model
opencode --print-logs 2>&1 | head -20

# 3. Inside OpenCode, test:
# > What models are available? Use the local ones only.

# Expected: Should answer without calling augment-context-engine when disabled, finish=stop, no timeout.
```

## Cost Impact

- Fully local mode (MCP disabled): $0 - per Intent pricing guide BYOA path
- BYOA + Context Engine (MCP enabled): Only retrieval credits, no model token credits
- Previous: 8B + auto-workspace + 16K/1.5K caps caused retries that wasted time and made you fall back to Augment native agents (credit-consuming)

This refactor is the implementation of ADVISE_REFACTOR.md Section 3.3.
