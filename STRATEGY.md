# STRATEGY

Operating strategy for the local-LLM stack on this 24 GB Mac mini M4 Pro. This document is the short, operator-focused summary of *how* we run and tune the stack safely. Detailed evidence lives in the workspace spec and task notes; the concrete OpenCode + Augment Context Engine context-budget numbers live in the "Context budget policy" section of `README.md`.

## Core principle

**Machine stability outranks maximizing resident model memory or context capacity.**

A local LLM that occasionally kernel-panics the machine is not usable, no matter how much context or how many tokens/second it delivers. Every tuning decision below is subordinate to this principle.

## Strategic objective

The objective of this repository is not merely to run a large language model locally.

The objective is to establish a practical, reproducible, and safe **local software-engineering agent stack** in which:

- the coding agent provides the interaction and agent loop;
- repository context is retrieved deliberately rather than placed wholesale into every prompt;
- the language model performs inference locally on the Mac mini;
- tool calls provide controlled access to the repository and development environment;
- context growth is actively managed;
- machine stability is treated as a hard operational constraint.

The currently proven architecture is:

```
Developer
    |
    v
Warp / terminal environment
    |
    v
OpenCode
    |
    +---- built-in coding tools
    |
    +---- Augment Context Engine MCP
    |         |
    |         +---- repository retrieval
    |
    v
OpenAI-compatible API
    |
    v
mlx-lm.server (v0.31.3, ~/.mlxlm/venv)
    |
    v
Qwen3-8B-4bit (default)  //  gpt-oss-20b-MXFP4-Q8 (alternate)
    |
    v
MLX / Metal
    |
    v
Apple M4 Pro unified memory (24 GB)
```

The architectural separation is intentional:

> Augment provides relevant context; Qwen provides local intelligence; OpenCode provides the agent loop; mlx-lm.server provides local inference.

No component should be asked to perform a responsibility that another layer can perform more efficiently or safely.

Runtime migration note: this stack originally ran on `mlx-serve` with `Qwen3-Coder-30B-A3B-Instruct-4bit`. It was migrated to `mlx-lm 0.29.1` because `mlx-serve` does not carry the `gpt_oss` architecture and because `mlx-lm.server` is the actively-maintained upstream OpenAI-compatible runtime. The historical `mlx-serve`/`Qwen3-Coder-30B` references retained in this document (root-cause attribution, order-of-operations) describe events on the pre-migration stack and remain historically accurate.

## Current maturity

The stack should be described according to demonstrated capability rather than intended capability.

### Proven

The following have been demonstrated end-to-end:

