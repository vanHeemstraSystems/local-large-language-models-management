# local-large-language-models-management

A reproducible **local software-engineering agent stack** for a Mac mini M4 Pro (24 GB unified memory):

```
OpenCode  ──►  mlx-lm.server (127.0.0.1:8080/v1)  ──►  Qwen3-8B-4bit (default) / gpt-oss-20b-MXFP4-Q8
    │
    └── Augment Context Engine MCP (retrieval)
```

Runs entirely local against an OpenAI-compatible endpoint. Integrates with the **Intent by Augment** desktop app in BYOA (Bring Your Own Agent) mode — model inference is free; only Augment Context Engine retrievals draw credits.

Verified on Apple M4 Pro · 14 cores · 24 GiB · macOS 26.5.2 (arm64).

## Start here

- **[QUICKSTART.md](QUICKSTART.md)** — step-by-step operator guide: prerequisites, venv setup, the required A.1 patch, daily workflow, known errors, an end-to-end example, and the Intent BYOA billing/credits guide.
- **[STRATEGY.md](STRATEGY.md)** — the *why*: safety principles, maturity criteria, tuning discipline, failure interpretation.

## Authoritative files

| File | Authoritative for |
|---|---|
| `opencode.json` | Provider endpoint, default model, `context 16384` / `max_output_tokens 1536`, MCP wiring, compaction, tool-output caps, side-band agent settings (W1 workaround). |
| `.mlxlm/PATCHES.md` | The **A.1 venv patch** that makes `mlx_lm.server` emit OpenAI-spec-compliant `tool_calls[].id` values. Not committed to the repo — must be re-applied when the venv is rebuilt. |
| `.mlxlm/serve.sh` | Lifecycle wrapper (`start` / `stop` / `status` / `log`) for `mlx-lm.server` in `~/.mlxlm/venv`. |
| `STRATEGY.md` | Operating principles and safety baseline (18 GB resident cap, 16,384 ctx, 1,536 max tokens, 4-bit KV). |
| `QUICKSTART.md` | Operator workflow, verification steps, known errors, Intent BYOA setup. |

If any documentation disagrees with `opencode.json` or `.mlxlm/PATCHES.md`, the runtime configuration is authoritative and the documentation must be corrected.

## What is in this repo

- `.mlxlm/serve.sh` — start/stop/status wrapper for `mlx-lm.server` at `127.0.0.1:8080`.
- `.mlxlm/PATCHES.md` — the required A.1 venv patch (one-line `tool_calls[].id` fix).
- `.mlxlm/probes/` — four-probe baseline suite (transport / modeling / resource / long-context) and reproducible artifacts under `baseline_postmerge_*`.
- `opencode.json` — OpenCode workspace configuration that wires the agent loop to the local endpoint and the Augment Context Engine MCP.
- `QUICKSTART.md`, `STRATEGY.md` — see above.
- `archive/memo1.md`, `archive/memo2.md`, `archive/memo3.md` — background rationale (hardware, model choice, runtime selection). Not required to operate the stack.
- `scripts/mlxserve.sh`, `scripts/client_smoke.py`, `.mlxserve/` — **legacy** artifacts from the pre-migration `mlx-serve` stack. Retained for historical reference; see the *Legacy `mlx-serve` stack* appendix below.

## Prerequisites

- Apple Silicon Mac with ≥ 24 GB unified memory (validated on M4 Pro / macOS 26.5.2).
- Homebrew.
- Python 3.9+ for a dedicated venv at `~/.mlxlm/venv`.
- `opencode` CLI (verified against 1.18.18).
- `auggie` CLI with an authenticated Intent session (verified against 0.34.0).
- ~20 GB free disk for model weights.

Full setup — venv creation, model download, and the required A.1 venv patch — is in [QUICKSTART.md](QUICKSTART.md).

## Quickstart

```sh
# 1. Start the local mlx-lm.server (127.0.0.1:8080).
.mlxlm/serve.sh start

# 2. Confirm the A.1 patch is in place (see .mlxlm/PATCHES.md).
grep -n 'uuid.uuid4' ~/.mlxlm/venv/lib/python*/site-packages/mlx_lm/server.py

# 3. Launch OpenCode from the repo root; it reads opencode.json.
opencode

# 4. Stop cleanly.
.mlxlm/serve.sh stop
```

For step-by-step instructions with verification steps and known errors, see [QUICKSTART.md](QUICKSTART.md).

## Runtime configuration (current stack)

Runtime defaults are set in `opencode.json` and enforced client-side:

