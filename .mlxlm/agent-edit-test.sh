#!/usr/bin/env bash
# OpenCode read -> edit -> verify acceptance test for the local model.
#
# Creates a fresh scratch dir .mlxlm/probes/agentedit_<ts>/ with a fixture
# greet.txt ("hello\n"), runs `opencode run --format json` with a fixed
# prompt, bounds the run (5 min wall, 15 OpenCode steps, or any new [METAL]
# line in the server log), parses the JSONL for tool parts + step_finish
# token counts, verifies the file content deterministically, and prints a
# per-layer PASS/FAIL table using the diag.sh vocabulary.
#
# Flags:
#   -m <provider/model>   Pass through to `opencode run -m` (default: config).
#   -h | --help           Show usage.
#
# Exit codes: 0 PASS, 1 FAIL (layer, kill, METAL, or health gate), 2 usage.
# Bash 3.2-safe (macOS /bin/bash). Composio must stay disabled upstream.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SERVE_LOG="${MLXLM_SERVE_LOG:-$HERE/mlxlm-serve.log}"
MAX_WALL="${AGENTEDIT_MAX_WALL:-300}"
MAX_STEPS="${AGENTEDIT_MAX_STEPS:-15}"
MODEL=""

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--model) MODEL="${2:-}"; shift 2 ;;
    -h|--help)  sed -n '2,16p' "$0"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v opencode >/dev/null 2>&1 || { echo "opencode not on PATH" >&2; exit 2; }
command -v python3  >/dev/null 2>&1 || { echo "python3 not on PATH"  >&2; exit 2; }

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$HERE/probes/agentedit_${TS}"
mkdir -p "$OUT_DIR"
FIXTURE="$OUT_DIR/greet.txt"
printf 'hello\n' > "$FIXTURE"

HERDR_PATH="$HOME/.config/opencode/plugins/herdr-agent-state.js"
if [ -f "$HERDR_PATH" ]; then HERDR_PRESENT=yes; else HERDR_PRESENT=no; fi
printf 'herdr_plugin=%s path=%s\n' "$HERDR_PRESENT" "$HERDR_PATH" > "$OUT_DIR/herdr_state.txt"

# Health gate: before.
if ! bash "$HERE/health.sh" > "$OUT_DIR/health_before.out" 2>&1; then
  echo "[FAIL] health.sh (before) did not pass; see $OUT_DIR/health_before.out" >&2
  exit 1
fi

MLX_PID="$(pgrep -f mlx_lm.server 2>/dev/null | head -n 1 || true)"
foot_now() {
  [ -n "$MLX_PID" ] || { echo "-"; return; }
  /usr/bin/footprint "$MLX_PID" 2>/dev/null \
    | awk '/Footprint:/ {print $5 $6; exit}'
}
pc_now() {
  grep "Prompt Cache: " "$SERVE_LOG" 2>/dev/null | tail -n 1 \
    | awk '{for(i=1;i<=NF;i++) if($i=="GB"){print $(i-1); exit}}'
}
METAL_BEFORE=$(grep -c '\[METAL\]' "$SERVE_LOG" 2>/dev/null || echo 0)
LOG_OFFSET_BEFORE=$(wc -c < "$SERVE_LOG" 2>/dev/null | awk '{print $1}')
FOOT_BEFORE=$(foot_now); PC_BEFORE=$(pc_now)

PROMPT="Open greet.txt in this directory, append the line 'world' after 'hello', and confirm by reading the file back. Do not do anything else."
RUN_JSONL="$OUT_DIR/run.jsonl"
RUN_ERR="$OUT_DIR/run.stderr"
: > "$RUN_JSONL"

START_EPOCH=$(date +%s)
if [ -n "$MODEL" ]; then
  opencode run --format json --dir "$OUT_DIR" -m "$MODEL" "$PROMPT" \
    >"$RUN_JSONL" 2>"$RUN_ERR" &
else
  opencode run --format json --dir "$OUT_DIR" "$PROMPT" \
    >"$RUN_JSONL" 2>"$RUN_ERR" &
fi
OC_PID=$!

