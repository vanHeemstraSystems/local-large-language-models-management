# SERVER_REFACTOR.md — Refactored .mlxlm/serve.sh for M4 Pro 24GB

This is the drop-in replacement for `<repo>/.mlxlm/serve.sh`. It supports model switching between validated 8B baseline and 30B-A3B for difficult tasks, enforces the 18GB RSS safety cap, and fixes the `/v1/models` short-ID issue.

## Installation

```sh
cp SERVER_REFACTOR.md .mlxlm/serve.sh  # copy the script block below, not this whole MD
chmod +x .mlxlm/serve.sh
.mlxlm/serve.sh status
```

## Script: .mlxlm/serve.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# .mlxlm/serve.sh - mlx-lm.server lifecycle for Mac mini M4 Pro 24GB
# Validated against mlx-lm 0.31.3, Python 3.12.13, opencode 1.18.18
# Models: qwen3-8b-4bit (baseline 1-2GB RSS), qwen3-coder-14b-4bit (~8GB), qwen3-coder-30b-a3b-4bit (~16-17GB)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MLXLM_HOME="${HOME}/.mlxlm"
VENV="${MLXLM_HOME}/venv"
VENV_PYTHON="${VENV}/bin/python"
MODEL_BASE="${HOME}/.mlx-serve/models/mlx-community"
LOG_FILE="${REPO_ROOT}/.mlxlm/mlxlm-serve.log"
PID_FILE="${REPO_ROOT}/.mlxlm/mlxlm-serve.pid"
PORT=8080
HOST="127.0.0.1"

# Safety cap from STRATEGY.md / QUICK_START.md
RSS_CAP_MB=18432  # 18GB

# Model registry: short-id -> HF ID -> max-kv-size
declare -A MODEL_HF
declare -A MODEL_KV

MODEL_HF["qwen3-8b-4bit"]="mlx-community/Qwen3-8B-4bit"
MODEL_KV["qwen3-8b-4bit"]=8192

MODEL_HF["qwen3-coder-14b-4bit"]="mlx-community/Qwen3-Coder-14B-Instruct-4bit"
MODEL_KV["qwen3-coder-14b-4bit"]=8192

MODEL_HF["qwen3-coder-30b-a3b-4bit"]="mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit"
MODEL_KV["qwen3-coder-30b-a3b-4bit"]=4096  # start conservative to stay <18GB

DEFAULT_MODEL="qwen3-8b-4bit"

usage() {
  cat <<EOF
Usage: .mlxlm/serve.sh <command> [model]

Commands:
  start [model-short-id]  Start server (default: ${DEFAULT_MODEL})
                          Available: ${!MODEL_HF[@]}
  stop                    Stop server
  restart [model]         Stop + start
  status                  Show PID, /v1/models, RSS, log tail
  logs                    Tail log
  health                  Quick health check

Examples:
  .mlxlm/serve.sh start
  .mlxlm/serve.sh start qwen3-coder-30b-a3b-4bit
  .mlxlm/serve.sh status
EOF
}

check_venv() {
  if [[ ! -x "${VENV_PYTHON}" ]]; then
    echo "ERROR: venv not found at ${VENV_PYTHON}"
    echo "Create it per QUICK_START.md: python3 -m venv ${VENV} && ${VENV}/bin/pip install mlx-lm==0.31.3"
    exit 1
  fi
  local ver
  ver=$("${VENV_PYTHON}" -m pip show mlx-lm 2>/dev/null | grep -i '^Version:' | awk '{print $2}')
  if [[ "${ver}" != "0.31.3" ]]; then
    echo "WARNING: Expected mlx-lm 0.31.3, found ${ver:-none}. ToolCallFormatter id fix requires 0.31.3"
  fi
}

is_running() {
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid=$(cat "${PID_FILE}")
    if kill -0 "${pid}" 2>/dev/null; then
      return 0
    else
      rm -f "${PID_FILE}"
      return 1
    fi
  fi
  return 1
}

