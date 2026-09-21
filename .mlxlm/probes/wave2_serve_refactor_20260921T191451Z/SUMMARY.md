# Wave 2 — `.mlxlm/serve.sh` refactor evidence

Task note: `Wave 2 — Make serve.sh model-selectable with macOS-safe shell code`
(ID `cb2fc84c-e5db-4c58-b389-cb7126f8d414`).

Timestamp (UTC): 2026-09-21T19:14:51Z (evidence dir name) → run window 19:15–19:21Z.

## Result: acceptance criteria all met

- `.mlxlm/serve.sh` refactored to Bash 3.2-safe code using a `case`-based
  `resolve_model()` helper (no `declare -A`, no Bash 4-only syntax).
- Warm-default model is now `mlx-community/Qwen3-8B-4bit` (the validated local
  model), selected via the new `MLXLM_SERVE_MODEL` env var (default alias:
  `qwen3-8b`). Only `qwen3-8b` is accepted in Wave 2.
- Unknown alias exits `2` with a clear error message and does NOT start the
  server, does NOT write a PID file, and leaves `/v1/models` unreachable.
- No unsupported flag was introduced. `--max-kv-size` was NOT added (does not
  exist in mlx-lm 0.31.3). `--prompt-cache-size` / `--prompt-cache-bytes`
  intentionally NOT added (out of scope; separate controlled cache experiment
  required per the Wave 0 corrections).
- `start`, `stop`, `status`, `log` behavior fully preserved; additive `models`
  subcommand lists the supported alias table.
- `~/intent/workspaces/opencode.json` untouched (present, `size=1386`,
  `mtime=2026-08-31T23:09:03Z`).
- No `.opencodeignore` created anywhere.
- `opencode.json`, `.mlxlm/health.sh`, README/QUICKSTART/STRATEGY/WARP docs,
  and the Qwen3-8B-4bit model weights (`mtime` unchanged since 2026-08-23)
  were not modified in this wave.

## Files in this evidence directory

- `serve.sh.pre` — verbatim pre-refactor copy of `.mlxlm/serve.sh` (rollback
  source). `cp` it back over `.mlxlm/serve.sh` and `chmod +x` to revert.
- `lifecycle_cycles.txt` — script transcript of the 14 lifecycle steps
  (`models`, usage banner, unknown-alias rejection, default start,
  readiness, `status`, `health.sh`, minimal chat, `stop`, explicit-alias
  start/status/health/stop, stop-when-not-running, `log` tail,
  status-when-not-running).
- `tool_protocol/` — full `.mlxlm/probes/tool_protocol_test.sh` output
  (`assertions.log`, `request_*.json`, `response_*.json/sse`, `summary.txt`).
- `four_probes/` — copies of `.mlxlm/probes/pX_*.out.json` (opencode
  `--format json` NDJSON), matching `.servelog` deltas, empty `.stderr` for
  each probe, and `summary.txt` from `run_probes.sh`.
- `probes_servelog_delta.txt` — server-log delta captured strictly around
  the four-probe run.
- `full_wave_servelog_delta.txt` — server-log delta across the whole wave
  (start-to-final-stop).
- `log_offsets.txt` — byte offsets in `.mlxlm/mlxlm-serve.log` at the wave
  boundaries.

## Verification results

### Syntax / lint

- `bash -n .mlxlm/serve.sh` → clean (both `/usr/bin/env bash` and `/bin/bash`;
  both resolve to Bash 3.2.57 on this Mac).
- `shellcheck -s bash .mlxlm/serve.sh` → exit `0`, no findings
  (shellcheck 0.11.0).

### Lifecycle (see `lifecycle_cycles.txt`)

| Step | Result |
|------|--------|
| `models` subcommand | prints `qwen3-8b -> ~/.mlx-serve/models/mlx-community/Qwen3-8B-4bit` |
| Usage banner (no args) | exits `2`, prints `usage: … {start\|stop\|status\|log\|models}` |
| `MLXLM_SERVE_MODEL=bogus start` | exits `2`, no PID file, no `mlx_lm` process, `/v1/models` unreachable |
| Default `start` (no env) | exits `0`, ready in ~2 s (2 probes), warm model = Qwen3-8B-4bit |
| `status` | shows PID + Python cmdline with `--model .../Qwen3-8B-4bit`; `/v1/models` returns the Qwen3-8B-4bit id |
| `.mlxlm/health.sh` (server up) | 3× `[OK]` — Python 3.12.13, mlx-lm 0.31.3, endpoint, RSS 4.58 GiB under 18 GB cap |
| Minimal chat probe | HTTP 200, `finish_reason=stop`, content `"OK"` |
| `stop` (default) | exits `0`, PID file removed, endpoint unreachable |
| `MLXLM_SERVE_MODEL=qwen3-8b start` | identical behavior to default start |
| `stop` (explicit alias) | exits `0`, PID file removed |
| `stop` when not running | prints `no pid file`, exits `0` (idempotent, preserved) |
| `log` | tails `.mlxlm/mlxlm-serve.log` (unchanged behavior) |
| `status` when not running | prints `not running` + curl-connection-refused message (preserved) |

### Tool-protocol harness (`tool_protocol/`)