- OpenCode can use the local `mlx-lm.server` endpoint (mlx-lm 0.31.3's upstream `ToolCallFormatter` supplies OpenAI-spec-compliant `tool_calls[].id` values natively; the historical A.1 venv patch that used to fix this on 0.29.1 is now retired — see `.mlxlm/PATCHES.md`).
- Qwen3-8B-4bit can receive OpenCode tool definitions.
- The model can request a tool.
- OpenCode can execute the tool.
- The tool result can be returned to the model.
- The model can reason over that result and stop naturally.
- Augment Context Engine can be exposed through MCP.
- Qwen can invoke codebase retrieval when repository context is required.
- Retrieved repository context can be used to produce a grounded answer.
- OpenCode compaction can materially reduce conversation context.
- Context and retrieval costs have been measured under real agent workloads.
- A four-probe baseline (transport / modeling / resource / long-context) passes cleanly against the patched runtime on `origin/main`; artifacts under `.mlxlm/probes/baseline_postmerge_*`.

This establishes a functioning local retrieval-augmented agent loop.

### Not yet proven

The following must not yet be treated as production-proven:

- sustained edit-producing coding sessions;
- repeated inspect → retrieve → edit → test → repair loops;
- long-running autonomous agent operation;
- long-horizon stability under sustained GPU load;
- safe operation close to the theoretical 16K context limit;
- kernel-panic-free operation over extended workloads.

The next maturity milestone is therefore not a larger model or larger context.

It is a reliable edit-producing loop:

```
inspect
   ↓
retrieve
   ↓
reason
   ↓
edit
   ↓
verify
   ↓
repair if necessary
   ↓
stop
```

This loop should be demonstrated repeatedly before the stack is described as suitable for sustained coding work.

## Configuration authority

Repeated configuration values across documentation and configuration files create drift risk.

The runtime configuration files are authoritative for machine-consumed values.

### Runtime sources of truth

`opencode.json`

Authoritative for both the runtime-facing and OpenCode-facing configuration on the current stack, including:

- provider endpoint (`http://127.0.0.1:8080/v1`);
- default model (`Qwen3-8B-4bit`);
- per-model context/output limits (`context: 16384`, `max_output_tokens: 1536`) — these are what enforce the safety baseline caps now that the runtime CLI does not;
- side-band agent configuration (title/summary disabled as the W1 concurrency workaround);
- compaction configuration;
- tool-output limits;
- MCP configuration.

The `mlx-lm.server` CLI surface (see `python -m mlx_lm server --help`) is intentionally small. On mlx-lm 0.31.3 it exposes `--prompt-cache-bytes`, `--prompt-cache-size`, and `--prefill-step-size` (passed by `.mlxlm/serve.sh`), but it does **not** expose a resident-memory cap, a context-size cap, a KV-cache quantisation flag, or a PLD toggle. The 16384 / 1536 caps live on the client side in `opencode.json`; the 18 GB cap is measured by `.mlxlm/health.sh` rather than enforced by the server; 4-bit KV quantisation remains policy only. See *Safety-revised memory baseline* for the per-item table. `scripts/mlxserve.sh` is retained in the repository only for historical reference against the pre-migration stack.

`.mlxlm/PATCHES.md`

Historical record of the retired A.1 venv patch (mlx-lm 0.29.1) and its rollback path. On the current mlx-lm 0.31.3 stack the upstream `ToolCallFormatter` emits OpenAI-spec-compliant `tool_calls[].id` values on its own, so no venv patch is applied or needed. Rollback to the patched 0.29.1 stack is by restoring the preserved `~/.mlxlm/venv-py39-mlxlm0291.bak` venv, not by re-applying the patch by hand.

### Documentation

`STRATEGY.md` is authoritative for:

- why those settings exist;
- operational safety principles;
- experimental discipline;
- failure interpretation;
- tuning order;
- maturity criteria.

`README.md` is the operator-facing guide and should summarize the current configuration and measured context budget.

If README or STRATEGY disagrees with a runtime configuration file about the actual configured value, the runtime configuration is authoritative and the documentation must be corrected.

Measured historical values should remain clearly identified as measurements rather than configuration.

## Daily operating mode

Normal coding sessions should optimize for reliability rather than maximum context utilization.

Recommended operating behaviour:

1. Start from the committed, verified baseline.
2. Start `mlx-lm.server` before beginning the coding-agent session (via the local venv, e.g. `~/.mlxlm/venv/bin/python -m mlx_lm server --host 127.0.0.1 --port 8080 --log-level INFO`).
3. Confirm that the expected model appears at the first request in the `mlx-lm.server` startup log. On the current mlx-lm 0.31.3 stack no local A.1 patch is required (`.mlxlm/PATCHES.md`).
4. Start OpenCode with only the tools/MCP services required for the task.
5. Prefer repository retrieval over manually injecting large files into the conversation.
6. Keep individual retrieval results focused.
7. Allow OpenCode compaction to control conversation growth.
8. Start a fresh session when context becomes dominated by historical tool results or repeated retrieval.
9. Treat GPU-memory-gate rejection as a signal to reduce/restart, not as a challenge to bypass.
10. Stop immediately if the machine exhibits the safety symptoms documented below.

`mlx-lm.server` does not carry `mlx-serve`'s PLD (Prompt Lookup Decoding) toggle. Its speculative-decoding path is opt-in via `--draft-model` / `--num-draft-tokens` and is **disabled by default**, so the sustained-workload precaution that previously required `MLXSERVE_EXTRA_ARGS=--no-pld` is now the runtime's out-of-the-box behaviour. If speculative decoding is ever enabled on the new runtime, treat the same experimental discipline as the historical PLD toggle.

## Context is a budget, not a target

`16384` is a protocol/runtime ceiling. It is not a recommended working-set size.

Every OpenCode request consumes context from several sources:

```
system instructions
+ coding-agent instructions
+ tool definitions
+ MCP definitions
+ user conversation
+ assistant conversation
+ retrieved repository context
+ tool results
+ generation allowance
```

Consequently, a nominal 16K model context does not mean that 16K tokens of repository material are available.

The measured initial OpenCode + Augment envelope already consumes a substantial fraction of the available context before repository retrieval occurs.

The operating objective is therefore:

> Maintain enough unused context for the next tool call and its result.

Do not optimize for the largest prompt that `mlx-lm.server` can accept once. Optimize for enough headroom to complete the next agent-loop transition.

A request that fits but leaves insufficient room for its tool result is not operationally useful.

## Retrieval strategy

Repository retrieval should reduce context consumption, not recreate the entire repository inside the conversation.

Prefer:

```
question
   ↓
targeted retrieval
   ↓
inspect relevant files
   ↓
reason
   ↓
act
```

Avoid:

```
retrieve broadly
   ↓
retrieve again
   ↓
dump large files
   ↓
retain every tool result
   ↓
hit context/GPU limit
```

Retrieval payload limits should therefore be treated as part of the agent architecture, not merely as performance tuning.

However, excessively aggressive truncation is also unsafe operationally. Experiments showed that insufficient context can cause the model to perform additional or inappropriate tool calls, ultimately consuming more context than the larger original retrieval would have consumed.

The goal is **sufficient minimal context**, not minimal context.

## Session lifecycle

A local agent session should not be assumed to have unlimited useful life.

Use three conceptual states:

### Green — continue

- requests complete normally;
- retrieval is focused;
- compaction is effective;
- sufficient context headroom remains;
- no GPU-memory warnings occur.

### Amber — compact or restart

- repeated retrieval results dominate history;
- the session approaches the measured reliable context region;
- compaction has occurred repeatedly;
- the GPU memory gate begins rejecting otherwise reasonable requests;
- responses become dominated by attempts to recover missing context.

Preferred response:

1. preserve important conclusions in repository files or notes;
2. end the current agent session;
3. restart from a clean context;
4. retrieve only what the next task requires.

### Red — stop the workload

- GPU stalls;
- `mlx-lm.server` hangs;
- severe memory pressure;
- IOGPU/Metal errors;
- abnormal process termination;
- kernel panic or reboot.

Do not immediately reproduce the workload.

Capture evidence first.

## Safety-revised memory baseline

The 18 GB safety envelope survives the migration; only the enforcement mechanism changed. **Enforcement (pre-migration):** `scripts/mlxserve.sh` set `--max-resident-mem 18GB`, `--ctx-size 16384`, `--max-tokens 1536`, `--kv-quant 4`, `--prefill-chunk 1024`, `--skip-mem-preflight` on the `mlx-serve` binary. **Enforcement (current)** is split across three components; the table below records who enforces each baseline item on the mlx-lm 0.31.3 stack.

| Baseline item | Value | Enforced by | Mechanism |
| --- | --- | --- | --- |
| Physical-footprint ceiling | 18 GB | `.mlxlm/health.sh` (measurement gate) | Reads `/usr/bin/footprint` for the server PID; FAIL if ≥ 18 GB. Not server-side; not enforced by `mlx-lm.server`. |
| Context window | 16,384 tokens | `opencode.json` | Provider `context: 16384`. `mlx-lm.server` has no context-size flag on 0.31.3. |
| Max output tokens | 1,536 tokens | `opencode.json` | Provider `max_output_tokens: 1536`. `mlx-lm.server` `--max-tokens` is a default, not a cap; OpenCode is authoritative. |
| KV-cache quantisation | 4-bit | Policy only (aspiration) | mlx-lm 0.31.3 `python -m mlx_lm server --help` exposes no `--kv-quant`-equivalent flag. Documented here so a future runtime that re-exposes it can be adopted. |
| Prompt-cache size (bytes) | 6 GB | `.mlxlm/serve.sh` | `--prompt-cache-bytes 6442450944` on the running server; override `MLXLM_PROMPT_CACHE_BYTES`. |
| Prompt-cache size (sequences) | 4 | `.mlxlm/serve.sh` | `--prompt-cache-size 4`; override `MLXLM_PROMPT_CACHE_SIZE`. |
| Prefill step size | 1,024 | `.mlxlm/serve.sh` | `--prefill-step-size 1024` (mlx-lm default is 2048); override `MLXLM_PREFILL_STEP_SIZE`. |

The 18 GB policy was introduced after the 2026-08-17 IOGPUFamily kernel panic observed during an `mlx-serve` workload on the pre-migration stack. See "Root-cause attribution discipline" below for the evidence and the deliberately limited conclusions that may be drawn from it. Reducing the ceiling from 20 GB to 18 GB remains the least-invasive lever that increases headroom on the 24 GB envelope, and applies to any future model added to `opencode.json` regardless of runtime.

### 2026-10-06 prompt-cache and footprint findings

- With Composio attached and no server-side prompt-cache cap, prompt cache grew to **11.42 GB** before a Metal OOM. Server-side caps `--prompt-cache-bytes 6442450944` (6 GB) and `--prompt-cache-size 4` were adopted in `.mlxlm/serve.sh` to bound this growth.
- `ps -o rss=` under-reports unified memory on Apple Silicon by roughly **2.4 GiB** versus `/usr/bin/footprint`. `.mlxlm/health.sh` therefore gates on physical footprint, not RSS; RSS stays in the log line as informational only.
- Observed peak **physical footprint 11 GiB** during the three-run edit test with prompt cache at **5.53 GB** — well under the 18 GB ceiling and inside the 6 GB cache cap.

## Memo 7–17 decisions

Memos 7–17 were authored across several weeks and partially predate the current stack (`mlx-lm.server` 0.31.3, Qwen3-8B-4bit on `127.0.0.1:8080/v1`, Python 3.12.13, 18 GB / 16384 safety envelope). The following reconciliation points record how each memo is being applied, corrected, or deferred so that later waves build on a written decision rather than on memo text that no longer matches the stack. Each point names the memo(s) it corrects.

1. **Runtime and default model (corrects memos 8, 11, 14, 15, 16, 17).** The production runtime is `mlx-lm.server` 0.31.3 on `127.0.0.1:8080/v1`; the validated default coding model is `Qwen3-8B-4bit`. MLXServe on `:11234` and `Qwen3-Coder-30B-A3B-Instruct-4bit` are legacy and excluded from the safety baseline. Any memo text that assumes the legacy runtime or the 30B Coder model does not override the current stack.
2. `tool_calls[].id`** is no longer null (corrects memos 9, 10, 11, 12).** `mlx-lm` 0.31.3 ships an upstream `ToolCallFormatter` that emits OpenAI-spec-compliant `tool_calls[].id` values; the historical A.1 venv patch is retired (`.mlxlm/PATCHES.md`). The regression is retained only as a protocol-harness check, not as an open issue.
3. **Memo 11 baseline numbers are stale (corrects memo 11).** The current baseline items and their per-item enforcement are listed in *Safety-revised memory baseline* above (18 GB footprint, 16,384 context, 1,536 max output, 4-bit KV, 1,024-token prefill step, 6 GB / 4-sequence prompt-cache caps); memo 11's single-knob wording does not reflect that the 18 GB cap is a measurement gate, the context/output caps are client-side, and 4-bit KV has no 0.31.3 server flag. Memo 11 phases 1–9 are substantially complete through prior waves; what remains from memo 11 is §14 (one-command diagnostic), §16 (local-first routing policy, adopted below), and §17 (cost/outcome telemetry).
4. **Warp-as-agent-harness is blocked; OpenCode is the harness (corrects memo 8).** Warp's custom-inference endpoint rejects `localhost` and Warp Agent Mode is paid cloud AI, so memo 8 Phase 5 (Warp → local inference) is not pursued. The adopted adaptation keeps OpenCode as the agent/orchestrator and attaches Composio Connect as an MCP server in `opencode.json` (user-approved 2026-10-06).
5. **LiteLLM is not introduced (corrects memo 10).** OpenCode talks directly to `mlx-lm.server`; no routing proxy is added to the stack.
6. **Single-session discipline rules out parallel local agents (corrects memos 10 and 14).** On this 24 GB machine only one inference server and one OpenCode session run at a time. Orca (memo 10) is deferred for this reason, and Herdr (memo 14) is evaluated with exactly one session rather than the multi-session shape the memo originally proposed.
7. **OpenCode Go pricing verified; default escalation model = Kimi K3 (closes memo 17 §8).** Public OpenCode Go pricing checked on 2026-10-06: $10/month; `opencode-go/kimi-k3` carries a $15/month included-usage limit; `Kimi K2.7 Code` is $60/month. User decision (2026-10-06): default escalation model is **Kimi K3 (**`opencode-go/kimi-k3`**)**; Kimi K2.7 Code is not configured; the pay-per-token Moonshot API is not configured.
8. **Composio accepted with scope caveat (acts on memo 8).** User decision (2026-10-06): Composio Connect may be attached to OpenCode; tool calls and GitHub data may transit Composio's cloud; **model inference stays local**. A Composio SDK/session integration is explicitly out of scope; only the Connect MCP endpoint is used. Composio is **enabled by default** as of 2026-10-06 (user decision), with the operating rule that Composio tools run only on `opencode-go/kimi-k3` sessions; local-model sessions remain viable only when Composio tools are not loaded. Per-agent tool filtering is now in `opencode.json` via `agent.local.permission.composio_*: deny` (default) and `agent.escalation.permission.composio_*: allow` with `default_agent: "local"`, so the local-model first-turn envelope stays ≈6.5K while the `escalation` agent keeps the full Composio tool manifest.
9. **Jev automation is deferred; the Good-Enough Model principle is adopted now (acts on memos 12 and 15).** Automated routing to an external service (memo 12 Phases 2–5) is deferred until a telemetry log exists and until the privacy option in memo 12 §14 has been chosen. Memo 15's Good-Enough Model principle is adopted immediately as the project's **manual** routing policy (recorded below), so routing decisions are evidence-shaped before any automation is introduced.
10. **Memo 7 and memo 13 recorded, not implemented now (acts on memos 7 and 13).** Memo 7's Pi observation (sub-1K-token harness overhead vs OpenCode's ~6.9K) is retained as an optional evaluation task, since prompt-overhead savings matter directly on a 16K budget. Memo 13's continuous refactoring loop is deferred because it depends on both a routing/escalation tier and a telemetry log that do not yet exist; it will be replanned after Waves 1–2.

