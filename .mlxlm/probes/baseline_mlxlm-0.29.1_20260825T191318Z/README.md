# Baseline: mlx-lm 0.29.1 (patched A.1) — tool-protocol contract

Captured by `.mlxlm/probes/tool_protocol_test.sh` at `20260825T191318Z`
against the running server at `http://127.0.0.1:8080/v1`.

**Model:** `mlx-community/Qwen3-8B-4bit` (local path).

**Result:** both `stream=false` and `stream=true` pass every memo6 §7
contract assertion (see `assertions.log`, `summary.txt`).

Files:
- `request_base.json`, `request_nonstream.json`, `request_stream.json`
- `response_nonstream.json`, `response_stream.sse`
- `assertions.log`, `summary.txt`, `models.json`, `environment.txt`

Re-run: `bash .mlxlm/probes/tool_protocol_test.sh` (writes to a fresh
timestamped dir, not this one).
