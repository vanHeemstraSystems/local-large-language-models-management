# SERVER_REFACTOR_V2.md — Refactored .mlxlm/serve.sh (Respects STRATEGY.md Safety Baseline)

> Replaces SERVER_REFACTOR.md
> Core principle: Machine stability outranks maximizing memory
> Validated stack: mlx-lm.server 0.31.3, Qwen3-8B-4bit default, 18GB RSS ceiling, 16K context, 1.5K output, M4 Pro 24GB
> This version REMOVES Qwen3-Coder-30B-A3B - that model was pre-migration stack that contributed to 2026-08-17 IOGPUFamily panic

## Installation

```sh
cp .mlxlm/serve.sh .mlxlm/serve.sh.bak
# Copy script block below to .mlxlm/serve.sh
chmod +x .mlxlm/serve.sh
.mlxlm/serve.sh status
```

## Script: .mlxlm/serve.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# .mlxlm/serve.sh - mlx-lm.server lifecycle for M4 Pro 24GB - V2 SAFE BASELINE
# Respects STRATEGY.md: 18GB RSS ceiling is operator-discipline policy, enforced via client caps + health checks
# Validated: mlx-lm 0.31.3, Python 3.12.13, opencode 1.18.18, macOS 26.5.2
# Models: qwen3-8b-4bit (baseline 1-2GB), qwen3-coder-8b-4bit (1-2GB, shorter think traces) - both safe

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MLXLM_HOME="${HOME}/.mlxlm"
VENV="${MLXLM_HOME}/venv"
VENV_PYTHON="${VENV}/bin/python"
MODEL_BASE="${HOME}/.mlx-serve/models/mlx-community"
LOG_FILE="${REPO_ROOT}/.mlxlm/mlxlm-serve.log"
PID_FILE="${REPO_ROOT}/.mlxlm/mlxlm-serve.pid"
PORT=8080
HOST="127.0.0.1"

# Safety envelope from STRATEGY.md
RSS_CAP_MB=18432  # 18GB - operator policy, NOT enforced by mlx-lm.server CLI

declare -A MODEL_HF
declare -A MODEL_KV

MODEL_HF["qwen3-8b-4bit"]="mlx-community/Qwen3-8B-4bit"
MODEL_KV["qwen3-8b-4bit"]=8192

MODEL_HF["qwen3-coder-8b-4bit"]="mlx-community/Qwen3-Coder-8B-4bit"
MODEL_KV["qwen3-coder-8b-4bit"]=8192

# Optional safe fallback if you need more coding ability but stay <18GB: 14B ~7GB RSS
MODEL_HF["qwen3-coder-14b-4bit"]="mlx-community/Qwen3-Coder-14B-Instruct-4bit"
MODEL_KV["qwen3-coder-14b-4bit"]=8192

DEFAULT_MODEL="qwen3-8b-4bit"

usage() {
  cat <<EOF
Usage: .mlxlm/serve.sh <command> [model-short-id]

Commands:
  start [model]   Start server (default: ${DEFAULT_MODEL})
                 Available: ${!MODEL_HF[@]}
  stop           Stop server
  restart [model] Stop + start
  status         Show PID, /v1/models, RSS vs 18GB cap, BatchRotatingKVCache check
  logs           Tail log
  health         One-command preflight per QUICK_START.md

Examples:
  .mlxlm/serve.sh start
  .mlxlm/serve.sh start qwen3-coder-8b-4bit
  .mlxlm/serve.sh status
  bash .mlxlm/health.sh  # calls status internally

Safety: RSS must stay < ${RSS_CAP_MB}MB. If > cap, stop and restart with smaller model/kv.
EOF
}

check_venv() {
  if [[ ! -x "${VENV_PYTHON}" ]]; then
    echo "ERROR: venv not found at ${VENV_PYTHON}"
    echo "Create per QUICK_START.md: python3 -m venv ${VENV} && ${VENV}/bin/pip install mlx-lm==0.31.3"
    exit 1
  fi
  local ver
  ver=$("${VENV_PYTHON}" -m pip show mlx-lm 2>/dev/null | grep -i '^Version:' | awk '{print $2}' || echo "unknown")
  if [[ "${ver}" != "0.31.3" ]]; then
    echo "WARNING: Expected mlx-lm 0.31.3 (ToolCallFormatter supplies id natively), found ${ver}. See .mlxlm/PATCHES.md"
  fi
}

