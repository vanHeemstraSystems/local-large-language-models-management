#!/usr/bin/env bash
# One-command local LLM diagnostic ladder (memo 11 §14, current stack).
#
# Runs: health -> basic -> streaming -> tool_call -> tool_loop -> long_ctx
# against mlx-lm.server at http://127.0.0.1:8080/v1 with the committed
# Qwen3-8B-4bit default, prints a PASS/FAIL table with TTFT and gen tok/s,
# and writes raw per-step JSON + a server-log excerpt under
# .mlxlm/probes/diag_<UTC-timestamp>/ (gitignored via .mlxlm/).
#
# Exit codes:
#   0  all steps PASS
#   1  one or more steps FAIL ("Likely failure domain:" names the first layer)
#   2  usage / pre-flight error
#
# Bash 3.2-safe (macOS /bin/bash). Short, sequential requests only; no stress.
# Reuses .mlxlm/health.sh verbatim; does not modify .mlxlm/serve.sh or any probe.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE_URL="${MLXLM_BASE_URL:-http://127.0.0.1:8080/v1}"
MODEL="${MLXLM_MODEL:-$HOME/.mlx-serve/models/mlx-community/Qwen3-8B-4bit}"
SERVE_LOG="${MLXLM_SERVE_LOG:-$HERE/mlxlm-serve.log}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${DIAG_OUT_DIR:-$HERE/probes/diag_${TS}}"
mkdir -p "$OUT_DIR"
LOG_OFFSET_BEFORE=$(wc -c < "$SERVE_LOG" 2>/dev/null || echo 0)

STEPS=""         # table rows, newline-separated: name|status|ttft|tokps|prompt|notes
LIKELY_LAYER=""  # set on first failure; "server" | "protocol" | "context"
FAIL_COUNT=0

export MLXLM_BASE_URL

record_step() { STEPS="${STEPS}${1}|${2}|${3}|${4}|${5}|${6}
"; }

note_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  if [ -z "$LIKELY_LAYER" ]; then LIKELY_LAYER="$1"; fi
}

# ---------- Python helper (one HTTP request -> body + metrics.json) ----------
PY_HELPER="$OUT_DIR/_diag_request.py"
cat > "$PY_HELPER" <<'PY'
import json, os, sys, time, urllib.request, urllib.error

def main():
    body_path, out_body, out_metrics, mode = sys.argv[1:5]
    base_url = os.environ.get("MLXLM_BASE_URL", "http://127.0.0.1:8080/v1")
    url = base_url.rstrip("/") + "/chat/completions"
    with open(body_path, "rb") as f:
        data = f.read()
    accept = "text/event-stream" if mode == "stream" else "application/json"
    req = urllib.request.Request(
        url, data=data, method="POST",
        headers={"Content-Type": "application/json", "Accept": accept},
    )
    m = {
        "ok": False, "http_code": 0, "error": None,
        "elapsed_s": None, "ttft_s": None,
        "prompt_tokens": None, "completion_tokens": None, "gen_tokps": None,
        "max_chunk_gap_s": None, "avg_chunk_gap_s": None, "chunks": 0,
    }
    t0 = time.monotonic()
    try:
        resp = urllib.request.urlopen(req, timeout=180)
    except urllib.error.HTTPError as e:
        m["http_code"] = e.code
        m["error"] = "HTTPError %d" % e.code
        open(out_body, "wb").write(e.read() or b"")
        json.dump(m, open(out_metrics, "w"), indent=2); return
    except Exception as e:
        m["error"] = "%s: %s" % (type(e).__name__, e)
        open(out_body, "wb").write(b"")
        json.dump(m, open(out_metrics, "w"), indent=2); return

    m["http_code"] = resp.status
    if mode == "nonstream":
        body = resp.read()
        m["elapsed_s"] = time.monotonic() - t0
        open(out_body, "wb").write(body)
        try:
            d = json.loads(body)
            usage = d.get("usage") or {}
            m["prompt_tokens"] = usage.get("prompt_tokens")
            m["completion_tokens"] = usage.get("completion_tokens")
            if m["completion_tokens"] and m["elapsed_s"]:
                m["gen_tokps"] = m["completion_tokens"] / m["elapsed_s"]
            m["ok"] = resp.status == 200
        except Exception as e:
            m["error"] = "parse: %s" % e
    else:
        gaps = []
        last_t = None
        first_t = None
        chunks = 0
        last_ev = None
        with open(out_body, "wb") as fb:
            for raw in resp:
                now = time.monotonic()
                fb.write(raw)
                line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
                if not line.startswith("data:"):
                    continue
                payload = line[len("data:"):].strip()
                if payload in ("", "[DONE]"):
                    continue
                try:
                    ev = json.loads(payload)
                except Exception:
                    continue
                is_content = False
                for ch in ev.get("choices") or []:
                    d = ch.get("delta") or {}
                    if d.get("content") or d.get("tool_calls") or d.get("role"):
                        is_content = True
                if is_content and first_t is None:
                    first_t = now
                if last_t is not None:
                    gaps.append(now - last_t)
                last_t = now
                chunks += 1
                last_ev = ev
        m["elapsed_s"] = time.monotonic() - t0
        m["chunks"] = chunks
        if first_t is not None:
            m["ttft_s"] = first_t - t0
        if gaps:
            m["max_chunk_gap_s"] = max(gaps)
            m["avg_chunk_gap_s"] = sum(gaps) / len(gaps)
        if isinstance(last_ev, dict):
            usage = last_ev.get("usage") or {}
            m["prompt_tokens"] = usage.get("prompt_tokens")
            m["completion_tokens"] = usage.get("completion_tokens")
            ct = m["completion_tokens"]
            if ct and m["ttft_s"] is not None and m["elapsed_s"] and m["elapsed_s"] > m["ttft_s"]:
                m["gen_tokps"] = ct / (m["elapsed_s"] - m["ttft_s"])
            elif ct and m["elapsed_s"]:
                m["gen_tokps"] = ct / m["elapsed_s"]
        m["ok"] = resp.status == 200 and chunks > 0
    json.dump(m, open(out_metrics, "w"), indent=2)