None of the decisions above alter the 18 GB / 16384 safety envelope, re-enable MLXServe or the 30B Coder model, introduce parallel local agents, or revise the root-cause attribution of the 2026-08-17 kernel panic (which remains undetermined; see "Root-cause attribution discipline" below).

## Local-first routing policy

The project operates a manual, local-first routing policy derived from memo 15 §3/§14 (Good-Enough Model), memo 16 §7–§8 (escalation triggers and the no-hiding rule), and memo 8 §9 (action classes). It is enforced by operator discipline, not by an automated router; adopting it now gives later waves (telemetry in Wave 0, cloud escalation in Wave 1, external actions in Wave 2) a stable written baseline.

### Escalation ladder

Routing proceeds in this fixed order; a tier is only used when the tier above it is unsuitable for a specific reason that the operator records.

```
Local Qwen3-8B-4bit  (mlx-lm.server, default)
        │
        ▼
Subscribed cloud model  (OpenCode Go → Kimi K3, opencode-go/kimi-k3)
        │
        ▼
Human review
```

Rationale: the local tier is cost-free and private; the subscribed cloud tier is included-usage rather than pay-per-token, so routine escalation does not create per-call cost pressure; human review is the final tier when neither model tier is sufficient. The pay-per-token Moonshot API and additional cloud providers are out of scope under this policy.

