#!/usr/bin/env bash
# scripts/mlxserve.sh — reproducible local lifecycle for MLXServe.
#
# Subcommands:
#   install       Install mlx-serve via Homebrew (tap + trust + formula)
#   start         Start MLXServe in the background, bound to localhost
#   stop          Stop the background MLXServe process
#   restart       Stop then start
#   status        Show pid, port binding, and reachability
#   health        Probe GET /health (exit 0 when healthy)
#   logs          Tail the local log file (Ctrl-C to exit)
#   models        List models on disk (mlx-serve list)
#   foreground    Exec mlx-serve in the foreground (for supervisors / workspace
#                 scripts that want to own the process directly)
#   pull-primary  Download the primary smart-coding model into the model dir
#   load-primary  Ask the running server to load the primary model into memory
#   smoke         Send one /v1/chat/completions request to the primary model
#   client-smoke  Run scripts/client_smoke.py against the running server
#                 (stdlib-only OpenAI-compatible client; add --stream for SSE)
#
# Defaults (override via env vars):
#   MLXSERVE_HOST=127.0.0.1
#   MLXSERVE_PORT=11234
#   MLXSERVE_MODEL_DIR=$HOME/.mlx-serve/models
#   MLXSERVE_EXTRA_ARGS=""   # appended to `mlx-serve --serve ...`
#   MLXSERVE_PRIMARY_MODEL=mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit
#   MLXSERVE_MAX_RESIDENT_MEM=20GB   # tuned for a 24 GB Mac + ~17.6 GB primary
#                                    # weights, leaving ~4 GB for macOS + apps.
#                                    # Set to "auto" to defer to mlx-serve.
#   MLXSERVE_SKIP_MEM_PREFLIGHT=0    # 1 = pass --skip-mem-preflight (bypass the
#                                    # conservative per-load "free RAM now" gate
#                                    # that ignores reclaimable inactive pages).
#
# State (gitignored) lives under .mlxserve/ in the repo root.
set -euo pipefail

HOST="${MLXSERVE_HOST:-127.0.0.1}"
PORT="${MLXSERVE_PORT:-11234}"
MODEL_DIR="${MLXSERVE_MODEL_DIR:-$HOME/.mlx-serve/models}"
EXTRA_ARGS="${MLXSERVE_EXTRA_ARGS:-}"
PRIMARY_MODEL="${MLXSERVE_PRIMARY_MODEL:-mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit}"
MAX_RESIDENT_MEM="${MLXSERVE_MAX_RESIDENT_MEM:-20GB}"
SKIP_MEM_PREFLIGHT="${MLXSERVE_SKIP_MEM_PREFLIGHT:-0}"

# Compose the argv passed to `mlx-serve --serve`. We always include
# --max-resident-mem so the built-in resident-budget sizes for the primary
# model on this 24 GB machine (its 80%-of-wired default caps at ~14 GB, which
# is smaller than the primary model's ~17.6 GB working set). The per-load
# free-RAM pre-flight is separate; enable --skip-mem-preflight only when the
# operator knows the model fits (memo3.md: 17.2 GB weights on 24 GB unified).
SERVE_ARGS=(--serve --host "$HOST" --port "$PORT" --model-dir "$MODEL_DIR")
if [ "$MAX_RESIDENT_MEM" != "auto" ]; then
    SERVE_ARGS+=(--max-resident-mem "$MAX_RESIDENT_MEM")
fi
if [ "$SKIP_MEM_PREFLIGHT" = "1" ]; then
    SERVE_ARGS+=(--skip-mem-preflight)
fi
# shellcheck disable=SC2206
SERVE_ARGS+=($EXTRA_ARGS)

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT_DIR/.mlxserve"
PID_FILE="$STATE_DIR/mlxserve.pid"
LOG_FILE="$STATE_DIR/mlxserve.log"

mkdir -p "$STATE_DIR" "$MODEL_DIR"

MLX_BIN="${MLXSERVE_BIN:-$(command -v mlx-serve || true)}"

