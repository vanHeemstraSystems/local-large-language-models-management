# Rebuild ~/.mlxlm/venv on Python 3.12 with mlx-lm 0.31.3 — 2026-08-25

## Outcome

**SUCCESS.** New venv built on Homebrew Python 3.12.13, mlx-lm 0.31.3 installed
alongside mlx 0.32.2. Tool-protocol harness passes both modes; four-probe suite
matches the committed baseline expectations (P1/P2/P4 = `stop`, P3 = `length`).
Server log clean (no tracebacks, no `BatchRotatingKVCache`, no shape mismatch).
Old venv preserved at `~/.mlxlm/venv-py39-mlxlm0291.bak` for rollback.

## Interpreter + versions

- python3.12 binary: `/opt/homebrew/bin/python3.12` → `/opt/homebrew/opt/python@3.12/bin/python3.12`
- reported: `Python 3.12.13`
- new venv python: `/Users/willemvanheemstra/.mlxlm/venv/bin/python` → `python3.12`
- venv `sys.executable`: `/Users/willemvanheemstra/.mlxlm/venv/bin/python`
- venv `sys.version`: `3.12.13 (main, Mar  3 2026, 12:39:30) [Clang 17.0.0 (clang-1700.6.3.2)]`
- installed: `mlx-lm 0.31.3`, `mlx 0.32.2`, `mlx-metal 0.32.2`, `transformers 5.15.1`

Full evidence: `01_venv_create.txt`, `03_mlxlm_install.log`, `04_poststate.txt`.

## Backup preserved

`~/.mlxlm/venv` → `~/.mlxlm/venv-py39-mlxlm0291.bak` (rename, not copy).
Backup interior still shows:
- `mlx_lm 0.29.1` (imported cleanly from backup)
- `lib/python3.9/site-packages/mlx_lm/server.py` present (Python 3.9 A.1 stack intact)

Evidence: `00_backup_prestate.txt`.

## ToolCallFormatter + tc_id fallback (per §4 of the task)

`mlx_lm.server` in 0.31.3 exports `ToolCallFormatter` natively (0.29.1 did not).
The id-when-missing generation is built in — the A.1 patch line the 0.29.1
stack needed is **no longer required**:

```
class ToolCallFormatter:
    def __init__(self, tool_parser, tools, streaming=False):
        ...
    def _format(self, tc):
        tc_id = tc.pop("id", None) or str(uuid.uuid4())
        ...
```

`server.py`: `/Users/willemvanheemstra/.mlxlm/venv/lib/python3.12/site-packages/mlx_lm/server.py`
line 62 (verified via `inspect.getsource`). The old A.1 marker string
`call_{uuid.uuid4().hex[:24]}` is **not** present in this file (only `call_`
substrings appear in unrelated request-id prefixes on lines 1590/1609).

Evidence: `04_poststate.txt` sections
"confirm ToolCallFormatter exists" and "confirm tc_id fallback".

## serve.sh check (per §5)

`.mlxlm/serve.sh` uses `source "$HOME/.mlxlm/venv/bin/activate"` and runs
`python -m mlx_lm server ...`. No hardcoded `python3.9`, no hardcoded
`lib/python3.9`, no absolute interpreter path. **serve.sh unchanged**;
`python -m mlx_lm server` remains a valid subcommand in 0.31.3
(subcommands include `..., server, ...`).

Evidence: `05_serve_sh_check.txt`.

## Server restart + /v1/models (per §6)

Started via `.mlxlm/serve.sh start`, up within 13s. `curl /v1/models` → HTTP 200:

```
{"object": "list", "data": [{"id": ".../mlx-community/gpt-oss-20b-MXFP4-Q8",
"object": "model", "created": 1787686167}]}
```

Process line confirms Python 3.12 interpreter:
```
/opt/homebrew/Cellar/python@3.12/3.12.13/.../Python -m mlx_lm server
  --host 127.0.0.1 --port 8080
  --model .../mlx-community/gpt-oss-20b-MXFP4-Q8
```

Qwen3-8B-4bit loads on first harness request (mlx_lm.server resolves the
per-request `model` field). Evidence: `06a_server_start.txt`, `07_harness_stdout.log`.

## Tool-protocol harness — BOTH modes PASS (per §7)

`.mlxlm/probes/tool_protocol_test.sh` against Qwen3-8B-4bit, results at
`tool_protocol/`. Harness stdout (`07_harness_stdout.log`) final block:

```
nonstream: PASS
stream:    PASS
results:   .../rebuild_py312_mlxlm0.31.3_20260825T192734Z/tool_protocol
ALL PASS
```