### Escalation triggers (memo 16 §7)

The local tier is escalated only when at least one of the following conditions is observable and recorded:

- **Capability.** The task genuinely requires reasoning beyond the local 8B model's demonstrated range: large multi-file refactors, sophisticated architectural reasoning, or difficult cross-cutting debugging.
- **Runtime failure.** `mlx-lm.server` returns an error, the session times out, the context cap is hit (16384), the per-request GPU memory gate rejects the prompt, or the model crashes.
- **Quality failure.** The local model's output does not compile, fails tests, repeatedly fails to apply a correction, enters an unproductive loop, or is rejected by repository validation.
- **Resource constraints.** The required context does not fit the 16K envelope even after compaction and retrieval reduction, or the workload would push resident memory outside the 18 GB policy.

A session that proceeds to the cloud tier without matching one of these triggers is a policy violation; the operator should re-attempt locally or stop.

### Action classes (memo 8 §9)

Every tool-mediated action (local or escalated, Composio-mediated or built-in) is handled according to its class. These classes govern operator approval, not model capability.

- **Class A — Read:** search, inspect, list, retrieve, summarize, query. Normally execute without additional confirmation.
- **Class B — Reversible write (**`propose → approve → execute`**):** create a draft, open an issue, add a comment, create a branch. Require explicit confirmation while the architecture is being validated.
- **Class C — High-consequence / destructive / external communication (**`explain → approve → execute → verify`**):** delete, merge, publish, send, deploy, transfer, change permissions, modify credentials, remove infrastructure. Require an explicit explanation of intent, explicit approval, and model-side verification after execution. These are never promoted to autonomous execution without a separately approved, narrowly scoped automation.