- Non-stream mode: ALL PASS — `tool_calls.count=1`, non-null id, `type=function`,
  `function.name=get_current_directory`, arguments valid JSON.
- Stream mode: ALL PASS — 4 SSE events, id stable across deltas, correct
  `finish_reason=tool_calls`.

### Four probes (`four_probes/`)

| Probe | `step_finish.reason` | Notes |
|-------|-----------------------|-------|
| P1 transport | `stop` | reply `PROBE_1_TRANSPORT_OK` |
| P2 modeling | `stop` | Faulhaber one-liner `n*(n+1)*(2*n +1)//6` |
| P3 resource | `tool-calls` → `stop` | MCP `augment-context-engine_codebase-retrieval` invoked, then natural stop |
| P4 long-context | `stop` | reply `OK` on ~5 KB prompt |

All four opencode invocations exited `0` with empty stderr. Total run
`2m18s`; server RSS stayed between 4.4 – 4.8 GB.

### Server-log health (full wave)

Crash-marker scan across the full wave delta
(`full_wave_servelog_delta.txt`, 77 lines):

| Marker | Count |
|--------|-------|
| `Traceback` | 0 |
| `BatchRotatingKVCache` | 0 |
| `IOGPU` | 0 |
| `shape[- ]mismatch` | 0 |
| `kIOGPUCommandBuffer` | 0 |
| `Broken pipe` | 0 |
| `UnknownError` | 0 |
| `ERROR` | 0 |

HTTP status distribution over the wave: `POST /v1/chat/completions` → 8×200,
`GET /v1/models` → 7×200. No non-200 responses.

## Behavior change vs the pre-refactor `serve.sh`

Recorded honestly:

1. **Warm-default model changed.** Pre-refactor `serve.sh` hard-coded
   `--model .../gpt-oss-20b-MXFP4-Q8` at the CLI even though every runtime
   configuration (`opencode.json`, `.mlxlm/probes/tool_protocol_test.sh`,
   `.mlxlm/health.sh` implicitly) targets `Qwen3-8B-4bit`. The refactor
   aligns the warm default with the validated model. The Wave 0 baseline
   documented this mismatch: startup showed `gpt-oss-20b-MXFP4-Q8` in
   `/v1/models` while the actual smoke request specified the Qwen3-8B-4bit
   path per-request. `/v1/models` output during this wave now shows the
   Qwen3-8B-4bit path directly. This is intentional and matches the Wave 2
   brief ("support only the validated local Qwen3-8B-4bit model initially").
2. **`start` output now includes `alias=` and `model=` fields.** Additive; no
   caller in-repo parses this line.
3. **New subcommand `models`.** Additive; existing subcommand set unchanged.
4. **Unknown alias → exit 2, no server start.** New defensive behavior; no
   pre-existing caller passes an alias.
5. **Comment corrected.** The stale `mlx-lm 0.29.1` note in the file header
   is now `mlx-lm 0.31.3 on Python 3.12`, matching Wave 0 and `.mlxlm/PATCHES.md`.
6. **No new server flags.** No `--max-kv-size`, no cache flags, no
   `--decode-concurrency`/`--prompt-concurrency`/`--pipeline`.

Compared to the last committed post-merge baseline
(`.mlxlm/probes/baseline_postmerge_20260824T001813/`), the four-probe outcome
is at least as good: all four exit `0` and reach `finish=stop` (in Wave 0's
pre-baseline archive, P3 sometimes hit `finish=length` from Qwen3
`<think>`-loop; in this wave P3 correctly used the MCP retrieval tool and
finished with `stop`).

## Honest limitations

- **Rollback path.** `.mlxlm/serve.sh` was NOT tracked in git prior to
  Wave 2 (the entire `.mlxlm/` tree is `.gitignore`d; only `health.sh` and a
  handful of evidence dirs were force-added historically). Wave 2 follows
  that established pattern by force-adding the refactored `serve.sh` and
  this evidence directory. Rollback = restore `serve.sh.pre` (identical to
  the pre-refactor content) via `cp`.
- **Model registry is a single alias.** Wave 2 supports only `qwen3-8b`
  because it is the only alias for which the required verification
  (health + protocol harness + four probes) can be run against an existing
  local model. Adding further aliases is deferred to future waves as noted
  in the Wave 0 approval (Qwen3-Coder-8B-4bit does not exist upstream and
  must not be referenced; Qwen3-Coder-30B is out of scope per the plan).
- **RSS reporting.** The RSS `4.58 GiB` figure comes from `.mlxlm/health.sh`
  (`ps -o rss`) sampled once per health call; peak RSS across the four
  probes was `4.8 GB` from the periodic sampling inside `run_probes.sh`.
  Neither is a continuous max-watermark — same caveat as Wave 0.

## Rollback recipe

```
cp .mlxlm/probes/wave2_serve_refactor_20260921T191451Z/serve.sh.pre .mlxlm/serve.sh
chmod +x .mlxlm/serve.sh
.mlxlm/serve.sh stop || true
.mlxlm/serve.sh start
```

The pre-refactor `serve.sh.pre` starts the warm default it used before
(`gpt-oss-20b-MXFP4-Q8`); this is a full behavioral revert.
