#!/usr/bin/env bash
# Start mlx_lm.server on 127.0.0.1:8080 with the server-side safety caps.
#
# Uses the persistent venv at ~/.mlxlm/venv (mlx-lm 0.31.3 on Python 3.12).
# The startup --model is only a warm default; mlx_lm.server resolves each
# request's `model` field as either a local path or an HF repo id.
#
# Flags passed to `python -m mlx_lm server`:
#   --host                   127.0.0.1 (loopback only; no external exposure)
#   --port                   8080
#   --model                  warm default resolved from MLXLM_SERVE_MODEL
#   --prompt-cache-bytes     max KV-cache bytes; default 6 GB
#                            (override: MLXLM_PROMPT_CACHE_BYTES)
#   --prompt-cache-size      max distinct KV caches; default 4
#                            (override: MLXLM_PROMPT_CACHE_SIZE)
#   --prefill-step-size      prefill step; default 1024 (mlx-lm default is 2048)
#                            (override: MLXLM_PREFILL_STEP_SIZE)
#
# NOT server-side on mlx-lm 0.31.3 (the --help surface does not expose them):
#   - 16,384 context window        -> enforced by opencode.json provider `context`
#   - 1,536 max output tokens      -> enforced by opencode.json `max_output_tokens`
#   - 4-bit KV quantisation        -> no flag on 0.31.3; policy only (aspiration)
#   - 18 GB physical-footprint cap -> measured by .mlxlm/health.sh via
#                                     /usr/bin/footprint (not enforced here)
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

# Server-side prompt-cache caps (mlx-lm 0.31.3 --prompt-cache-bytes / --prompt-cache-size).
# Defaults: 6 GB (6,442,450,944 bytes) and 4 sequences. Overridable via env vars.
PROMPT_CACHE_BYTES="${MLXLM_PROMPT_CACHE_BYTES:-6442450944}"
PROMPT_CACHE_SIZE="${MLXLM_PROMPT_CACHE_SIZE:-4}"

# Server-side prefill step size (mlx-lm 0.31.3 --prefill-step-size).
# Default: 1024 (mlx-lm's own default is 2048). Overridable via env var.
PREFILL_STEP_SIZE="${MLXLM_PREFILL_STEP_SIZE:-1024}"

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
      --prompt-cache-bytes "$PROMPT_CACHE_BYTES" \
      --prompt-cache-size "$PROMPT_CACHE_SIZE" \
      --prefill-step-size "$PREFILL_STEP_SIZE" \
      >> "$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    printf 'started: pid=%s alias=%s model=%s log=%s prompt_cache_bytes=%s prompt_cache_size=%s prefill_step_size=%s\n' \
      "$(cat "$PIDFILE")" "$SELECTED_ALIAS" "$PRIMARY_MODEL" "$LOG" \
      "$PROMPT_CACHE_BYTES" "$PROMPT_CACHE_SIZE" "$PREFILL_STEP_SIZE"
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