if __name__ == "__main__":
    main()
PY


# ---------- small reader for metrics.json fields ----------
fmt_metric() {
  # args: metrics_file key printf_fmt
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
p, k, fmt = sys.argv[1], sys.argv[2], sys.argv[3]
try: d = json.load(open(p))
except Exception: print("-"); raise SystemExit
v = d.get(k)
if v is None or v == "": print("-")
else:
    try: print(fmt % float(v))
    except Exception: print(str(v))
PY
}

step_from_metrics() {
  # args: step_name layer metrics_file [extra_notes]
  local name="$1" layer="$2" mf="$3" extra="${4:-}"
  local ok ttft tokps ptok
  ok=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("ok"))' "$mf" 2>/dev/null || echo False)
  ttft=$(fmt_metric "$mf" ttft_s "%.3f")
  tokps=$(fmt_metric "$mf" gen_tokps "%.1f")
  ptok=$(fmt_metric "$mf" prompt_tokens "%.0f")
  if [ "$ok" = "True" ]; then
    record_step "$name" "PASS" "$ttft" "$tokps" "$ptok" "$extra"
  else
    local err
    err=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("error") or ("http="+str(d.get("http_code"))))' "$mf" 2>/dev/null || echo "unknown")
    record_step "$name" "FAIL" "$ttft" "$tokps" "$ptok" "$err"
    note_fail "$layer"
  fi
}

# ---------- request-body builders (python) ----------
build_body() {
  # args: out_file mode(stream|nonstream) template_tag [extra_json]
  python3 - "$1" "$2" "$3" "$MODEL" "${4:-}" <<'PY'
import json, sys
out, mode, tag, model, extra = sys.argv[1:6]
stream = (mode == "stream")
sys_msg = "You are a terse assistant. Answer in <=20 tokens. /no_think"
user_msg = ""
tools = None
if tag == "basic":
    user_msg = "Say exactly: BASIC_OK /no_think"
elif tag == "stream":
    user_msg = "Count from 1 to 5 separated by spaces. Only the digits. /no_think"
elif tag == "tool_call":
    sys_msg = ("You are a tool-using assistant. When asked about the current "
               "working directory, call get_current_directory exactly once. "
               "Do not answer from memory. /no_think")
    user_msg = ("What is the current working directory of the process "
                "running you? Call the tool now. /no_think")
    tools = [{"type": "function", "function": {
        "name": "get_current_directory",
        "description": "Return the current working directory of the running process.",
        "parameters": {"type": "object", "properties": {}}}}]
elif tag == "longctx":
    base = ("The quick brown fox jumps over the lazy dog near the riverbank, "
            "while the vigilant hawk observes from a nearby oak tree branch. ")
    user_msg = ("Below is filler text. Ignore its content. After it, on the "
                "LAST LINE ONLY, reply with the single word: OK\n\n"
                + (base * 320) + "\n\nAnswer with just: OK /no_think")
body = {
    "model": model,
    "messages": [{"role": "system", "content": sys_msg},
                 {"role": "user", "content": user_msg}],
    "temperature": 0.0,
    "max_tokens": 32 if tag == "longctx" else 128,
    "stream": stream,
}
if tools is not None:
    body["tools"] = tools
    body["tool_choice"] = "auto"
    body["max_tokens"] = 256
if stream:
    body["stream_options"] = {"include_usage": True}
if extra:
    body.update(json.loads(extra))
json.dump(body, open(out, "w"), indent=2)
PY
}