| Setting | Value | Source |
| --- | --- | --- |
| Endpoint | `http://127.0.0.1:8080/v1` | `opencode.json` → `provider.mlxlm.options.baseURL` |
| Default model | `Qwen3-8B-4bit` (local path) | `opencode.json` → top-level `model` |
| Alternate model | `gpt-oss-20b-MXFP4-Q8` | `opencode.json` → `provider.mlxlm.models` |
| Context cap | 16,384 tokens | `provider.mlxlm.models.*.limit.context` |
| Max output | 1,536 tokens | `provider.mlxlm.models.*.limit.output` |
| Auto-compaction | enabled (`reserved: 5000`, `preserve_recent_tokens: 4000`) | `compaction.*` |
| Tool-output cap | `max_lines: 200`, `max_bytes: 16384` | `tool_output.*` |
| Side-band agents | `title` / `summary` disabled (W1 workaround) | `agent.*` |
| Augment Context Engine | wired via MCP (`auggie --mcp`) | `mcp.augment-context-engine` |

The `mlx-lm.server` CLI itself does not expose resident-memory, ctx-size, KV-quantisation, prefill-chunk, or PLD toggles. Those constraints now live entirely in `opencode.json` and in operator discipline (see `STRATEGY.md`).

## Augment Intent (BYOA) integration

The Intent by Augment desktop app supports **Bring Your Own Agent**. Create a new Space and select **OpenCode** as the agent provider; Intent will launch `opencode` in the workspace, which routes all model calls to the local `mlx-lm.server`.

| Component | Costs Augment credits? |
| --- | --- |
| Local model inference via OpenCode + mlx-lm | No — traffic stays on `127.0.0.1` |
| Augment Context Engine (`auggie --mcp`) | Yes — per retrieval call |
| Intent orchestration (spec, worktrees, PR flow) | No separate charge |
| Auggie native agents (Coordinator / Implementor / Verifier) | Yes — same rate as the Auggie CLI |