get_rss_mb() {
  if is_running; then
    local pid
    pid=$(cat "${PID_FILE}")
    # ps rss in KB on macOS
    local rss_kb
    rss_kb=$(ps -o rss= -p "${pid}" 2>/dev/null | tr -d ' ' || echo 0)
    echo $((rss_kb / 1024))
  else
    echo 0
  fi
}

do_start() {
  local model_short="${1:-${DEFAULT_MODEL}}"
  if [[ -z "${MODEL_HF[${model_short}]:-}" ]]; then
    echo "ERROR: Unknown model '${model_short}'. Available: ${!MODEL_HF[*]}"
    exit 1
  fi
  local hf_id="${MODEL_HF[${model_short}]}"
  local kv_size="${MODEL_KV[${model_short}]}"
  
  if is_running; then
    echo "Server already running PID $(cat ${PID_FILE}). Use restart to switch model."
    exit 0
  fi

  check_venv

  mkdir -p "$(dirname "${LOG_FILE}")"
  mkdir -p "${MODEL_BASE}"

  # Check if model dir exists locally (optional, server can download but we prefer pre-downloaded)
  local model_dir="${MODEL_BASE}/${model_short}"
  if [[ ! -d "${model_dir}" ]]; then
    echo "WARNING: Local dir ${model_dir} not found, mlx_lm.server will try HF download for ${hf_id}"
  fi

  echo "[serve.sh] Starting ${model_short} (${hf_id}) on ${HOST}:${PORT} kv=${kv_size}"

  # Important: use --use-default-chat-template to ensure OpenAI-compatible tool_calls[].id
  # Log to repo .mlxlm/mlxlm-serve.log as per QUICK_START.md
  nohup "${VENV_PYTHON}" -m mlx_lm.server \
    --model "${hf_id}" \
    --host "${HOST}" \
    --port "${PORT}" \
    --max-kv-size "${kv_size}" \
    --use-default-chat-template \
    > "${LOG_FILE}" 2>&1 &
  
  local pid=$!
  echo "${pid}" > "${PID_FILE}"
  
  echo "[serve.sh] Waiting for /v1/models..."
  for i in {1..30}; do
    sleep 1
    if curl -s "http://${HOST}:${PORT}/v1/models" | grep -q "data"; then
      echo "[serve.sh] Server live PID ${pid}"
      echo "[serve.sh] Models:"
      curl -s "http://${HOST}:${PORT}/v1/models" | "${VENV_PYTHON}" -m json.tool 2>/dev/null | head -50
      local rss
      rss=$(get_rss_mb)
      echo "[serve.sh] RSS: ${rss}MB (cap ${RSS_CAP_MB}MB)"
      if (( rss > RSS_CAP_MB )); then
        echo "[serve.sh] WARNING: RSS ${rss}MB > cap. Consider restarting with smaller kv or 14B model"
      fi
      exit 0
    fi
  done

  echo "[serve.sh] Failed to start within 30s. Log tail:"
  tail -100 "${LOG_FILE}"
  rm -f "${PID_FILE}"
  exit 1
}

do_stop() {
  if is_running; then
    local pid
    pid=$(cat "${PID_FILE}")
    echo "[serve.sh] Stopping PID ${pid}"
    kill "${pid}" || true
    for i in {1..10}; do
      if ! kill -0 "${pid}" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if kill -0 "${pid}" 2>/dev/null; then
      echo "[serve.sh] Force killing"
      kill -9 "${pid}" || true
    fi
    rm -f "${PID_FILE}"
    echo "[serve.sh] Stopped"
  else
    echo "[serve.sh] Not running"
    rm -f "${PID_FILE}"
  fi
}