log() { printf '[mlxserve] %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }

require_bin() {
    [ -x "$MLX_BIN" ] || die "mlx-serve not on PATH. Run: $0 install"
}

is_running() {
    [ -f "$PID_FILE" ] || return 1
    local pid; pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

cmd_install() {
    command -v brew >/dev/null || die "Homebrew required. See https://brew.sh"
    log "Tapping ddalcu/mlx-serve"
    brew tap ddalcu/mlx-serve https://github.com/ddalcu/mlx-serve >/dev/null
    log "Trusting tap (required for third-party formulae)"
    brew trust ddalcu/mlx-serve >/dev/null 2>&1 || true
    log "Installing mlx-serve"
    brew install mlx-serve
    mlx-serve --help >/dev/null && log "Installed: $(command -v mlx-serve)"
}

cmd_start() {
    require_bin
    if is_running; then
        log "Already running (pid $(cat "$PID_FILE")) on $HOST:$PORT"
        return 0
    fi
    log "Starting mlx-serve on $HOST:$PORT (model-dir=$MODEL_DIR, max-resident-mem=$MAX_RESIDENT_MEM, skip-mem-preflight=$SKIP_MEM_PREFLIGHT)"
    nohup "$MLX_BIN" "${SERVE_ARGS[@]}" \
        >>"$LOG_FILE" 2>&1 &
    echo "$!" >"$PID_FILE"
    # Wait up to 30 s for the port to accept connections.
    local i
    for i in $(seq 1 60); do
        if curl -fsS -o /dev/null "http://$HOST:$PORT/health" 2>/dev/null; then
            log "Healthy after ${i}x0.5s. pid=$(cat "$PID_FILE"), log=$LOG_FILE"
            return 0
        fi
        is_running || die "Process exited during startup. See $LOG_FILE"
        sleep 0.5
    done
    die "Timed out waiting for /health. See $LOG_FILE"
}

cmd_stop() {
    if ! is_running; then
        log "Not running"
        rm -f "$PID_FILE"
        return 0
    fi
    local pid; pid="$(cat "$PID_FILE")"
    log "Stopping pid $pid"
    kill "$pid" 2>/dev/null || true
    local i
    for i in $(seq 1 40); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.25
    done
    if kill -0 "$pid" 2>/dev/null; then
        log "Escalating to SIGKILL"
        kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    log "Stopped"
}

cmd_status() {
    if is_running; then
        printf 'running pid=%s host=%s port=%s log=%s\n' \
            "$(cat "$PID_FILE")" "$HOST" "$PORT" "$LOG_FILE"
    else
        printf 'stopped host=%s port=%s\n' "$HOST" "$PORT"
    fi
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true
}

cmd_health() {
    curl -fsS "http://$HOST:$PORT/health" && echo
}

cmd_logs() {
    [ -f "$LOG_FILE" ] || die "No log file yet at $LOG_FILE"
    tail -n 200 -f "$LOG_FILE"
}

cmd_models() { require_bin; "$MLX_BIN" list; }

cmd_pull_primary() {
    require_bin
    log "Pulling primary model: $PRIMARY_MODEL"
    "$MLX_BIN" pull "$PRIMARY_MODEL"
}

cmd_load_primary() {
    is_running || die "MLXServe is not running. Start it first: $0 start"
    log "Loading primary model into memory: $PRIMARY_MODEL"
    curl -fsS -X POST "http://$HOST:$PORT/v1/load-model" \
        -H 'Content-Type: application/json' \
        -d "{\"model\":\"$PRIMARY_MODEL\"}"
    echo
}

cmd_smoke() {
    is_running || die "MLXServe is not running. Start it first: $0 start"
    log "Smoke test against $PRIMARY_MODEL"
    local prompt="${MLXSERVE_SMOKE_PROMPT:-Write a Python one-liner that returns the sum of squares from 1 to n.}"
    curl -fsS -X POST "http://$HOST:$PORT/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "$(cat <<JSON
{
  "model": "$PRIMARY_MODEL",
  "max_tokens": 128,
  "temperature": 0,
  "messages": [
    {"role": "system", "content": "You are a concise coding assistant."},
    {"role": "user", "content": "$prompt"}
  ]
}
JSON
)"
    echo
}

cmd_client_smoke() {
    is_running || die "MLXServe is not running. Start it first: $0 start"
    local script="$ROOT_DIR/scripts/client_smoke.py"
    [ -f "$script" ] || die "Missing $script"
    log "Client smoke against $HOST:$PORT (model=$PRIMARY_MODEL)"
    MLXSERVE_HOST="$HOST" MLXSERVE_PORT="$PORT" \
        MLXSERVE_PRIMARY_MODEL="$PRIMARY_MODEL" \
        python3 "$script" "$@"
}

cmd_foreground() {
    require_bin
    log "Foreground: mlx-serve on $HOST:$PORT (max-resident-mem=$MAX_RESIDENT_MEM, skip-mem-preflight=$SKIP_MEM_PREFLIGHT)"
    exec "$MLX_BIN" "${SERVE_ARGS[@]}"
}

case "${1:-}" in
    install)      cmd_install ;;
    start)        cmd_start ;;
    stop)         cmd_stop ;;
    restart)      cmd_stop; cmd_start ;;
    status)       cmd_status ;;
    health)       cmd_health ;;
    logs)         cmd_logs ;;
    models)       cmd_models ;;
    foreground)   cmd_foreground ;;
    pull-primary) cmd_pull_primary ;;
    load-primary) cmd_load_primary ;;
    smoke)        cmd_smoke ;;
    client-smoke) shift; cmd_client_smoke "$@" ;;
    ""|-h|--help|help)
        sed -n '2,34p' "$0"; exit 0 ;;
    *) die "Unknown subcommand: $1 (see --help)" ;;
esac