Full billing/credits walkthrough, including a fully-local zero-cost mode that disables the Context Engine MCP, is in [QUICKSTART.md → Billing & credits](QUICKSTART.md#billing--credits).

## Safety envelope

Governing principle: **machine stability outranks maximizing resident model memory or context capacity** (see `STRATEGY.md` for the full statement and the 2026-08-17 kernel-panic incident that motivated it).

Safety baseline enforced by `opencode.json` on the current stack:

- Resident memory: single ~4.5 GB Qwen3-8B-4bit model comfortably below the 18 GB policy cap.
- Context cap: 16,384 tokens per request (HTTP-error above).
- Max output: 1,536 tokens per response.
- Auto-compaction reserves 5,000 tokens and preserves the most recent 4,000 tokens.
- Retrieval payloads capped at 200 lines / 16,384 bytes to keep the budget spendable.

Historical measurements from the pre-migration `mlx-serve` + Qwen3-Coder-30B stack (context budget, failure-mode ladder, memory-envelope numbers) are preserved in the *Legacy `mlx-serve` stack* appendix below. They describe a different runtime and a different (much larger) model, so the specific numbers do not directly apply to the current `mlx-lm.server` + Qwen3-8B-4bit stack — but the layered failure model and the *do-not* list they document remain useful guidance.

## Fallback path

If Qwen3-8B-4bit is insufficient for a task, `opencode.json` already declares `gpt-oss-20b-MXFP4-Q8` as an alternate model on the same provider. Switch the top-level `model` field or select the alternate at runtime in OpenCode. Note: `gpt-oss-20b` uses the Harmony tool-call idiom, which `mlx_lm.server`'s built-in parser does not fully handle in every path — see [QUICKSTART.md → Known errors](QUICKSTART.md#known-errors-and-their-resolution) for the current status.

Both models must be downloaded once; see [QUICKSTART.md § 2](QUICKSTART.md#2-download-the-default-model).

## References

- mlx-lm: <https://github.com/ml-explore/mlx-lm>
- Default model: <https://huggingface.co/mlx-community/Qwen3-8B-4bit>
- Alternate model: <https://huggingface.co/mlx-community/gpt-oss-20b-MXFP4-Q8>
- OpenCode: <https://opencode.ai>
- Intent by Augment: <https://www.augmentcode.com/guides/intent-walkthrough-prompt-to-merge>
- Background rationale: `archive/memo1.md`, `archive/memo2.md`, `archive/memo3.md`

---

## Legacy `mlx-serve` stack (historical)

The content below documents the **pre-migration** stack — [MLXServe](https://mlxserve.com) serving `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` on `http://127.0.0.1:11234`, driven by `scripts/mlxserve.sh` and `scripts/client_smoke.py`. It has been superseded by the `mlx-lm.server` stack described above. The wrapper script and client smoke remain in the repo for reproducibility of the historical measurements.

### Legacy install

```sh
scripts/mlxserve.sh install
```

Taps `ddalcu/mlx-serve`, trusts the tap, and installs the `mlx-serve` formula. The binary lands at `/opt/homebrew/bin/mlx-serve`.

### Legacy quickstart

```sh
scripts/mlxserve.sh pull-primary   # ~17 GB, one-time
scripts/mlxserve.sh start
scripts/mlxserve.sh load-primary
scripts/mlxserve.sh client-smoke              # non-streaming
scripts/mlxserve.sh client-smoke --stream     # SSE streaming
scripts/mlxserve.sh stop
```

### Legacy operator cheat sheet

| Command | Purpose |
| --- | --- |
| `scripts/mlxserve.sh start` | Background start, waits for `/health`. |
| `scripts/mlxserve.sh status` | pid, host, port, listening socket. |
| `scripts/mlxserve.sh health` | `curl /health` (exit 0 when healthy). |
| `scripts/mlxserve.sh logs` | Tail `.mlxserve/mlxserve.log`. |
| `scripts/mlxserve.sh models` | List models on disk. |
| `scripts/mlxserve.sh pull-primary` | Download `$MLXSERVE_PRIMARY_MODEL`. |
| `scripts/mlxserve.sh load-primary` | `POST /v1/load-model` for the primary. |
| `scripts/mlxserve.sh smoke` | One `/v1/chat/completions` round-trip. |
| `scripts/mlxserve.sh client-smoke [--stream]` | Full OpenAI-contract client smoke. |
| `scripts/mlxserve.sh restart` | `stop` then `start`. |

Environment overrides used on the legacy stack: `MLXSERVE_HOST`, `MLXSERVE_PORT`, `MLXSERVE_MODEL_DIR`, `MLXSERVE_PRIMARY_MODEL`, `MLXSERVE_MAX_RESIDENT_MEM` (default `18GB`), `MLXSERVE_SKIP_MEM_PREFLIGHT` (default `1`), `MLXSERVE_CTX_SIZE` (default `16384`), `MLXSERVE_MAX_TOKENS` (default `1536`), `MLXSERVE_KV_QUANT` (default `4`), `MLXSERVE_PREFILL_CHUNK` (default `1024`), `MLXSERVE_EXTRA_ARGS`.

### Legacy client workflow

`scripts/client_smoke.py` is the canonical supported consumer of the legacy stack. It calls `POST http://127.0.0.1:11234/v1/chat/completions` and validates the OpenAI Chat Completions response.

- **Non-streaming:** `scripts/mlxserve.sh client-smoke` → `OK non-streaming model=… prompt=… completion=… total=… elapsed=… finish=stop`. Exit code `0`.
- **Streaming (SSE):** `scripts/mlxserve.sh client-smoke --stream` → `OK streaming frames=… chars=…`, with `[DONE]` sentinel and delta reassembly verified. Exit code `0`.
- **Failure signal:** any HTTP / URL / JSON / contract violation exits non-zero with a `FAIL: …` line on stderr.

### Legacy memory and stability envelope (24 GB M4 Pro)

Observed during Waves 1–3 verification against the Qwen3-Coder-30B model:

| Phase | Wired memory | Free memory |
| --- | --- | --- |
| Server started, no model | ~2.0 GB | ~316 MB free (plus idle inactive) |
| After `/v1/load-model` (ready) | ~18.5 GB | ~500 MB – 2 MB |
| After two `/v1/chat/completions` | ~18.5 GB (flat) | stable |
| After `scripts/mlxserve.sh stop` | ~2.0 GB | ~4 GB (fully reclaimed) |

- `bytes_resident` for the loaded model: **17.18 GB**.
- Load time: ~7–12 s cold.
- Decode: ~90–94 tok/s on the primary model.
- **Practical accepted-prompt ceiling: ~13.5K tokens** on the legacy stack, up from ~3.6K under Wave A. Binding constraint was a per-request GPU-memory pre-flight in `mlx-serve`, not `--ctx-size`. Wave B at `--ctx-size 16384 --prefill-chunk 1024 --kv-quant 4 --max-resident-mem 20GB` with `max_tokens=256`: ~13.6K accepted (peak ~19.0 GB active), ~14.4K rejected. The single biggest lever was `--prefill-chunk`; lowering it from 8192 to 1024 lifted the ceiling from ~4K to ~13.5K.
- **32K context was possible but not stable.** Small prompts worked and the per-request gate accepted up to ~24K tokens at `max_tokens<=64`, but real workloads at ~22K prompt + `max_tokens=128` crashed the MLX Metal command buffer with `kIOGPUCommandBufferCallbackErrorOutOfMemory`.
- **`--skip-mem-preflight` did NOT bypass the per-request GPU-memory gate** — only the one-shot free-RAM check at model load.
- **The startup line `Model context length: 4096 tokens` is cosmetic** in `mlx-serve 26.8.7`; the enforced cap was `--ctx-size` (16384).

### Legacy safety note: 18GB resident cap (2026-08-17 revision)

On 2026-08-17 the Mac suffered a full macOS kernel panic during a modest MLXServe workload (8,260-token prompt, streaming, speculative decoding active). The panic report was `"completeMemory() prepare count underflow" @IOGPUMemory.cpp:550` in Apple's `com.apple.iokit.IOGPUFamily` driver, with `mlx-serve` listed as the panicked task. The evidence does not establish whether the underlying defect is in MLXServe, MLX, Metal/IOGPUFamily, or an interaction among them.

The wrapper's `MLXSERVE_MAX_RESIDENT_MEM` default was reduced from `20GB` to `18GB` after this event. All other frozen-baseline flags were unchanged. Rationale, layered failure modes, and the one-variable-at-a-time / stop-rule discipline governing further tuning are recorded in `STRATEGY.md`.

### Legacy context budget policy (OpenCode + Augment Context Engine)

Measured against the legacy baseline (`scripts/mlxserve.sh` defaults + the older `opencode.json`).

| Item | Value | Source |
| --- | --- | --- |
| Hard context cap | 16,384 tokens | `--ctx-size` (MLXServe); HTTP 400 above this |
| Initial envelope, MCP enabled | ~8,262 tokens | after adding `augment-context-engine` MCP |
| Per retrieval call | ~2,400 tokens / ~10 KB | bounded by `tool_output.max_lines: 200` |
| Compaction reserve | 5,000 tokens | `compaction.reserved` |
| Spare after one retrieval | ~722 tokens | `16,384 − 8,262 − 2,400 − 5,000` |
| Peak measured successful prompt | 15,531 tokens | end-to-end Safety Phase run, natural stop |

**Failure-mode ladder** (legacy stack — the same layered model applies on the current stack, with the layer 2 remediation adapted to `.mlxlm/serve.sh restart`):

| Layer | What the operator sees | Response |
| --- | --- | --- |
| 1. ctx-size overflow | HTTP 400 `"Prompt exceeds maximum context length: N requested, 16384 available"` | Let auto-compaction fire; if it has already run this turn, restart the OpenCode session. |
| 2. Per-request GPU gate | HTTP 400 `"requires ~XMB GPU memory but only ~YMB available"` | Restart the server — warm-cache fragmentation is not fixable client-side. |
| 3. Driver-level instability | Server hang, GPU stall, or (once observed) a macOS kernel panic | Stop the server, honor `STRATEGY.md` stop rules, capture logs, reassess before resuming. |

**Do not** (each item is backed by a measured failure on the legacy stack):

- Do not truncate `tool_output` below the committed defaults. `max_lines: 100 / max_bytes: 8192` produced ~46% less payload but induced a hallucinated-webfetch storm and a ctx-size overflow at request 3.
- Do not assume a fixed token ceiling equals reliability. A post-compaction 11,889-token request was rejected by the per-request GPU gate.
- Do not treat a few clean short runs as proof of sustained-workload safety.

Known gaps at the time of the legacy measurements: edit-producing loop shape undemonstrated at budget; n=1 per condition; long-horizon safety unproven; warm-cache degradation quantified only anecdotally.

### Legacy fallback path

If Qwen3-Coder-30B was too memory-constrained on the legacy stack, `archive/memo3.md` marked Qwen 14B 4-bit as the comfortable fallback:

```sh
export MLXSERVE_PRIMARY_MODEL=mlx-community/<qwen-14b-4bit-repo-id>
scripts/mlxserve.sh pull-primary
scripts/mlxserve.sh restart
scripts/mlxserve.sh load-primary
scripts/mlxserve.sh client-smoke
```

### Legacy Augment Intent status

At the time of the legacy stack, direct Augment Intent → local endpoint routing was not verified. That has since changed: on the current `mlx-lm.server` stack, Intent BYOA via OpenCode is the supported path (see the *Augment Intent (BYOA) integration* section above and `QUICKSTART.md`).

### Legacy references

- MLXServe: <https://mlxserve.com> · <https://github.com/ddalcu/mlx-serve>
- Legacy primary model: <https://huggingface.co/mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit>
