# mlx-lm 0.31.3 upgrade attempt — 2026-08-25

## Outcome

**FAILURE (install blocked by transitive dependency); old stack re-validated intact.**

The upgrade `pip install "mlx-lm==0.31.3"` inside `~/.mlxlm/venv` failed before
touching any files: mlx-lm 0.31.3 requires `mlx>=0.31.2; platform_system == "Darwin"`,
and this venv's Python 3.9.6 has no compatible `mlx` wheel on PyPI (the highest
`mlx` available for Python 3.9 is `0.29.3`; the 0.30.x/0.31.x mlx series is
Python 3.10+ only).

Because the install aborted, `mlx-lm` remained pinned at 0.29.1 with the A.1
patch on `server.py:1074` still in place — no rollback action was required.
The old stack was then re-validated end-to-end per the failure-path DoD.

## Pre-state (before install attempt)

- `mlx-lm` version: `0.29.1`
- `mlx` version: `0.29.3`
- Python: `3.9.6`
- `server.py:1074`: `"id": f"call_{uuid.uuid4().hex[:24]}",` (A.1 patch applied)
- `has ToolCallFormatter: False`

See `prestate.txt` for the raw evidence.

## Install failure (exact error)

From `pip_upgrade.log`:

```
Collecting mlx-lm==0.31.3
  Using cached mlx_lm-0.31.3-py3-none-any.whl.metadata (9.5 kB)
ERROR: Could not find a version that satisfies the requirement mlx>=0.31.2;
       platform_system == "Darwin" (from mlx-lm)
       (from versions: ..., 0.29.1, 0.29.2, 0.29.3)
ERROR: No matching distribution found for mlx>=0.31.2; platform_system == "Darwin"
```

`pip index versions mlx` confirmed the ceiling on this interpreter is `0.29.3`.
`pip index versions mlx-lm` confirmed 0.31.3 is the current latest on PyPI.

## Post-state (unchanged, install did not run)

- `mlx-lm` still `0.29.1`
- `server.py:1074` still shows the A.1-patched line (grep captured)
- No files modified in the venv

## Re-validation of the old stack (0.29.1 + A.1 patch)

Server restarted cleanly (`.mlxlm/serve.sh start`), `/v1/models` returns 200.

### Tool-protocol harness — BOTH modes PASS

`.mlxlm/probes/tool_protocol_test.sh` against Qwen3-8B-4bit; results at
`tool_protocol_revalidate/`. Quoted from `harness_stdout.log`:

- `nonstream: PASS` — `id=call_6851a648967748059243bf57`, `type=function`,
  `function.name=get_current_directory`, arguments valid JSON `{}`.
- `stream: PASS` — 6 SSE events, id stable across deltas
  (`call_3b9607a4a1e24ff1bb0a7665`), `finish_reason=stop`.
- Final line: `ALL PASS` (exit 0).

### Four-probe suite — all four exit 0, all `finish_reason=stop`

From `four_probe_stdout.log` and `probe_finish_reasons.txt`
(`four_probe_revalidate/`):

| Probe | Exit | Elapsed | Finish | Tokens in/out | Baseline expectation |
|---|---|---|---|---|---|
| p1_transport | 0 | 35 s | `stop` | 8339 / 312 | ✅ stop |
| p2_modeling  | 0 | 14 s | `stop` | 8353 / 326 | ✅ stop |
| p3_resource  | 0 | 44 s | `stop` (two turns: 8365/497 then 12739/303) | ✅ stop (length also allowed) |
| p4_longctx   | 0 | 33 s | `stop` | 13554 / 326 | ✅ stop |

P3 improved on the committed baseline (baseline: `length` at output=1536; this
run: `stop` on both turns). All other probes match baseline exactly.

### Server log during the run

`serve_delta.log` (log slice from harness start onward): **no** `Traceback`,
`Error`, `BatchRotatingKVCache`, or shape-mismatch matches. Grep in
`probe_finish_reasons.txt` shows empty match set.

## Verification quotes (per DoD)

- Version + ToolCallFormatter inspection: `prestate.txt` lines "Version: 0.29.1",
  "has ToolCallFormatter: False", "1074:                \"id\": f\"call_{uuid.uuid4().hex[:24]}\",".
- Harness exit code / summary:
  ```
  nonstream: PASS
  stream:    PASS
  results:   .mlxlm/probes/upgrade_0.31.3_20260825T191622Z/tool_protocol_revalidate
  ALL PASS
  ```
- Probe summary (from `four_probe_revalidate/summary.txt`):
  ```
  probe=p1_transport exit=0 elapsed=35s
  probe=p2_modeling  exit=0 elapsed=14s
  probe=p3_resource  exit=0 elapsed=44s
  probe=p4_longctx   exit=0 elapsed=33s
  ```

## Server stopped

`.mlxlm/serve.sh stop` → `stopped: pid=26606`; subsequent `status` returns
`not running`.

## Follow-up (out of this task's scope)

To actually reach mlx-lm 0.31.3 the venv would need to be rebuilt on
Python 3.10+ (that's where `mlx>=0.31.2` wheels are published). That is a
venv-lifecycle change, not the "one variable" this task allowed. Report it
back to the coordinator; do not attempt here.

## Files in this directory

| File | Content |
|---|---|
| `REPORT.md` | This document |
| `prestate.txt` | `pip show mlx-lm`, Python version, server.py:1074 grep + context, `ToolCallFormatter` probe |
| `pip_upgrade.log` | Install attempt output + post-check confirming no venv change |
| `harness_stdout.log` | Tool-protocol harness stdout (both modes PASS) |
| `tool_protocol_revalidate/` | Full harness artifacts (requests, responses, assertions.log, summary.txt) |
| `four_probe_stdout.log` | Four-probe suite stdout |
| `four_probe_revalidate/` | Copies of p1..p4 `.out.json` / `.servelog` / `.stderr` and `summary.txt` |
| `probe_finish_reasons.txt` | Parsed `finish_reason` and token counts per probe; traceback grep result |
| `serve_delta.log` | Server log slice from harness start onward (no tracebacks) |