- nonstream: 1 tool_call, `id=60796e0f-0966-4c18-92bf-94b420c09a2d`,
  `type=function`, `function.name=get_current_directory`, `arguments={}` (valid JSON).
- stream: 4 SSE events, id stable across deltas
  (`fb1e5cd8-13cc-43fc-b295-2112ee360230`), `finish_reason=tool_calls`.

Note on id format: 0.29.1+A.1 emitted `call_<hex24>`; 0.31.3's built-in
fallback emits raw UUIDs (`str(uuid.uuid4())`). Both are non-null and
harness-stable; the harness only asserts presence/stability/uniqueness.

## Four-probe suite — all exit 0, matches committed baseline (per §8)

From `.mlxlm/probes/summary.txt` (copied to `four_probe/summary.txt`) and
parsed step_finish events (`08_probe_finish_reasons.txt`):

| Probe        | Exit | Elapsed | Finish   | in / out / total | Baseline expectation |
|---           |---   |---      |---       |---               |---                   |
| p1_transport | 0    | 33 s    | `stop`   | 8334 / 237 / 8576  | ✅ stop              |
| p2_modeling  | 0    | 16 s    | `stop`   |   37 / 370 / 8723  | ✅ stop              |
| p3_resource  | 0    | 50 s    | `length` |   49 / 1536 / 9901 | ✅ length allowed    |
| p4_longctx   | 0    | 35 s    | `stop`   | 5238 / 335 / 13889 | ✅ stop              |

P3 hits its 1536 output cap — identical behavior to the committed baseline
(`baseline_mlxlm-0.29.1_20260825T191318Z`).

Evidence: `08_four_probe_stdout.log`, `08_probe_finish_reasons.txt`,
`four_probe/summary.txt`, `four_probe/p*.out.json`.

## Server log during runs (per §9)

`09_serve_delta.log` = slice from server start onward (55 lines).
`grep -E 'Traceback|Error|Exception|BatchRotating|shape mismatch'` → **no matches**
(recorded in `09_serve_delta_errors.txt`).

Log is normal: prompt-processing progress, prompt-cache summaries, and
`POST /v1/chat/completions HTTP/1.1" 200 -` per request.

## Server stopped (per §10)

`.mlxlm/serve.sh stop` → `stopped: pid=28626`; subsequent `status` returns
`not running`. Evidence: `10_server_stop.txt`.

## Verification quotes (per DoD)

- Python + versions: `04_poststate.txt`:
  - `Python 3.12.13`, `mlx-lm 0.31.3` (dist), `mlx 0.32.2` (dist).
- `ToolCallFormatter`: `04_poststate.txt` — `has ToolCallFormatter: True`,
  source printed from `inspect.getsource`, `tc_id = tc.pop("id", None) or str(uuid.uuid4())`.
- Harness exit: `ALL PASS` (harness ends with `exit 0`).
- Probe summary (`four_probe/summary.txt`):
  ```
  probe=p1_transport exit=0 elapsed=33s
  probe=p2_modeling  exit=0 elapsed=16s
  probe=p3_resource  exit=0 elapsed=50s
  probe=p4_longctx   exit=0 elapsed=35s
  ```

## Files in this directory

| File | Content |
|---|---|
| `REPORT.md` | This document |
| `00_backup_prestate.txt` | Backup rename + old venv mlx-lm version + A.1 grep |
| `01_venv_create.txt` | python3.12 path, `venv` creation, symlink readlinks |
| `02_pip_upgrade.log` | `pip install --upgrade pip` output |
| `03_mlxlm_install.log` | `pip install mlx-lm==0.31.3` output (success) |
| `04_poststate.txt` | Python/mlx/mlx-lm versions, ToolCallFormatter source, tc_id grep, `pip freeze` |
| `05_serve_sh_check.txt` | serve.sh hardcoded-path grep + `mlx_lm server` subcommand check |
| `06a_server_start.txt` | `.mlxlm/serve.sh start`, /v1/models, status/ps line |
| `07_harness_stdout.log` | Tool-protocol harness stdout (both modes PASS) |
| `tool_protocol/` | Full harness artifacts (requests, responses, assertions.log, summary.txt) |
| `08_four_probe_stdout.log` | Four-probe suite stdout |
| `08_probe_finish_reasons.txt` | Parsed step_finish `reason` + tokens per probe |
| `four_probe/` | Copies of `summary.txt`, `p*.out.json`, `p*.stderr`, `p*.servelog` |
| `09_serve_delta.log` | Server log slice from start onward |
| `09_serve_delta_errors.txt` | Traceback/error grep result (empty) |
| `10_server_stop.txt` | Server stop + status confirmation |