KILL_REASON=""
while kill -0 "$OC_PID" 2>/dev/null; do
  sleep 2
  NOW=$(date +%s); ELAPSED=$((NOW - START_EPOCH))
  STEPS=$(grep -c '"type":"step_start"' "$RUN_JSONL" 2>/dev/null); STEPS=${STEPS:-0}
  NEW_METAL=0
  if [ -f "$SERVE_LOG" ]; then
    NEW_METAL=$(tail -c +"$((LOG_OFFSET_BEFORE + 1))" "$SERVE_LOG" \
      | grep -c '\[METAL\]' 2>/dev/null); NEW_METAL=${NEW_METAL:-0}
  fi
  if [ "$ELAPSED" -ge "$MAX_WALL" ]; then KILL_REASON="wall_${ELAPSED}s"; fi
  if [ "$STEPS"   -gt "$MAX_STEPS" ];  then KILL_REASON="steps_${STEPS}"; fi
  if [ "$NEW_METAL" -gt 0 ];          then KILL_REASON="metal_${NEW_METAL}"; fi
  if [ -n "$KILL_REASON" ]; then
    pkill -TERM -P "$OC_PID" 2>/dev/null || true
    kill -TERM  "$OC_PID"               2>/dev/null || true
    sleep 3
    pkill -KILL -P "$OC_PID" 2>/dev/null || true
    kill -KILL  "$OC_PID"               2>/dev/null || true
    break
  fi
done
wait "$OC_PID" 2>/dev/null
END_EPOCH=$(date +%s); WALL=$((END_EPOCH - START_EPOCH))

STEPS_FINAL=$(grep -c '"type":"step_start"' "$RUN_JSONL" 2>/dev/null); STEPS_FINAL=${STEPS_FINAL:-0}
METAL_AFTER=$(grep -c '\[METAL\]' "$SERVE_LOG" 2>/dev/null); METAL_AFTER=${METAL_AFTER:-0}
FOOT_AFTER=$(foot_now); PC_AFTER=$(pc_now)
if [ -f "$SERVE_LOG" ]; then
  tail -c +"$((LOG_OFFSET_BEFORE + 1))" "$SERVE_LOG" \
    > "$OUT_DIR/server_log_excerpt.log" 2>/dev/null || true
fi

python3 - "$RUN_JSONL" "$FIXTURE" "$OUT_DIR/summary.json" <<'PY'
import json, os, sys
jsonl, fixture, out = sys.argv[1:4]
events = []
with open(jsonl, 'r', errors='replace') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try: events.append(json.loads(line))
        except Exception: pass
step_starts   = [e for e in events if e.get("type") == "step_start"]
step_finishes = [e for e in events if e.get("type") == "step_finish"]
tool_uses     = [e for e in events if e.get("type") == "tool_use"]
tools = []
for ev in tool_uses:
    p = ev.get("part") or {}
    st = p.get("state") or {}
    tools.append({"tool": p.get("tool"), "status": st.get("status"),
                  "input": st.get("input")})
def tl(t): return (t.get("tool") or "").lower()
is_edit  = lambda t: any(k in tl(t) for k in ("edit", "write", "patch", "str_replace"))
is_read  = lambda t: any(k in tl(t) for k in ("read", "cat", "view"))
envelope = (((step_finishes[0] or {}).get("part") or {}).get("tokens") or {}).get("input") if step_finishes else None
last_reason = (((step_finishes[-1] or {}).get("part") or {}).get("reason")) if step_finishes else None
content = None; file_ok = False
if os.path.exists(fixture):
    with open(fixture, 'rb') as f:
        content = f.read().decode('utf-8', errors='replace')
    file_ok = content == "hello\nworld\n"
tool_discovery  = any(is_edit(t) for t in tools)
tool_emission   = any(is_edit(t) and t.get("status") == "completed" for t in tools)
result_handling = tool_emission and file_ok
seen_edit = False; interpretation = False
for t in tools:
    if is_edit(t): seen_edit = True
    elif seen_edit and is_read(t): interpretation = True; break
