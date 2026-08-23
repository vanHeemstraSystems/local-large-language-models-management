# local-large-language-models-management

A minimal, reproducible local-LLM stack for a **Mac mini M4 Pro with 24 GBunified memory**: [MLXServe](https://mlxserve.com) serving`mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`on `http://127.0.0.1:11234` through an OpenAI-compatible API, driven by asmall wrapper script and a stdlib-only Python smoke client.

Verified on Apple M4 Pro · 14 cores · 24 GiB · macOS 26.5.2 (arm64).

> **New operator?** Start with [QUICKSTART.md](QUICKSTART.md) — step-by-step setup for the current `mlx-lm.server` + OpenCode + Augment Intent (BYOA) workflow, including the A.1 venv patch, billing/credits guidance, and known errors. This README documents the historical `mlx-serve` stack and its safety envelope.

## What is in this repo

- `scripts/mlxserve.sh` — single entry point for install / lifecycle /primary-model / client-smoke operations. Run `scripts/mlxserve.sh --help`for the full subcommand list.
- `scripts/client_smoke.py` — Python 3 stdlib OpenAI-compatible client(non-streaming + SSE) that validates the Chat Completions contract andexits `0` iff the round-trip succeeds.
- `memo1.md`, `memo2.md`, `memo3.md` — background rationale (hardware, modelchoice, MLXServe vs alternatives). Not required to operate the stack.
- `.mlxserve/` — gitignored runtime state (pid, logs, fixtures).

## Prerequisites

- macOS 26.2 or later on Apple Silicon (MLXServe requirement).
- Homebrew.
- Python 3 on `PATH` (system Python 3.9 is sufficient; no `pip` installs).
- ~20 GB free disk space for the primary model.

## Install

```sh
scripts/mlxserve.sh install
```

Taps `ddalcu/mlx-serve`, trusts the tap, and installs the `mlx-serve`formula. The binary lands at `/opt/homebrew/bin/mlx-serve`.

## Quickstart

```sh
# 1. Download the primary model (~17 GB, one-time).
scripts/mlxserve.sh pull-primary

# 2. Start the server (loopback :11234) with the verified defaults baked in
#    for the 24 GB envelope (--max-resident-mem 18GB, --skip-mem-preflight,
#    --ctx-size 16384, --max-tokens 1536, --kv-quant 4, --prefill-chunk 1024)
#    and load the primary model into memory. No ad hoc env vars required.
scripts/mlxserve.sh start
scripts/mlxserve.sh load-primary

# 3. Verify with the supported OpenAI-compatible client workflow.
scripts/mlxserve.sh client-smoke              # non-streaming
scripts/mlxserve.sh client-smoke --stream     # SSE streaming

# 4. Stop cleanly (releases the port and reclaims wired GPU memory).
scripts/mlxserve.sh stop
```

## Operator cheat sheet

| Command | Purpose |
| --- | --- |
| scripts/mlxserve.sh start | Background start, waits for /health. |
| scripts/mlxserve.sh status | pid, host, port, listening socket. |
| scripts/mlxserve.sh health | curl /health (exit 0 when healthy). |
| scripts/mlxserve.sh logs | Tail .mlxserve/mlxserve.log. |
| scripts/mlxserve.sh models | List models on disk. |
| scripts/mlxserve.sh pull-primary | Download $MLXSERVE_PRIMARY_MODEL. |
| scripts/mlxserve.sh load-primary | POST /v1/load-model for the primary. |
| scripts/mlxserve.sh smoke | One /v1/chat/completions round-trip. |
| scripts/mlxserve.sh client-smoke [--stream] | Full OpenAI-contract client smoke. |
| scripts/mlxserve.sh restart | stop |

Key environment overrides (all optional):

- `MLXSERVE_HOST` / `MLXSERVE_PORT` — bind address (defaults: `127.0.0.1:11234`).
- `MLXSERVE_MODEL_DIR` — model download directory (default: `~/.mlx-serve/models`).
- `MLXSERVE_PRIMARY_MODEL` — canonical primary model id (see fallback below).
- `MLXSERVE_MAX_RESIDENT_MEM` — resident-memory cap (default: `18GB`, safety-revised from `20GB` after the 2026-08-17 kernel panic; see the safety note below).
- `MLXSERVE_SKIP_MEM_PREFLIGHT` — `1` (default) passes `--skip-mem-preflight` to bypass the per-load free-RAM gate that the primary model trips on this 24 GB machine. Set to `0` to re-enable the built-in load gate.
- `MLXSERVE_CTX_SIZE` — `--ctx-size` (default: `16384`). The enforced KV/prompt cap. See the honesty note below on the practical accepted-prompt ceiling.
- `MLXSERVE_MAX_TOKENS` — `--max-tokens` (default: `1536`). Default per-request output cap.
- `MLXSERVE_KV_QUANT` — `--kv-quant` (default: `4`). KV cache quantisation in bits; 4-bit keeps the 16K KV budget on-device.
- `MLXSERVE_PREFILL_CHUNK` — `--prefill-chunk` (default: `1024`). Max tokens forwarded per prefill chunk. Wave B: this is the single biggest lever against the per-request GPU-memory gate; lowering it from `mlx-serve`'s 8192 default lifts the accepted-prompt ceiling from ~4K to ~13.5K on this 24 GB machine.
- `MLXSERVE_EXTRA_ARGS` — free-form extra flags appended to `mlx-serve --serve` (applied after the baked-in flags above).

## Supported local client workflow

`scripts/client_smoke.py` is the canonical supported consumer. It calls`POST http://127.0.0.1:11234/v1/chat/completions` and validates the OpenAIChat Completions response (`choices[0].message.content`, `finish_reason`,`usage.{prompt,completion,total}_tokens`).

- **Non-streaming:** `scripts/mlxserve.sh client-smoke` → prints`OK non-streaming model=… prompt=… completion=… total=… elapsed=… finish=stop`on success. Exit code `0`.
- **Streaming (SSE):** `scripts/mlxserve.sh client-smoke --stream` → prints`OK streaming frames=… chars=… elapsed=…`, having verified the`[DONE]` sentinel and delta reassembly. Exit code `0`.
- **Failure signal:** any HTTP / URL / JSON / contract violation exitsnon-zero with a `FAIL: …` line on stderr. Safe to use as an automationgate.

Any OpenAI-SDK-shaped client (Claude Code with `ANTHROPIC_BASE_URL` remapped,Continue, OpenCode, custom Python/TS clients) is a supported consumer of thesame endpoint.

## OpenCode (verified consumer)

[OpenCode](https://opencode.ai) is verified as a full agent-loop consumer of the local MLXServe endpoint (Phase 1, user-driven).

- **`opencode.json`** at the repo root is the OpenCode workspace config that wires OpenCode to the local endpoint. It declares a single provider "Local MLXServe" via `@ai-sdk/openai-compatible`, with `baseURL http://127.0.0.1:11234/v1` and the primary model `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` at `context 16384 / output 1536`. OpenCode picks it up automatically when launched from the repo root.
- **Frozen known-good baseline** (do not tune until Phase 2 is measured):

  | Knob | Value |
  | --- | --- |
  | `--ctx-size` | 16384 |
  | `--max-tokens` | 1536 |
  | `--kv-quant` | 4 |
  | `--prefill-chunk` | 1024 |
  | `--max-resident-mem` | 18GB (safety-revised from 20GB) |
  | `--skip-mem-preflight` | on (per-load free-RAM gate bypassed) |
  | OpenCode provider limits | context 16384 / output 1536 |

- **Phase 1 verified result:** full agent loop against local Qwen3-Coder-30B — tool call (Read) → tool continuation on the tool result → grounded synthesis → natural stop. A 12,750-token post-tool prompt was accepted, sitting under the ~13.5K accepted-prompt ceiling documented below; output ceiling raised 1024 → 1536 and the model used 323 tokens before stopping naturally.

## Memory and stability envelope (24 GB M4 Pro)

The primary model is at the upper edge of what runs comfortably on 24 GB.Observed during Waves 1–3 verification:

| Phase | Wired memory | Free memory |
| --- | --- | --- |
| Server started, no model | ~2.0 GB | ~316 MB free (plus idle inactive) |
| After /v1/load-model (ready) | ~18.5 GB | ~500 MB – 2 MB |
| After two /v1/chat/completions | ~18.5 GB (flat) | stable |
| After scripts/mlxserve.sh stop | ~2.0 GB | ~4 GB (fully reclaimed) |

- `bytes_resident` for the loaded model: **17.18 GB** (matches the ~17.2 GBweight budget in `memo3.md`).
- Load time: ~7–12 s cold.
- Decode: ~90–94 tok/s on the primary model.
- **Context configuration (wrapper defaults):** `--ctx-size 16384`, `--max-tokens 1536`, `--kv-quant 4`, `--prefill-chunk 1024` are baked into `scripts/mlxserve.sh` at the Wave B verified working values. Override via `MLXSERVE_CTX_SIZE`, `MLXSERVE_MAX_TOKENS`, `MLXSERVE_KV_QUANT`, `MLXSERVE_PREFILL_CHUNK`.
- **Practical accepted-prompt ceiling: ~13.5K tokens** (up from ~3.6K under the Wave A 8K/default-prefill-chunk configuration). On this 24 GB machine, the binding constraint is a *per-request* GPU-memory pre-flight in `mlx-serve`, not `--ctx-size`. Wave B measurements at `--ctx-size 16384 --prefill-chunk 1024 --kv-quant 4 --max-resident-mem 20GB` with `max_tokens=256`: **~13.6K-token prompts accepted (peak ~19.0 GB active), ~14.4K rejected with HTTP 400** (`requires ~XMB GPU memory but only ~YMB available`). The single biggest lever was `--prefill-chunk`; lowering it from the `mlx-serve` 8192 default to 1024 lifted the ceiling from ~4K to ~13.5K.
- **32K context is possible but not the stable default.** With `MLXSERVE_CTX_SIZE=32768 --prefill-chunk 1024`, small prompts work and the per-request gate accepts up to ~24K tokens at `max_tokens<=64`, but real workloads at ~22K prompt + `max_tokens=128` crash the MLX Metal command buffer with `kIOGPUCommandBufferCallbackErrorOutOfMemory` on this 24 GB hardware. The wrapper therefore defaults to 16K; opt into 32K via `MLXSERVE_CTX_SIZE=32768` only when you can bound the combined prompt+generation size.
- **`--skip-mem-preflight` does NOT bypass the per-request GPU-memory gate.** It only bypasses the one-shot free-RAM check at model *load* time. The per-request gate is enforced by the runtime and is what caps effective prompts even under `--skip-mem-preflight`.
- **The startup line `Model context length: 4096 tokens` is cosmetic.** It is an internal display value in the `mlx-serve 26.8.7` binary that appears on every startup regardless of `--ctx-size`. It does not gate requests; the model's `config.json` declares `max_position_embeddings=262144`, and the enforced cap is `--ctx-size` (currently 16384).
- **The two memory knobs are load-blocking by default**:
  - MLXServe's built-in ~14 GB resident cap refuses the ~17.6 GB primarymodel → `MLXSERVE_MAX_RESIDENT_MEM=18GB` is the wrapper default (safety-revised from 20GB; see the safety note below).
  - MLXServe's per-load free-RAM pre-flight uses "currently free" pages andignores reclaimable inactive/file-cache pages, so it refuses loads thatin fact fit → `MLXSERVE_SKIP_MEM_PREFLIGHT=1` is the wrapper default.
- **Concurrent memory-hungry apps (browser, Docker, large IDEs) can OOM theload** at this envelope. Close them before `load-primary`, or use thefallback tier below.

## Safety note: 18GB resident cap (2026-08-17 revision)

On 2026-08-17 the Mac suffered a full macOS kernel panic during a modest MLXServe workload (8,260-token prompt, streaming, speculative decoding active). The panic report was `"completeMemory() prepare count underflow" @IOGPUMemory.cpp:550` in Apple's `com.apple.iokit.IOGPUFamily` driver, with `mlx-serve` listed as the panicked task. mlx-serve was the panicked task and generated the associated GPU workload/state, but the panic itself occurred inside Apple's IOGPUFamily driver. The evidence does NOT yet establish whether the underlying defect is in MLXServe, MLX, Metal/IOGPUFamily, or an interaction among them — do not describe MLXServe as definitively containing the root-cause bug.

Operating principle after this event: **machine stability outranks maximizing resident model memory or context capacity.** The wrapper's `MLXSERVE_MAX_RESIDENT_MEM` default was therefore reduced from `20GB` to `18GB`. All other frozen-baseline flags are unchanged (`--ctx-size 16384`, `--max-tokens 1536`, `--kv-quant 4`, `--prefill-chunk 1024`, `--skip-mem-preflight`). Note that mlx-serve derives its `[wired] mode=max limit=18186 MB` ceiling independently of this flag, so the log line looks identical at 18GB and 20GB; the registry line (`max_resident_mem=18.0 GB`) is the visible change. Rationale, layered failure modes, and the one-variable-at-a-time / stop-rule discipline governing further tuning are recorded in `STRATEGY.md`.

## Context budget policy (OpenCode + Augment Context Engine)

Operator-facing policy for running OpenCode with the Augment Context Engine MCP against the local MLXServe endpoint on this 24 GB Mac mini. Numbers below are measured against the committed baseline (`opencode.json` at the repo root; MLXServe defaults from `scripts/mlxserve.sh`). This section sits on top of the stability principle and layered failure model in `STRATEGY.md`.

### The budget (verified numbers)

| Item | Value | Source |
| --- | --- | --- |
| Hard context cap | 16,384 tokens | `--ctx-size` (MLXServe); HTTP 400 above this |
| Initial envelope, MCP enabled | ~8,262 tokens | measured after adding `augment-context-engine` MCP |
| Per retrieval call | ~2,400 tokens / ~10 KB | bounded by committed `tool_output.max_lines: 200` (measured 2,339 / 2,442 tokens on 9.3–9.8 KB payloads) |
| Compaction reserve | 5,000 tokens | committed `compaction.reserved` |
| Spare after one retrieval | ~722 tokens | `16,384 − 8,262 − 2,400 − 5,000` |
| Peak measured successful prompt | 15,531 tokens | end-to-end Safety Phase run, natural stop |

Rule of thumb: roughly **two retrievals plus one continuation** fit before auto-compaction must fire. The budget is real but genuinely narrow.

### What is enforced automatically vs. operator discipline

Enforced by committed `opencode.json`:

- Auto-compaction (`compaction.auto: true`, `prune: true`, `reserved: 5000`, `preserve_recent_tokens: 4000`) — fires above the reserve, prunes tool messages, reissues a shrunk prompt. Verified: a 16,005-token turn was pruned to an 11,889-token reissue (−26%).
- Retrieval / tool payload caps (`tool_output.max_lines: 200`, `tool_output.max_bytes: 16384`) — the `max_lines` cap is the binding one for `codebase-retrieval` payloads.

Operator discipline (the config cannot enforce these):

- Ask targeted retrieval questions — small, specific queries beat broad "explain everything" prompts.
- Avoid broad reads of large files. `tool_output.max_bytes` did **not** cap the read-tool path in one measured run (14,907 bytes returned uncapped). Prefer retrieval over full-file reads when the file is larger than ~8 KB.
- Restart the OpenCode session when the warm cache degrades (see the failure-mode ladder below).

### Do not

Each item is backed by a measured failure.

- **Do not truncate `tool_output` below the committed defaults.** A `max_lines: 100 / max_bytes: 8192` variant produced ~46% less payload but induced a hallucinated-webfetch storm (20 calls to an invented GitHub repo) and a ctx-size overflow at request 3 (18,552 tokens). Under-truncation deprives the model of grounding and is counterproductive.
- **Do not assume a fixed token ceiling equals reliability.** A post-compaction 11,889-token request was rejected by the per-request GPU gate (780 MB needed vs. 514 MB available). Runtime free GPU memory — not the token count alone — governs acceptance.
- **Do not treat a few clean short runs as proof of sustained-workload safety.** All measurements above are n=1 per condition; see "Known gaps".

### Failure-mode ladder and operator response

| Layer | What the operator sees | Response |
| --- | --- | --- |
| 1. ctx-size overflow | HTTP 400 `"Prompt exceeds maximum context length: N requested, 16384 available"` | Let auto-compaction fire; if compaction has already run this turn, restart the OpenCode session. |
| 2. Per-request GPU gate | HTTP 400 `"requires ~XMB GPU memory but only ~YMB available"` | Restart MLXServe (`scripts/mlxserve.sh restart && scripts/mlxserve.sh load-primary`) — warm-cache fragmentation is not fixable client-side. |
| 3. Driver-level instability | Server hang, GPU stall, or (once observed) a full macOS kernel panic | Stop the server, honor the `STRATEGY.md` stop rules, capture logs, and reassess before resuming. Root-cause attribution across MLXServe / MLX / Metal / IOGPUFamily is undetermined. |

### Safety controls for sustained agent workloads

- `MLXSERVE_EXTRA_ARGS="--no-pld"` disables PLD/speculative decoding as a precaution for long agent loops. Committed default is unchanged (verdict undetermined; short controlled cycles neither proved nor refuted a causal PLD contribution to the driver-level failure). Trades throughput on echo-heavy loops for one fewer variable in the GPU state.
- `--max-resident-mem 18GB` is a policy-level tightening from `20GB`. With a single ~16 GB model loaded it is **non-binding today** (the wired limit `18186 MB` is derived independently), but it caps future multi-model or larger-model configurations.
- Restart MLXServe between long agent sessions to clear warm cache state.
- Honor the `STRATEGY.md` stop rules on any GPU stall, severe memory pressure, or abnormal log output — do not push through.

### Known gaps (honesty section)

- **Edit-producing loop shape undemonstrated** at this budget. Phase 3 retrieval measurements used a read-then-summarize scenario ("Do NOT modify any files"); the end-to-end tool-call → tool-result → edit flow at ~15K tokens has not been reproduced under the current committed defaults.
- **n=1 per condition.** Single runs cannot cleanly separate config effects from stochastic behavior.
- **Long-horizon safety unproven.** The panic-workload shape has deliberately not been reproduced; clean short cycles are not proof of sustained safety.
- **Warm-cache degradation quantified only anecdotally** — the Stage 2b rejection at 15,499 tokens and the post-compaction rejection at 11,889 tokens are the only concrete data points.

## Fallback path (spec acceptance criterion 7)

If the primary model is too memory-constrained or unstable on this 24 GBmachine, keep MLXServe and switch to a smaller MLX Qwen 14B 4-bit model.`memo3.md` marks the Qwen 14B 4-bit tier as the comfortable fallback.

```sh
# 1. Pick an available MLX Qwen 14B 4-bit build under mlx-community/... on
#    Hugging Face. The exact repo id changes over time; confirm the id
#    exists (e.g. via https://huggingface.co/mlx-community?search=Qwen3+14B)
#    before running `pull-primary`.
export MLXSERVE_PRIMARY_MODEL=mlx-community/<qwen-14b-4bit-repo-id>

# 2. Pull it, restart the server, load it, verify via the client smoke.
scripts/mlxserve.sh pull-primary
scripts/mlxserve.sh restart
scripts/mlxserve.sh load-primary
scripts/mlxserve.sh client-smoke
```

Notes:

- Use `scripts/mlxserve.sh models` after the pull to confirm the download.
- With a ~14B 4-bit model (roughly 8–10 GB of weights) you can typicallyset `MLXSERVE_SKIP_MEM_PREFLIGHT=0` and lower `MLXSERVE_MAX_RESIDENT_MEM`(e.g. `12GB`) to leave more headroom for desktop apps. Re-verify with`scripts/mlxserve.sh client-smoke` after tuning.
- The fallback is a **model swap only**; MLXServe, the wrapper, and theclient-smoke workflow are unchanged.
- If neither model is workable during normal desktop use, follow the spec'srollback plan: `scripts/mlxserve.sh stop` and treat the local stack as anisolated experiment rather than a daily-workflow dependency.

## Note on Augment Intent

Direct Augment Intent → local endpoint routing (pointing the desktop app at`http://127.0.0.1:11234/v1`) is **not verified** by this project. `memo2.md`covers the reasoning: MLXServe exposes an OpenAI-compatible surface, butAugment Intent BYO-endpoint support has not been demonstrated end-to-endhere. Any such claim should be re-verified before it is documented.

The verified consumers of the local endpoint in this repo are`scripts/client_smoke.py` and any OpenAI-SDK-shaped client using the sameURL and model id.

## References

- MLXServe: <[https://mlxserve.com](https://mlxserve.com)> · <[https://github.com/ddalcu/mlx-serve](https://github.com/ddalcu/mlx-serve)>
- Primary model: <[https://huggingface.co/mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit)>
- Background rationale: `memo1.md`, `memo2.md`, `memo3.md`