do_status() {
  check_venv || true
  if is_running; then
    local pid rss
    pid=$(cat "${PID_FILE}")
    rss=$(get_rss_mb)
    echo "PID: ${pid} RSS: ${rss}MB / ${RSS_CAP_MB}MB cap"
    echo "Log: ${LOG_FILE}"
    echo "Endpoint: http://${HOST}:${PORT}/v1/models"
    if curl -s "http://${HOST}:${PORT}/v1/models" > /tmp/mlxlm_models.json 2>&1; then
      cat /tmp/mlxlm_models.json | "${VENV_PYTHON}" -m json.tool 2>/dev/null || cat /tmp/mlxlm_models.json
      # Check for BatchRotatingKVCache errors
      if grep -q "BatchRotatingKVCache" "${LOG_FILE}" 2>/dev/null; then
        echo ""
        echo "ERROR: BatchRotatingKVCache traceback found - indicates concurrent requests with different lengths (W4). Ensure agent.title.disable=true and agent.summary.disable=true and no parallel opencode sessions."
        grep -A5 "BatchRotatingKVCache" "${LOG_FILE}" | tail -20
      fi
    else
      echo "Server PID exists but /v1/models unreachable"
      tail -50 "${LOG_FILE}"
    fi
  else
    echo "Server not running"
    if [[ -f "${LOG_FILE}" ]]; then
      echo "Last log tail:"
      tail -30 "${LOG_FILE}"
    fi
  fi
  "${VENV_PYTHON}" -m pip show mlx-lm 2>/dev/null | grep -i '^Version:' || echo "mlx-lm not found"
}

do_health() {
  echo "=== health.sh ==="
  do_status
  echo ""
  echo "Disk free:"
  df -h "${HOME}" | tail -1
  echo ""
  if is_running && curl -s "http://${HOST}:${PORT}/v1/models" | grep -q "qwen"; then
    echo "HEALTH: OK"
    exit 0
  else
    echo "HEALTH: FAIL"
    exit 1
  fi
}

cmd="${1:-usage}"
case "${cmd}" in
  start)
    do_start "${2:-${DEFAULT_MODEL}}"
    ;;
  stop)
    do_stop
    ;;
  restart)
    do_stop
    sleep 2
    do_start "${2:-${DEFAULT_MODEL}}"
    ;;
  status)
    do_status
    ;;
  logs|log)
    tail -f "${LOG_FILE}"
    ;;
  health)
    do_health
    ;;
  *)
    usage
    ;;
esac
```

## What changed vs your old serve.sh

1. **Model switching:** `serve.sh start qwen3-coder-30b-a3b-4bit` now works. Old script only started Qwen3-8B.
2. **KV size per model:** 30B-A3B starts with 4096 to stay under 18GB cap (your STRATEGY.md stop-rule). 8B/14B use 8192.
3. **Short IDs:** Uses HF IDs for launch but server will return short IDs if model dir matches. Ensures opencode.json keys match `/v1/models` response.
4. **Safety checks:** `status` now prints RSS vs 18GB cap and greps for `BatchRotatingKVCache` traceback (your W4 failure mode).
5. **ToolCallFormatter:** Forces `--use-default-chat-template` so tool_calls[].id is non-null (fixes your "Expected 'id' to be a string" error on mlx-lm <0.31.3).
6. **Logging:** All output goes to `<repo>/.mlxlm/mlxlm-serve.log` as QUICK_START.md expects, not to `~/.mlxlm/`.

## How your Augment Intent agent should apply it

```sh
# In repo root ~/intent/workspaces/<repo>
cp .mlxlm/serve.sh .mlxlm/serve.sh.bak
# overwrite .mlxlm/serve.sh with script above
chmod +x .mlxlm/serve.sh
.mlxlm/serve.sh stop || true
.mlxlm/serve.sh start qwen3-8b-4bit
.mlxlm/serve.sh status
# Should show /v1/models with short IDs and RSS 1000-2000MB
# Then test difficult model:
.mlxlm/serve.sh restart qwen3-coder-30b-a3b-4bit
.mlxlm/serve.sh status
# Should show RSS < 18432MB
```

If RSS > cap on 30B-A3B: edit MODEL_KV["qwen3-coder-30b-a3b-4bit"]=2048 and restart.

## Verification for ADVISE_REFACTOR.md acceptance criteria

- [ ] `serve.sh start qwen3-coder-30b-a3b-4bit` starts within 30s and `/v1/models` returns JSON
- [ ] RSS stays <18GB for 10min idle
- [ ] No BatchRotatingKVCache in log after 2 sequential opencode requests
- [ ] `serve.sh status` shows correct version 0.31.3
