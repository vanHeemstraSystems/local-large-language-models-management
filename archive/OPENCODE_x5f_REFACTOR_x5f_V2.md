# OPENCODE_REFACTOR_V2.md — Refactored opencode.json (Respects STRATEGY.md Safety Baseline)

> Replaces OPENCODE_REFACTOR.md
> Core principle: Machine stability outranks maximizing memory
> Runtime sources of truth per STRATEGY.md: opencode.json is authoritative for provider endpoint, default model, context/output limits, side-band config, compaction, tool_output, MCP
> Baseline: 18GB RSS ceiling (operator discipline), 16384 context, 1536 output, 4-bit KV, Qwen3-8B-4bit default, mlx-lm.server 0.31.3

## Installation

```sh
cp opencode.json opencode.json.bak
# Overwrite repo root opencode.json with JSON below
# For template for new repos:
cp opencode.json ~/.config/opencode/opencode.json
```

## File: opencode.json - V2 Safe Baseline

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["@sveltejs/opencode"],
  "permission": {
    "edit": "allow",
    "bash": "allow"
  },
  "model": "mlxlm/qwen3-coder-8b-4bit",
  "small_model": "mlxlm/qwen3-coder-8b-4bit",
  "enabled_providers": ["mlxlm"],
  "mcp": {
    "augment-context-engine": {
      "type": "local",
      "command": ["auggie", "--mcp", "--mcp-auto-workspace"],
      "enabled": true
    }
  },
  "compaction": {
    "auto": true,
    "prune": true,
    "reserved": 1500,
    "preserve_recent_tokens": 9000
  },
  "tool_output": {
    "max_lines": 300,
    "max_bytes": 20480
  },
  "agent": {
    "title": { "disable": true },
    "summary": { "disable": true }
  },
  "provider": {
    "mlxlm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local mlx-lm 0.31.3 M4 Pro Safe Baseline",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "timeout": 600000
      },
      "models": {
        "qwen3-coder-8b-4bit": {
          "name": "Qwen3 Coder 8B 4-bit (primary - same RSS as baseline, better coding)",
          "limit": {
            "context": 16384,
            "output": 2048
          }
        },
        "qwen3-8b-4bit": {
          "name": "Qwen3 8B 4-bit (validated baseline origin/main)",
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

## Why this respects STRATEGY.md

- **Model:** `qwen3-coder-8b-4bit` is same size class as `qwen3-8b-4bit` (1-2GB RSS), well below 18GB cap. No reintroduction of 30B-A3B that caused pre-migration panic. One-variable experiment: Coder variant vs base variant.
- **Context: 16384:** Unchanged from safety baseline. Per STRATEGY.md "Context is a budget, not a target" - 16K is ceiling, not working set. System + tool defs + MCP + conversation + retrieval + tool results + generation allowance all consume it. Do NOT claim 16K of repo material available.
- **Output: 2048 for Coder only:** Base 8B stays at 1536 (your validated P3 behavior). Coder variant has shorter <think> traces, so 2048 allows it to complete difficult tasks with `finish=stop` instead of `finish=length` retry loop that caused timeout. If RSS exceeds cap or IOGPU errors appear, rollback to 1536 immediately per stop-rule.
- **reserved:1500 (was 5000) + preserve_recent_tokens:9000 (was 4000):** Addresses STRATEGY.md operating objective: "Maintain enough unused context for next tool call and its result." Less reserved = more usable, more preserved recent = Amber state less likely. No increase in hard cap.
- **tool_output: 300/20480 (was 200/16384):** Slight increase so test failures don't truncate and cause model to perform additional inappropriate tool calls (per Retrieval strategy: insufficient context -> more tool calls -> more context consumption).
- **timeout:600000:** 10min, up from 300000. Prevents Warp kill during compaction. Does NOT increase GPU memory, only client wait time. Also set Warp Settings > AI > Tool timeout to 300s.
- **title.disable + summary.disable:** Required W4 mitigation for `BatchRotatingKVCache.merge` crash on concurrent requests with different prompt lengths. Serializes one session's traffic, does NOT protect against second client - hence two-tab Warp layout with single opencode session.
- **MCP enabled:true:** Default per QUICK_START.md is BYOA + Context Engine (retrieval credits only, model $0). For fully zero-cost mode per billing table, operator toggles inside OpenCode: `/mcp disable augment-context-engine`. Then OpenCode falls back to built-in file/grep/terminal tools.

## Variant: Fully Local Zero-Cost Mode

Create `opencode.local.json` or toggle at runtime:

```json
{
  "mcp": {
    "augment-context-engine": {
      "enabled": false
    }
  }
}
```

Inside OpenCode TUI:
```
/mcp
> disable augment-context-engine
```

Cost: $0 model + $0 retrieval. Loses Augment semantic search, keeps file tools.

Per QUICK_START.md Verifying no credits consumed: Check balance at app.augmentcode.com before/after. Disabled session should show zero delta.

## Variant: Baseline Probe Reproduction (origin/main)

To reproduce committed baseline before Phase 4 trials:

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

```sh
bash .mlxlm/probes/run_probes.sh
cat .mlxlm/probes/summary.txt
# Expected: P1,P2,P4 exit 0 finish=stop; P3 exit 0 finish=length (documented Qwen3 behavior, not regression)
```

## How to Prompt for Difficult Challenges Within Safety (Phase 4)

From STRATEGY.md, context budget policy: Don't bundle unrelated asks. One focused change per exchange.

Instead of: "Refactor entire module to handle edge cases and add tests"

Do Phase 4 loop:

1. **inspect:** "Use codebase-retrieval to find where safety baseline caps are enforced and quote exact lines"
2. **retrieve + reason:** Let model reason over result (finish=stop expected)
3. **edit:** "Modify function X in path/to/file to Z. Show diff only. Do not touch other files."
4. **verify:** "Run <tests|lint|build> from repo root and report only failing lines"
5. **repair if necessary + stop:** Preserve conclusions to notes, end session, restart clean

Add to prompt for hard tasks:
> Do not use <think> reasoning trace. Provide diff only. Keep output under 2000 tokens. Do not summarize other files.

This keeps request + tool result within 16384 and output within 2048, preventing Layer 1 hard cap and Layer 2 GPU gate rejection.

## Cost Impact Within Safety

- **Fully local:** $0 - BYOA provider is local, $0 per Intent pricing guide
- **BYOA + Context Engine:** Only retrieval credits, no chat/completion token credits
- **Previous timeout cost:** When 8B timed out due to context explosion from intent/workspaces root + broad retrieval, operator fell back to Auggie native agents (Coordinator/Implementor) which cost credits per QUICK_START.md billing table. This refactor prevents fallback by fixing context budget.

## Verification Checklist (Acceptance per STRATEGY.md)

- [ ] `curl http://127.0.0.1:8080/v1/models` returns short IDs `qwen3-coder-8b-4bit`, `qwen3-8b-4bit` (not filesystem paths)
- [ ] `.mlxlm/serve.sh status` shows RSS 1000-3000MB < 18432MB cap, no BatchRotatingKVCache traceback
- [ ] `opencode` started from `intent/workspaces/<single-repo>` (not parent) completes "Explain repo structure in 5 bullets" with finish=stop
- [ ] Difficult task broken into Phase 4 steps: inspect->retrieve->reason->edit->verify->stop completes without context overflow, GPU-gate failure, process instability
- [ ] No IOGPU/Metal errors, kernel panic over 3 Phase 4 trials
- [ ] Probes: P1,P2,P4 stop, P3 length or stop (documented)
- [ ] Credit balance zero delta in fully local mode

## What NOT to do

- Do NOT increase context beyond 16384 without explicit safety validation per Experimental discipline (hypothesis -> isolated change -> controlled measurement -> observation -> verification -> documentation -> baseline decision)
- Do NOT reintroduce 30B model without isolated experiment and stop-rule monitoring
- Do NOT run parallel OpenCode sessions against single mlx-lm.server
- Do NOT paste large files into prompt (bypasses tool_output caps and blows context)
- Do NOT delegate git commit/push to model

This file implements ADVISE_REFACTOR_V2.md Section 3.3 and respects STRATEGY.md configuration authority: opencode.json is authoritative for runtime-facing values, STRATEGY.md for why.