# ---------- steps ----------
run_step_health() {
  if bash "$HERE/health.sh" > "$OUT_DIR/01_health.out" 2>&1; then
    record_step "health" "PASS" "-" "-" "-" ""
    return 0
  fi
  record_step "health" "FAIL" "-" "-" "-" "see 01_health.out"
  note_fail "server"
  return 1
}

run_step_basic() {
  build_body "$OUT_DIR/02_basic.req.json" nonstream basic
  python3 "$PY_HELPER" "$OUT_DIR/02_basic.req.json" \
    "$OUT_DIR/02_basic.resp.json" "$OUT_DIR/02_basic.metrics.json" nonstream
  step_from_metrics "basic" "server" "$OUT_DIR/02_basic.metrics.json"
}

run_step_stream() {
  build_body "$OUT_DIR/03_stream.req.json" stream stream
  python3 "$PY_HELPER" "$OUT_DIR/03_stream.req.json" \
    "$OUT_DIR/03_stream.resp.sse" "$OUT_DIR/03_stream.metrics.json" stream
  local gap
  gap=$(fmt_metric "$OUT_DIR/03_stream.metrics.json" max_chunk_gap_s "%.3f")
  step_from_metrics "stream" "protocol" "$OUT_DIR/03_stream.metrics.json" "max_gap=${gap}s"
}

run_step_tool_call() {
  build_body "$OUT_DIR/04_tool.req.json" nonstream tool_call
  python3 "$PY_HELPER" "$OUT_DIR/04_tool.req.json" \
    "$OUT_DIR/04_tool.resp.json" "$OUT_DIR/04_tool.metrics.json" nonstream
  local ok
  ok=$(python3 - "$OUT_DIR/04_tool.resp.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    msg = (d.get("choices") or [{}])[0].get("message") or {}
    tcs = msg.get("tool_calls") or []
    if not tcs: print("False"); raise SystemExit
    c = tcs[0]
    if not c.get("id") or (c.get("function") or {}).get("name") != "get_current_directory":
        print("False"); raise SystemExit
    print("True")
except Exception:
    print("False")
PY
)
  if [ "$ok" = "True" ]; then
    step_from_metrics "tool_call" "protocol" "$OUT_DIR/04_tool.metrics.json"
  else
    record_step "tool_call" "FAIL" "-" "-" \
      "$(fmt_metric "$OUT_DIR/04_tool.metrics.json" prompt_tokens "%.0f")" \
      "no valid tool_calls"
    note_fail "protocol"
  fi
}