check_pwd_safety() {
  # Prevent running from intent/workspaces root which indexes all repos
  if [[ "$(basename "$PWD")" == "workspaces" && "$PWD" == *"intent/workspaces"* ]]; then
    echo "ERROR: Do not run from ~/intent/workspaces/ root. cd into ~/intent/workspaces/<single-repo> per STRATEGY.md retrieval strategy."
    exit 1
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
    local pid rss_kb
    pid=$(cat "${PID_FILE}")
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
  check_pwd_safety
  if is_running; then
    echo "Server already running PID $(cat ${PID_FILE}). Use restart to switch."
    exit 0
  fi
  check_venv
  mkdir -p "$(dirname "${LOG_FILE}")"
  local hf_id="${MODEL_HF[${model_short}]}"
  local kv_size="${MODEL_KV[${model_short}]}"

  echo "[serve.sh] Starting ${model_short} (${hf_id}) on ${HOST}:${PORT} kv=${kv_size} - Safety cap ${RSS_CAP_MB}MB"
  echo "[serve.sh] Log: ${LOG_FILE}"

  nohup "${VENV_PYTHON}" -m mlx_lm.server \
    --model "${hf_id}" \
    --host "${HOST}" \
    --port "${PORT}" \
    --max-kv-size "${kv_size}" \
    --use-default-chat-template \
    > "${LOG_FILE}" 2>&1 &
  
  local pid=$!
  echo "${pid}" > "${PID_FILE}"
  
  for i in {1..30}; do
    sleep 1
    if curl -s "http://${HOST}:${PORT}/v1/models" | grep -q "data"; then
      echo "[serve.sh] Live PID ${pid}"
      curl -s "http://${HOST}:${PORT}/v1/models" | "${VENV_PYTHON}" -m json.tool 2>/dev/null | head -60
      local rss
      rss=$(get_rss_mb)
      echo "[serve.sh] RSS: ${rss}MB / ${RSS_CAP_MB}MB cap"
      if (( rss > RSS_CAP_MB )); then
        echo "[serve.sh] STOP-RULE: RSS ${rss}MB > cap - abort per STRATEGY.md"
        do_stop
        exit 1
      fi
      exit 0
    fi
  done
  echo "[serve.sh] Failed to start in 30s. Tail:"
  tail -100 "${LOG_FILE}"
  rm -f "${PID_FILE}"
  exit 1
}

do_stop() {
  if is_running; then
    local pid
    pid=$(cat "${PID_FILE}")
    echo "[serve.sh] Stopping ${pid}"
    kill "${pid}" || true
    for _ in {1..10}; do
      if ! kill -0 "${pid}" 2>/dev/null; then break; fi
      sleep 1
    done
    if kill -0 "${pid}" 2>/dev/null; then kill -9 "${pid}" || true; fi
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
    echo "Endpoint: http://${HOST}:${PORT}/v1/models Log: ${LOG_FILE}"
    if curl -s "http://${HOST}:${PORT}/v1/models" > /tmp/mlxlm_models.json 2>&1; then
      cat /tmp/mlxlm_models.json | "${VENV_PYTHON}" -m json.tool 2>/dev/null || cat /tmp/mlxlm_models.json
      if grep -q "BatchRotatingKVCache" "${LOG_FILE}" 2>/dev/null; then
        echo ""
        echo "W4 ERROR: BatchRotatingKVCache.merge traceback - concurrent requests with different lengths. Mitigation: title.disable + summary.disable + no parallel opencode sessions"
        grep -B2 -A8 "BatchRotatingKVCache" "${LOG_FILE}" | tail -30
      fi
      if (( rss > RSS_CAP_MB )); then
        echo "SAFETY: RSS ${rss}MB > ${RSS_CAP_MB}MB cap - stop per STRATEGY.md stop-rule"
      fi
    else
      echo "PID exists but /v1/models unreachable"
      tail -50 "${LOG_FILE}"
    fi
  else
    echo "Not running"
    tail -30 "${LOG_FILE}" 2>/dev/null || true
  fi
  "${VENV_PYTHON}" -m pip show mlx-lm 2>/dev/null | grep -i '^Version:' || echo "mlx-lm not found"
}

do_health() {
  echo "=== health.sh (per QUICK_START.md) ==="
  do_status
  echo ""
  df -h "${HOME}" | tail -1
  if is_running && curl -s "http://${HOST}:${PORT}/v1/models" | grep -q "qwen"; then
    echo "HEALTH: OK - Green state"
    exit 0
  else
    echo "HEALTH: FAIL - Red/Amber"
    exit 1
  fi
}

cmd="${1:-usage}"
case "${cmd}" in
  start) do_start "${2:-${DEFAULT_MODEL}}" ;;
  stop) do_stop ;;
  restart) do_stop; sleep 2; do_start "${2:-${DEFAULT_MODEL}}" ;;
  status) do_status ;;
  logs|log) tail -f "${LOG_FILE}" ;;
  health) do_health ;;
  *) usage ;;
esac
```

## Changes vs old serve.sh and vs V1 refactor

- **Removed 30B-A3B entirely** - violates STRATEGY.md safety baseline and 18GB cap, historical cause of IOGPUFamily panic
- **Only safe models:** `qwen3-8b-4bit` (1-2GB RSS, validated baseline) and `qwen3-coder-8b-4bit` (same footprint, better coding, shorter <think>), optional `14b` (~7GB, still safe)
- **Added PWD safety check:** Prevents running from `intent/workspaces/` root which causes context explosion + W4 concurrent-like load
- **Enforces 18GB cap:** If RSS > cap, abort per stop-rule
- **Keeps --use-default-chat-template:** Required for ToolCallFormatter id fix (A.1 retired in 0.31.3)

## Verification

```sh
.mlxlm/serve.sh stop || true
.mlxlm/serve.sh start qwen3-coder-8b-4bit
.mlxlm/serve.sh status
# Expected: RSS 1000-3000MB, well below 18432MB, /v1/models returns short IDs
bash .mlxlm/probes/run_probes.sh
cat .mlxlm/probes/summary.txt
# Expected: P1,P2,P4 stop, P3 length OR stop (Coder variant may stop)
```