The same classification applies regardless of whether the action is performed by the local model, by the escalated cloud model, or by a Composio-mediated tool call.

### Escalation must not hide local failures (memo 16 §8)

Escalation to the cloud tier is a signal, not a workaround. Every escalation event is treated as diagnostic input for the local stack: the triggering failure is recorded (which trigger class fired, which request shape, which log markers), classified, and used to inform later tuning or memos. Escalating to Kimi K3 to "just get the task done" without recording the local failure is a policy violation, because it silently removes the only evidence that would make the local tier better over time.

Concretely, when a local request fails and escalation is used:

1. Record the triggering failure (trigger class, timestamp, request shape, server-log delta if any).
2. Note the escalation (model used, task completed yes/no).
3. Keep the failure visible — do not retroactively edit it out of the task note once the cloud tier succeeds.
4. Return to the local tier for the next task; do not stay on cloud by default.

The Wave 0 telemetry log (`.mlxlm/routing/`, gitignored) and the Wave 1 escalation configuration implement the mechanical side of this rule. This section states the operator policy that those tools serve.

## Layered failure modes and which layer each mitigation addresses

Field experience surfaced *three* resource/driver failure modes on the pre-migration stack, stacked from softest to hardest. The migration to `mlx-lm.server` surfaced a fourth, *runtime-layer* class documented separately in the next section.

