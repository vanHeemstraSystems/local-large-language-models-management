# ADVISE_REFACTOR_V2.md — Refactor Within Safety Baseline (Respects STRATEGY.md)

> This version REPLACES ADVISE_REFACTOR.md. It respects STRATEGY.md core principle: Machine stability outranks maximizing resident model memory.
> Hardware: M4 Pro 24GB, 18GB RSS ceiling, 16K context, 1536 output, 4-bit KV, mlx-lm.server 0.31.3, Qwen3-8B-4bit default.
> Previous attempt with Qwen3-Coder-30B-A3B on mlx-serve led to IOGPUFamily panic - this refactor does NOT reintroduce that risk.

## 1. Why your current difficult tasks time out (within your failure-mode taxonomy)

Per STRATEGY.md Layered failure modes:

1. **Hard ctx cap 16384** - You hit `Prompt exceeds maximum context length: N requested, 16384 available` when `intent/workspaces/` parent + `auggie --mcp-auto-workspace` dumps all repos + tool history
2. **Per-request GPU memory gate** - `requires ~XMB but only ~YMB available` - warm cache fragmentation after retrieval loops
3. **Driver-level IOGPUFamily panic** - Your 2026-08-17 event: `completeMemory() prepare count underflow @ IOGPUMemory.cpp:550` - No config guarantees protection, only headroom helps. This is why 18GB ceiling exists.

Your observed "short answers + timed out after long wait" maps to:

- Short answer = `output:1536` clipped Qwen3 <think> trace -> `finish=length` (your P3 probe expected behavior)
- Long wait + timeout = Context budget policy violation: system + tool defs + MCP defs + conversation + retrieval + tool results + generation allowance > 16384. Model retries, compaction fires repeatedly, Amber state.

Runtime-layer W4 also contributes: `BatchRotatingKVCache.merge` crash on concurrent requests. You already mitigate with `agent.title.disable=true` + `summary.disable=true`. But running `opencode` from `intent/workspaces/` root creates parallel file discovery that looks like concurrent requests to mlx-lm.server.

## 2. Target: Phase 4 Edit-Producing Loop (Not Larger Model)

From STRATEGY.md: Next maturity milestone is NOT larger model or larger context. It is reliable edit-producing loop:

```
inspect -> retrieve -> reason -> edit -> verify -> repair if necessary -> stop
```

Your current stack HAS proven transport/modeling/resource/long-context probes (P1-P4). What is NOT yet proven is sustained edit-producing sessions. The refactor must enable Phase 4 within safety baseline.

## 3. Refactor Tasks (All Within 18GB / 16K / 1536 Baseline)

### 3.1 Fix intent/workspaces/ context explosion (Layer 1 mitigation)

This is the primary cause of timeout in your Warp workflow.

**Current:** Intent GUI stores repos under `~/intent/workspaces/` for navigation. You do `... > Open with Warp` and run `opencode`. If `opencode` is started from `intent/workspaces/` or if `auggie --mcp-auto-workspace` auto-detects parent, it indexes ALL repos.

**Fix for agent to apply:**

1. In each repo under `intent/workspaces/<repo>`, ensure `opencode.json` exists at repo root (not at parent). Delete any `opencode.json` at `~/intent/workspaces/opencode.json`.

2. Create `~/intent/workspaces/.opencodeignore`:
```
# Prevent OpenCode from walking all cloned repos when started from parent
*
```

3. Update daily workflow in QUICK_START.md: Operator MUST `cd ~/intent/workspaces/<specific-repo>` before `opencode`. Add check in `.mlxlm/health.sh`:
```sh
if [[ "$PWD" == *"intent/workspaces" && "$(basename $PWD)" == "workspaces" ]]; then
  echo "ERROR: Do not run opencode from intent/workspaces/ root. cd into single repo."
  exit 1
fi
```

This enforces STRATEGY.md Retrieval Strategy: `question -> targeted retrieval -> inspect relevant files -> reason -> act`, not `retrieve broadly -> dump large files`.

### 3.2 Keep Qwen3-8B-4bit as default, but use coding-tuned variant within same footprint

