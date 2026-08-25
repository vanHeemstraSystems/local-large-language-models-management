#!/usr/bin/env bash
# Tool-calling protocol test harness (memo6 §7 + §14).
#
# Sends one tool-required prompt (get_current_directory, no params) to
# Qwen3-8B-4bit against http://127.0.0.1:8080/v1/chat/completions, in
# both non-streaming and streaming mode, and asserts the memo6 §7 contract.
#
# Usage:
#   .mlxlm/probes/tool_protocol_test.sh           # writes into a fresh
#                                                 # tool_protocol_<TS>/ dir
#   RESULTS_DIR=... .mlxlm/probes/tool_protocol_test.sh
#
# Exit 0 = all assertions pass, non-zero with FAIL: line = failure.
# Dependencies: bash, curl, python3 (macOS system python is fine).

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE_URL="${MLXLM_BASE_URL:-http://127.0.0.1:8080/v1}"
MODEL="${MLXLM_MODEL:-$HOME/.mlx-serve/models/mlx-community/Qwen3-8B-4bit}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
RESULTS_DIR="${RESULTS_DIR:-$HERE/tool_protocol_${TS}}"
mkdir -p "$RESULTS_DIR"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$RESULTS_DIR/assertions.log"; }
fail() { printf 'FAIL: %s\n' "$*" | tee -a "$RESULTS_DIR/assertions.log" >&2; exit 1; }

log "results_dir=$RESULTS_DIR"
log "base_url=$BASE_URL"
log "model=$MODEL"

# --- reachability -----------------------------------------------------------
code=$(curl -s -o "$RESULTS_DIR/models.json" -w '%{http_code}' -m 5 "$BASE_URL/models" || true)
if [ "$code" != "200" ]; then
  fail "server not reachable at $BASE_URL/models (http=$code). Start with .mlxlm/serve.sh start"
fi
log "server reachable http=$code"

# --- request body -----------------------------------------------------------
python3 - "$MODEL" > "$RESULTS_DIR/request_base.json" <<'PY'
import json, sys
model = sys.argv[1]
body = {
    "model": model,
    "messages": [
        {"role": "system", "content": (
            "You are a tool-using assistant. Whenever the user asks about the "
            "current working directory, you MUST call the get_current_directory "
            "tool exactly once and wait for the result. Do not answer from "
            "memory. /no_think"
        )},
        {"role": "user", "content": (
            "What is the current working directory of the process running you? "
            "Call the get_current_directory tool now to find out. /no_think"
        )},
    ],
    "tools": [{
        "type": "function",
        "function": {
            "name": "get_current_directory",
            "description": "Return the current working directory of the running process.",
            "parameters": {"type": "object", "properties": {}}
        }
    }],
    "tool_choice": "auto",
    "temperature": 0.0,
    "max_tokens": 512,
}
print(json.dumps(body, indent=2))
PY

python3 -c '
import json,sys
b=json.load(open(sys.argv[1]))
b["stream"]=False
json.dump(b, open(sys.argv[2],"w"), indent=2)
' "$RESULTS_DIR/request_base.json" "$RESULTS_DIR/request_nonstream.json"

python3 -c '
import json,sys
b=json.load(open(sys.argv[1]))
b["stream"]=True
json.dump(b, open(sys.argv[2],"w"), indent=2)
' "$RESULTS_DIR/request_base.json" "$RESULTS_DIR/request_stream.json"

# --- mode A: non-streaming --------------------------------------------------
log "--- MODE A: stream=false ---"
code=$(curl -sS -o "$RESULTS_DIR/response_nonstream.json" -w '%{http_code}' \
  -m 180 -H 'Content-Type: application/json' \
  -X POST "$BASE_URL/chat/completions" \
  --data-binary "@$RESULTS_DIR/request_nonstream.json" || true)
log "nonstream http=$code bytes=$(wc -c < "$RESULTS_DIR/response_nonstream.json")"
[ "$code" = "200" ] || fail "non-stream HTTP $code — see response_nonstream.json"

python3 "$HERE/tool_protocol_assert.py" nonstream "$RESULTS_DIR/response_nonstream.json" \
  get_current_directory 2>&1 | tee -a "$RESULTS_DIR/assertions.log"
rc_nonstream=${PIPESTATUS[0]}
[ "$rc_nonstream" -eq 0 ] || fail "non-stream assertions failed (rc=$rc_nonstream)"
log "non-stream: PASS"

# --- mode B: streaming ------------------------------------------------------
log "--- MODE B: stream=true ---"
code=$(curl -sS -N -o "$RESULTS_DIR/response_stream.sse" -w '%{http_code}' \
  -m 180 -H 'Content-Type: application/json' -H 'Accept: text/event-stream' \
  -X POST "$BASE_URL/chat/completions" \
  --data-binary "@$RESULTS_DIR/request_stream.json" || true)
log "stream http=$code bytes=$(wc -c < "$RESULTS_DIR/response_stream.sse")"
[ "$code" = "200" ] || fail "stream HTTP $code — see response_stream.sse"

python3 "$HERE/tool_protocol_assert.py" stream "$RESULTS_DIR/response_stream.sse" \
  get_current_directory 2>&1 | tee -a "$RESULTS_DIR/assertions.log"
rc_stream=${PIPESTATUS[0]}
[ "$rc_stream" -eq 0 ] || fail "stream assertions failed (rc=$rc_stream)"
log "stream: PASS"

# --- summary ----------------------------------------------------------------
{
  printf 'tool-protocol test summary\n'
  printf 'timestamp: %s\n' "$TS"
  printf 'base_url:  %s\n' "$BASE_URL"
  printf 'model:     %s\n' "$MODEL"
  printf 'nonstream: PASS\n'
  printf 'stream:    PASS\n'
  printf 'results:   %s\n' "$RESULTS_DIR"
} | tee "$RESULTS_DIR/summary.txt"

log "ALL PASS"
exit 0