1. **Hard ctx cap (16384 tokens)** — request rejected with "Prompt exceeds maximum context length: N requested, 16384 available". Deterministic and recoverable. On the current stack the cap is enforced by OpenCode's provider `context: 16384` limit rather than an `mlx-lm.server` CLI flag. *Mitigations:* OpenCode compaction/pruning (`compaction`, `tool_output.max_lines`, `tool_output.max_bytes`); retrieval budgets (smaller `codebase-retrieval` payloads); session-restart discipline.
2. **Per-request GPU memory gate** — request rejected with "requires ~XMB GPU memory but only ~YMB available". Depends on live free GPU memory at request time, so warm/fragmented caches can reject prompts that a cold session accepts. *Mitigations:* compaction (reduces prompt size); session-restart discipline (clears warm cache state); resident-memory headroom (18 GB policy leaves more physical margin); server-side prompt-cache caps (`--prompt-cache-bytes`, `--prompt-cache-size`) that bound KV-cache growth; the legacy `--prefill-chunk 1024` lever is restored on mlx-lm 0.31.3 as `--prefill-step-size 1024` (passed by `.mlxlm/serve.sh`).
3. **Driver-level IOGPUFamily panic** — full macOS kernel panic. No OpenCode-side, `mlx-lm.server`-side, or client-side configuration can *guarantee* protection at this layer. *Mitigations we can apply:* resident-memory headroom (18 GB policy); avoiding the specific workload shape that preceded the observed panic (streaming + speculative decoding + accumulating GPU state) is a candidate but *not a confirmed cause*. On the current runtime speculative decoding is opt-in via `--draft-model` and disabled by default, so the "PLD-off precaution" from the legacy stack is now the runtime's default posture. Attribution of the 2026-08-17 event stays undetermined; see the "Root-cause attribution discipline" section.

Compaction/truncation and retrieval budgets address layer 1 primarily and layer 2 secondarily; resident-memory headroom and session-restart discipline address layer 2 and (as best as we can) layer 3.