run_step_tool_loop() {
  # Build the two-step follow-up: assistant.tool_calls + tool result message.
  if [ ! -f "$OUT_DIR/04_tool.resp.json" ]; then
    record_step "tool_loop" "FAIL" "-" "-" "-" "tool_call step missing"
    note_fail "protocol"; return
  fi
  python3 - "$OUT_DIR/04_tool.resp.json" "$MODEL" "$OUT_DIR/05_loop.req.json" "$HERE" <<'PY'
import json, sys
resp = json.load(open(sys.argv[1]))
model, out, cwd = sys.argv[2], sys.argv[3], sys.argv[4]
msg = (resp.get("choices") or [{}])[0].get("message") or {}
tcs = msg.get("tool_calls") or []
if not tcs:
    json.dump({}, open(out, "w")); raise SystemExit
tc = tcs[0]
body = {
    "model": model,
    "messages": [
        {"role": "system", "content": (
            "You are a tool-using assistant. After a tool result arrives, "
            "answer in <=25 tokens quoting the directory. /no_think")},
        {"role": "user", "content": (
            "What is the current working directory of the process "
            "running you? Call the tool now. /no_think")},
        {"role": "assistant", "content": msg.get("content") or "",
         "tool_calls": [tc]},
        {"role": "tool", "tool_call_id": tc["id"],
         "name": (tc.get("function") or {}).get("name"),
         "content": cwd},
    ],
    "temperature": 0.0, "max_tokens": 128, "stream": False,
}
json.dump(body, open(out, "w"), indent=2)
PY
  if [ ! -s "$OUT_DIR/05_loop.req.json" ] || \
     ! python3 -c 'import json,sys; json.load(open(sys.argv[1])).get("messages")' \
         "$OUT_DIR/05_loop.req.json" >/dev/null 2>&1; then
    record_step "tool_loop" "FAIL" "-" "-" "-" "no tool_call from step 4"
    note_fail "protocol"; return
  fi
  python3 "$PY_HELPER" "$OUT_DIR/05_loop.req.json" \
    "$OUT_DIR/05_loop.resp.json" "$OUT_DIR/05_loop.metrics.json" nonstream
  # Protocol-level assertion: final message has non-empty content and no new tool_calls.
  local ok
  ok=$(python3 - "$OUT_DIR/05_loop.resp.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    msg = (d.get("choices") or [{}])[0].get("message") or {}
    content = (msg.get("content") or "").strip()
    print("True" if content and not msg.get("tool_calls") else "False")
except Exception:
    print("False")
PY
)
  if [ "$ok" = "True" ]; then
    step_from_metrics "tool_loop" "protocol" "$OUT_DIR/05_loop.metrics.json"
  else
    record_step "tool_loop" "FAIL" "-" "-" \
      "$(fmt_metric "$OUT_DIR/05_loop.metrics.json" prompt_tokens "%.0f")" \
      "no final content"
    note_fail "protocol"
  fi
}

run_step_longctx() {
  build_body "$OUT_DIR/06_longctx.req.json" nonstream longctx
  python3 "$PY_HELPER" "$OUT_DIR/06_longctx.req.json" \
    "$OUT_DIR/06_longctx.resp.json" "$OUT_DIR/06_longctx.metrics.json" nonstream
  step_from_metrics "longctx" "context" "$OUT_DIR/06_longctx.metrics.json"
}

# ---------- run ladder ----------
printf 'diag ladder start=%s UTC\n' "$TS"
printf 'base_url=%s\nmodel=%s\nout_dir=%s\n\n' "$BASE_URL" "$MODEL" "$OUT_DIR"

if run_step_health; then
  run_step_basic
  run_step_stream
  run_step_tool_call
  run_step_tool_loop
  run_step_longctx
fi

# ---------- server-log excerpt ----------
if [ -f "$SERVE_LOG" ]; then
  tail -c +"$((LOG_OFFSET_BEFORE + 1))" "$SERVE_LOG" > "$OUT_DIR/server_log_excerpt.log" 2>/dev/null || true
fi

# ---------- summary.json + table ----------
printf '%s' "$STEPS" > "$OUT_DIR/.steps.raw"
python3 - "$OUT_DIR/.steps.raw" "$OUT_DIR/summary.json" "$LIKELY_LAYER" "$FAIL_COUNT" "$TS" "$OUT_DIR" <<'PY'
import json, sys
raw, out, layer, fails, ts, outdir = sys.argv[1:7]
rows = []
for line in open(raw):
    line = line.rstrip("\n")
    if not line: continue
    parts = line.split("|")
    while len(parts) < 6: parts.append("")
    rows.append({"step": parts[0], "status": parts[1], "ttft_s": parts[2],
                 "gen_tokps": parts[3], "prompt_tokens": parts[4], "notes": parts[5]})
summary = {"timestamp_utc": ts, "out_dir": outdir, "fail_count": int(fails),
           "likely_failure_domain": layer or None, "steps": rows}
json.dump(summary, open(out, "w"), indent=2)
PY

printf '\n%-10s  %-6s  %10s  %10s  %7s  %s\n' "step" "status" "ttft(s)" "tok/s" "p_tok" "notes"
printf -- '----------  ------  ----------  ----------  -------  ------------------------------------\n'
printf '%s' "$STEPS" | while IFS='|' read -r name status ttft tokps ptok notes; do
  [ -z "$name" ] && continue
  printf '%-10s  %-6s  %10s  %10s  %7s  %s\n' "$name" "$status" "$ttft" "$tokps" "$ptok" "$notes"
done

printf '\nraw results: %s\n' "$OUT_DIR"
if [ "$FAIL_COUNT" -gt 0 ]; then
  printf 'Likely failure domain: %s (%d step(s) failed)\n' "$LIKELY_LAYER" "$FAIL_COUNT"
  exit 1
fi
printf 'all steps PASS\n'
exit 0
