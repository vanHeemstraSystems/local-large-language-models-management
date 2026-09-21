#!/usr/bin/env bash
# Start mlx_lm.server on 127.0.0.1:8080 with the safety-baseline caps.
#
# Uses the persistent venv at ~/.mlxlm/venv (mlx-lm 0.31.3 on Python 3.12).
# The startup --model is only a warm default; mlx_lm.server resolves each
# request's `model` field as either a local path or an HF repo id.
#
# Model selection (Wave 2, macOS /bin/bash 3.2-safe):
#   MLXLM_SERVE_MODEL=<alias>   env var; default: qwen3-8b
#   Supported aliases:
#     qwen3-8b -> ~/.mlx-serve/models/mlx-community/Qwen3-8B-4bit
#   Unknown alias -> exit 2 without starting the server.
#
# Usage:
#   .mlxlm/serve.sh start    # background start, PID written to .mlxlm/serve.pid
#   .mlxlm/serve.sh stop     # kill by PID file
#   .mlxlm/serve.sh status   # ps + /v1/models
#   .mlxlm/serve.sh log      # tail the log
#   .mlxlm/serve.sh models   # list supported model aliases

set -u
STATE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$STATE_DIR/mlxlm-serve.log"
PIDFILE="$STATE_DIR/serve.pid"

HOST=127.0.0.1
PORT=8080
MODEL_DIR_ROOT="$HOME/.mlx-serve/models"
VENV="$HOME/.mlxlm/venv"

# Bash 3.2-compatible model registry (no associative arrays).
resolve_model() {
  case "$1" in
    qwen3-8b)
      printf '%s\n' "$MODEL_DIR_ROOT/mlx-community/Qwen3-8B-4bit"
      ;;
    *)
      return 1
      ;;
  esac
}

list_models() {
  printf 'supported model aliases (Wave 2):\n'
  printf '  %-10s  %s\n' "qwen3-8b" "$MODEL_DIR_ROOT/mlx-community/Qwen3-8B-4bit"
}

SELECTED_ALIAS="${MLXLM_SERVE_MODEL:-qwen3-8b}"

case "${1:-}" in
  start)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      printf 'already running: pid=%s\n' "$(cat "$PIDFILE")"
      exit 0
    fi
    if ! PRIMARY_MODEL="$(resolve_model "$SELECTED_ALIAS")"; then
      printf 'error: unknown model alias: %s\n' "$SELECTED_ALIAS" >&2
      printf 'run: %s models   (for supported aliases)\n' "$0" >&2
      exit 2
    fi
    if [ ! -d "$PRIMARY_MODEL" ]; then
      printf 'error: model directory not found on disk: %s\n' "$PRIMARY_MODEL" >&2
      exit 3
    fi
    # shellcheck disable=SC1091
    source "$VENV/bin/activate"
    nohup python -m mlx_lm server \
      --host "$HOST" \
      --port "$PORT" \
      --model "$PRIMARY_MODEL" \
      >> "$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    printf 'started: pid=%s alias=%s model=%s log=%s\n' \
      "$(cat "$PIDFILE")" "$SELECTED_ALIAS" "$PRIMARY_MODEL" "$LOG"
    ;;
  stop)
    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE")
      kill "$PID" 2>/dev/null && printf 'stopped: pid=%s\n' "$PID"
      rm -f "$PIDFILE"
    else
      printf 'no pid file\n'
    fi
    ;;
  status)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      ps -o pid,rss,command -p "$(cat "$PIDFILE")"
    else
      printf 'not running\n'
    fi
    printf '\n--- /v1/models ---\n'
    curl -sS -m 3 "http://$HOST:$PORT/v1/models" 2>&1 | head -c 800
    printf '\n'
    ;;
  log)
    tail -80 "$LOG"
    ;;
  models)
    list_models
    ;;
  *)
    printf 'usage: %s {start|stop|status|log|models}\n' "$0"
    exit 2
    ;;
esac