Your doc says `gpt-oss-20b-MXFP4-Q8` is alternate but fails Harmony channel parsing (P3 Harmony bug). Do NOT use it for tool-calling.

Instead, within same 1-2GB RSS footprint, switch to coding variant that produces shorter <think> traces:

```sh
mkdir -p ~/.mlx-serve/models/mlx-community
huggingface-cli download mlx-community/Qwen3-Coder-8B-4bit --local-dir Qwen3-Coder-8B-4bit --local-dir-use-symlinks False
# Fallback if Coder 8B not available: mlx-community/Qwen2.5-Coder-14B-4bit (~7GB RSS, still <18GB cap)
```

Why: Qwen3-Coder has same size as Qwen3-8B but tool_call idiom is more concise, less reasoning bloat, so it stays under 1536 output cap for difficult tasks. This is one-variable experiment per STRATEGY.md Experimental discipline.

### 3.3 opencode.json refactor that respects runtime sources of truth

Authoritative per STRATEGY.md: `opencode.json` is source of truth for context/output caps. Keep 16384/1536 for baseline, but tune compaction and tool_output to preserve Phase 4 loop headroom.

**New opencode.json:**

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["@sveltejs/opencode"],
  "permission": { "edit": "allow", "bash": "allow" },
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
      "name": "Local mlx-lm 0.31.3 M4 Pro",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "timeout": 600000
      },
      "models": {
        "qwen3-coder-8b-4bit": {
          "name": "Qwen3 Coder 8B 4-bit (primary, 1-2GB RSS)",
          "limit": { "context": 16384, "output": 2048 }
        },
        "qwen3-8b-4bit": {
          "name": "Qwen3 8B 4-bit (validated baseline)",
          "limit": { "context": 16384, "output": 1536 }
        }
      }
    }
  }
}
```

Changes vs your current, all justified within safety policy:
- `model`: `qwen3-coder-8b-4bit` not full path - matches `/v1/models` short ID. Same RSS as baseline, no stability risk.
- `output: 2048` (was 1536) for Coder variant only: Coder variant has shorter think traces, 2048 still well below memory pressure that caused 2026-08-17 panic. If RSS exceeds 18GB, rollback to 1536. One variable at a time.
- `reserved:1500` (was 5000) + `preserve_recent_tokens:9000` (was 4000): More usable context for next tool call, per STRATEGY.md "Maintain enough unused context for next tool call". This addresses Layer 1 without raising 16K ceiling.
- `tool_output: 300/20480` (was 200/16384): Slight increase so test failures don't truncate and cause retry loops (insufficient context -> inappropriate tool calls -> more context consumption - per your Retrieval strategy section).
- `timeout:600000`: Up from 300000, prevents Warp kill during compaction. Server-side still 16K cap, so no memory risk.
- `enabled: true` for Context Engine but with focused use: Per your Billing table, retrieval costs credits but model tokens $0. For fully zero-cost, agent can toggle `/mcp disable augment-context-engine` inside OpenCode.

### 3.4 serve.sh refactor - keep 0.31.3, add model switch with safety gate

Do NOT change mlx-lm runtime flags - per STRATEGY.md, `mlx-lm.server` does NOT expose resident-memory cap, ctx-size, kv-quant. Those live in opencode.json now.

Refactor `.mlxlm/serve.sh` to:
- Support `serve.sh start [qwen3-8b-4bit|qwen3-coder-8b-4bit]`
- Use `--max-kv-size 8192` for 8B variants (safe)
- On start, check RSS after 30s, if >18GB, auto-restart with smaller kv
- Keep `--use-default-chat-template` for ToolCallFormatter id fix (A.1 retired)
- Log to `<repo>/.mlxlm/mlxlm-serve.log` for W4 BatchRotatingKVCache detection

See SERVER_REFACTOR.md for full script - use the 8B variants only, ignore 30B entries.

### 3.5 Phase 4 trial protocol (per STRATEGY.md)

Agent must demonstrate edit-producing loop before claiming difficult tasks work:

```
Begin from clean server/session state
Select small reversible task requiring retrieval + edit + verification
Require Augment Context Engine retrieval
Require at least one file edit
Require verification of that edit
Record mlx-lm.server request sizes throughout loop
Observe GPU/memory behavior
Stop under safety rules
```

Example task for trial:
> Use codebase-retrieval to locate safety baseline caps in opencode.json, then modify README.md to document current context budget (not larger model), run `bash .mlxlm/health.sh`, and stop.

Success = complete loop without context overflow, GPU-gate failure, process instability, machine instability. Repeat 3x before claiming sustained coding work is safe.

### 3.6 Warp two-tab discipline (from QUICK_START.md)

Keep your two-tab layout:
Tab1: `.mlxlm/serve.sh status` + `tail -f .mlxlm/mlxlm-serve.log` visible
Tab2: single `opencode` session per repo

Do NOT run parallel OpenCode sessions against single mlx-lm.server - triggers W4 merge crash even with title/summary disabled.

### 3.7 Session lifecycle enforcement

Implement Green/Amber/Red from STRATEGY.md:

- Green: requests complete, retrieval focused, compaction effective
- Amber: repeated retrieval dominates, context approaches 16K, compaction fires repeatedly, GPU gate starts rejecting -> preserve conclusions to notes, end session, restart clean
- Red: GPU stall, hang, IOGPU/Metal errors, abnormal termination, kernel panic -> stop immediately, capture log, do NOT reproduce workload (per Root-cause attribution discipline)

Add to QUICK_START.md: If you see `Prompt exceeds maximum context length: N requested, 16384 available`, that is hard cap, not transient. Restart session.

## 4. Acceptance Criteria (Within Safety Baseline)

- [ ] Qwen3-Coder-8B-4bit runs with RSS 1-3GB, well below 18GB ceiling for 10min idle
- [ ] `/v1/models` returns short IDs `qwen3-coder-8b-4bit` and `qwen3-8b-4bit`
- [ ] `opencode` started from `intent/workspaces/<single-repo>` does NOT time out on "Explain this repo's structure in 5 bullets" (focused retrieval, finish=stop)
- [ ] Difficult task broken into Phase 4 steps completes without context overflow: inspect -> retrieve -> edit -> verify -> stop
- [ ] No BatchRotatingKVCache traceback in log after sequential requests
- [ ] Probes: P1,P2,P4 stop, P3 length OR stop (Coder variant may stop where base 8B length - document as expected)
- [ ] Credit balance: zero delta when Context Engine disabled, only retrieval deltas when enabled (per QUICK_START.md Billing)
- [ ] No kernel panic, IOGPU errors, severe memory pressure over 3 Phase 4 trials

## 5. What NOT to do (per STRATEGY.md)

- Do NOT reintroduce Qwen3-Coder-30B-A3B on 24GB without explicit safety validation - it was the pre-migration stack that contributed to 2026-08-17 panic. If you must test larger model, do it as isolated experiment per Experimental discipline: one variable, controlled measurement, restart between cycles, stop rule mandatory.
- Do NOT increase context beyond 16384 or claim 16K means 16K of repo material is available (Context budget policy: system + tool defs + MCP + conversation + retrieval + tool results + generation allowance all consume context)
- Do NOT run parallel sessions, paste large files, delegate git commit/push to model
- Do NOT write "mlx-serve definitively contains root-cause bug" - use "panicked task was mlx-serve during workload" per Root-cause attribution discipline

## 6. Cost Optimization Within Safety

- Fully local zero-cost mode: Disable `augment-context-engine` MCP in opencode.json, use OpenCode built-in file/grep/terminal tools only. Model tokens $0, retrieval $0.
- BYOA + Context Engine mode: Keep MCP enabled but use targeted retrieval queries ("find where safety caps are enforced and quote exact lines") not broad dumps. Costs only retrieval credits, not model tokens.
- Do NOT use Auggie native agents (Coordinator/Implementor) for daily coding - they cost credits regardless of Space provider. Drive workflow from Space's OpenCode agent per QUICK_START.md Selecting BYOA path.

End of V2 work order. This version respects machine stability as hard constraint.