The V2 refactor proposals (archived under `archive/ADVISE_x5f_REFACTOR_x5f_V2.md`, `archive/OPENCODE_x5f_REFACTOR_x5f_V2.md`, `archive/SERVER_x5f_REFACTOR_x5f_V2.md`) were evaluated against this failure-mode taxonomy in Waves 0–4c and **rejected**: raising `tool_output.max_lines` to 300 triggered a ~12.38 GB prompt-cache spike and a Metal IOGPU OOM (layer 2/3), switching the default to a non-existent `mlx-community/Qwen3-Coder-8B-4bit` was not viable, `--max-kv-size` is not a supported `mlx-lm.server` flag, and `.opencodeignore` is not honoured by OpenCode's ripgrep integration. See the *Rejected V2 refactor proposals (archived)* section of `README.md` for the operator-facing summary.

## Runtime-layer bugs surfaced by the mlx-lm migration

Migration to `mlx-lm 0.29.1` exposed three runtime-layer client-server contract issues that are distinct from the resource/driver failure modes above. They break the request/response contract rather than exhaust resources, and their evidence lives under `.mlxlm/probes/`.

| # | Gap | Impact | Mitigation on this stack | Evidence |
| --- | --- | --- | --- | --- |
| W4 | BatchRotatingKVCache.merge crashes on concurrent requests with different prompt lengths | Server 500 on legitimate parallel traffic | opencode.json disables the title and summary side-band agents so requests serialize | .mlxlm/probes/upstream_bug_report.md |
| A.1 (retired) | On mlx-lm 0.29.1, mlx_lm.server hard-coded tool_calls[].id: null, violating the OpenAI spec | ai-sdk clients (OpenCode) aborted mid-stream on any tool call | Retired as of mlx-lm 0.31.3: upstream ToolCallFormatter supplies a non-null id natively. Historical one-line venv patch and rollback path documented in .mlxlm/PATCHES.md | .mlxlm/PATCHES.md, .mlxlm/probes/upstream_fr_tool_calls.md, .mlxlm/probes/rebuild_py312_mlxlm0.31.3_20260825T192734Z/ (artifacts in git history at af4357a5727132b4facdd84c836ad8101736551c) |
| P3 Harmony | mlx_lm.server does not parse gpt-oss Harmony commentary channels into structured tool_calls[] | gpt-oss-20b cannot complete MCP tool loops | Not fixed at the runtime layer; the current default model is Qwen3-8B-4bit which uses the standard <tool_call> idiom | .mlxlm/probes/harmony_adapter_analysis.md |

The A.1 patch is retired as of mlx-lm 0.31.3, which ships an upstream `ToolCallFormatter` that emits a non-null `tool_calls[].id` natively. The historical patch is documented in `.mlxlm/PATCHES.md` alongside its rollback path (restore the preserved `~/.mlxlm/venv-py39-mlxlm0291.bak` venv). The drafted upstream report for W4 remains under `.mlxlm/probes/` and pending filing at `ml-explore/mlx-lm`.

## Experimental discipline

A setting becomes part of the baseline only through:

```
hypothesis
    ↓
isolated change
    ↓
controlled measurement
    ↓
observation
    ↓
verification
    ↓
documentation
    ↓
baseline decision
```

A successful request is evidence that a configuration *can* work.

It is not evidence that the configuration is reliably safe.

Similarly, one failed request does not automatically identify its root cause.

Separate:

- configuration;
- observation;
- inference;
- hypothesis;
- conclusion.

This distinction is particularly important for GPU/driver failures.

**One variable at a time.** Every tuning experiment isolates a single flag or setting against an otherwise frozen baseline. Never change the resident-memory policy and speculative decoding in the same experiment. Never mix context-window and OpenCode-side compaction changes in the same experiment.

**Stop rule (mandatory).** Abort *immediately* on:

- GPU stalls or non-responsive server;
- severe/urgent macOS memory pressure (`kern.memorystatus_level` dropping into critical range);
- process hangs;
- any abnormal `mlx-lm.server` log output (OOM, IOGPUCommandBuffer errors, panics, unexplained thread aborts, `BatchRotatingKVCache` tracebacks).

On any stop-rule trigger: stop the server, capture the log and any system diagnostics, record the observation verbatim, and *do not* push through. No repeated high-pressure automated loops. Short, controlled requests only during safety validation phases.

**Restart between experimental cycles.** Cumulative GPU/cache state is a confounder for per-request-gate behaviour and (potentially) for the driver-level failure mode. During safety-validation runs, restart the server between cycles so cache state is removed as a variable. During normal daily use, session-restart discipline plays the same role when the warm cache degrades.

## Root-cause attribution discipline

For the 2026-08-17 kernel panic (and any similar future event):