natural_stop = last_reason == "stop" and len(step_starts) <= 15
summary = {
    "steps": len(step_starts),
    "step_finish_reasons": [((sf.get("part") or {}).get("reason")) for sf in step_finishes],
    "tools_called": tools, "envelope_tokens": envelope,
    "last_reason": last_reason, "file_ok": file_ok, "file_content": content,
    "layers": {"tool_discovery": tool_discovery,
               "tool_call_emission": tool_emission,
               "result_handling": result_handling,
               "interpretation_verification": interpretation,
               "natural_stop": natural_stop},
}
json.dump(summary, open(out, "w"), indent=2)
PY

SUMMARY="$OUT_DIR/summary.json"
get_layer() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["layers"][sys.argv[2]])' "$SUMMARY" "$1"; }
get_field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$SUMMARY" "$1"; }

OVERALL="PASS"
for layer in tool_discovery tool_call_emission result_handling interpretation_verification natural_stop; do
  [ "$(get_layer "$layer")" = "True" ] || OVERALL="FAIL"
done
[ -n "$KILL_REASON" ] && OVERALL="FAIL"

ENVELOPE=$(get_field envelope_tokens)
LAST_REASON=$(get_field last_reason)
FILE_OK=$(get_field file_ok)
NEW_METAL_TOTAL=$((METAL_AFTER - METAL_BEFORE))

{
  printf 'agent-edit-test ts=%s model=%s wall=%ss steps=%s killed=%s overall=%s\n' \
    "$TS" "${MODEL:-<config-default>}" "$WALL" "$STEPS_FINAL" "${KILL_REASON:--}" "$OVERALL"
  printf 'herdr_plugin=%s\n' "$HERDR_PRESENT"
  printf 'footprint before=%s after=%s\n' "${FOOT_BEFORE:--}" "${FOOT_AFTER:--}"
  printf 'prompt_cache_gb before=%s after=%s\n' "${PC_BEFORE:--}" "${PC_AFTER:--}"
  printf 'METAL_lines total before=%s after=%s new=%s\n' "$METAL_BEFORE" "$METAL_AFTER" "$NEW_METAL_TOTAL"
  printf 'envelope_tokens=%s last_reason=%s file_ok=%s\n' "$ENVELOPE" "$LAST_REASON" "$FILE_OK"
  printf '\n'
  printf '%-28s  %s\n' "layer" "status"
  printf -- '----------------------------  ------\n'
  for layer in tool_discovery tool_call_emission result_handling interpretation_verification natural_stop; do
    v=$(get_layer "$layer")
    if [ "$v" = "True" ]; then s=PASS; else s=FAIL; fi
    printf '%-28s  %s\n' "$layer" "$s"
  done
  printf '\nraw: %s\n' "$OUT_DIR"
} | tee "$OUT_DIR/report.txt"

OUTCOME="completed"
if [ "$OVERALL" = "FAIL" ]; then
  case "$KILL_REASON" in
    wall_*|steps_*) OUTCOME="timeout" ;;
    metal_*)        OUTCOME="context_overflow" ;;
    *)              OUTCOME="tool_failure" ;;
  esac
fi
bash "$REPO/scripts/route-log.sh" add \
  --category agentedit \
  --model "${MODEL:-qwen3-8b-4bit}" \
  --outcome "$OUTCOME" \
  --duration "$WALL" \
  --notes "ts=$TS killed=${KILL_REASON:--} herdr=$HERDR_PRESENT env=${ENVELOPE:-NA} steps=${STEPS_FINAL}" \
  >/dev/null 2>&1 || true

if ! bash "$HERE/health.sh" > "$OUT_DIR/health_after.out" 2>&1; then
  echo "[FAIL] health.sh (after) did not pass; see $OUT_DIR/health_after.out" >&2
  exit 1
fi
if [ "$NEW_METAL_TOTAL" -gt 0 ]; then
  echo "[FAIL] $NEW_METAL_TOTAL new [METAL] line(s) in server log during this run" >&2
  exit 1
fi

[ "$OVERALL" = "PASS" ] && exit 0 || exit 1