- The workload at the time of the panic was an 8,260-token prompt served with streaming and speculative decoding — a fact from the panic report.
- The exact panic string was `"completeMemory() prepare count underflow" @ IOGPUMemory.cpp:550` in `com.apple.iokit.IOGPUFamily` — a fact from the panic report.
- `mlx-serve` was the panicked task and generated the GPU workload/state associated with the panic — this is a fact from the panic report.
- The panic itself occurred inside Apple's IOGPUFamily driver (`IOGPUMemory.cpp:550`) — also a fact from the panic report.
- Whether the underlying defect is in `mlx-serve`, MLX, Metal/IOGPUFamily, or an interaction among them is **undetermined**.

For the 2026-10-06 kernel panic (and any similar future event):

- The workload at the time of the panic was `mlx-lm.server` serving `Qwen3-8B-4bit` idle at ≈143 MB RSS, OpenCode 1.18.31 running with the `augment-context-engine` and `composio` MCP servers during Wave 2 Composio tool discovery, and the Intent app itself — facts from the panic report and the recorded process state.
- The exact panic string was `"pending memory object unexpectedly found in non pending hash" @ IOGPUGroupMemory.cpp:528` — a fact from the panic report.
- The kexts in the backtrace were `com.apple.iokit.IOGPUFamily (130.15.2)` and `com.apple.AGXG16X (351.2)` — a fact from the panic report.
- The panicked task was pid 1487 `Intent by Augment Helper` (3,031 pages ≈ 47 MB, 25 threads), **not** `mlx_lm.server` and **not** `opencode` — a fact from the panic report.
- The compressor was at 5% of the compressed-page limit and 6% of the segment limit with swap OK, i.e. **no memory-pressure signature** — a fact from the panic report.
- Host was macOS 25F84 / Darwin 25.5.0 on a Mac mini M4 Pro (T6041); panic report path `/Library/Logs/DiagnosticReports/panic-full-2026-10-06-221917.0002.panic` — facts from the panic report.
- Whether the underlying defect is in the Intent helper, `mlx-lm`/MLX, Metal/IOGPUFamily/AGXG16X, or an interaction among them is **undetermined**. Two panics in the same driver family under materially different workloads (an 18 GB-era `mlx-serve` streaming + speculative-decoding workload in 2026-08, and a ≈143 MB-idle `mlx-lm.server` alongside an Intent GPU helper in 2026-10) **widen rather than narrow** the candidate set.

Do not write, in any file or note, that `mlx-serve`, `mlx-lm.server`, the Intent helper, or any specific component definitively contains the root-cause bug for either event. Use "the panicked task was X" or "the panic occurred during workload Y" instead. The migration to `mlx-lm.server` does not retroactively assign blame for the 2026-08-17 event — it changes the runtime binary in play going forward — and the 2026-10-06 event does not assign blame to the Intent helper merely because it was the panicked task. The same discipline applies to any comparable future event.

## Order of operations for future tuning

1. Establish that the current baseline is stable under short controlled cycles (this is the Safety Phase).
2. Only then, investigate whether speculative decoding (opt-in via `--draft-model` on `mlx-lm.server`) contributes materially to instability — one variable at a time, never combined with a resident-memory-policy change.
3. Resume retrieval-payload and context-budget work once the baseline is judged safe under sustained (not just short) workloads.

A few clean short cycles demonstrate basic viability. They are **not** proof of long-horizon safety. Extended use is required before promoting the baseline from "viable" to "safe for sustained agent workloads".

## Phase 4 acceptance criterion

The next engineering phase should prioritize coding capability rather than additional context expansion.

The primary experiment should demonstrate a real repository change using:

```
inspect
  → retrieve
  → reason
  → edit
  → verify
  → stop
```

A Phase 4 trial should:

- begin from a clean server/session state;
- use the committed safety baseline;
- select a small, reversible repository task;
- require Augment Context Engine retrieval;
- require at least one actual file edit;
- require verification of that edit;
- record `mlx-lm.server` request sizes throughout the loop;
- observe GPU/memory behaviour;
- stop under the existing safety rules.

Success means that the complete coding loop finishes naturally without context overflow, GPU-gate failure, process instability, or machine instability.

Only after repeated successful edit-producing sessions should longer-running or more autonomous workloads be investigated.