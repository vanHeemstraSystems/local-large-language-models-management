#!/usr/bin/env bash
# scripts/mlxserve.sh — reproducible local lifecycle for MLXServe.
#
# Subcommands:
#   install     Install mlx-serve via Homebrew (tap + trust + formula)
#   start       Start MLXServe in the background, bound to localhost
#   stop        Stop the background MLXServe process
#   restart     Stop then start
#   status      Show pid, port binding, and reachability
#   health      Probe GET /health (exit 0 when healthy)
#   logs        Tail the local log file (Ctrl-C to exit)
#   models      List models on disk (mlx-serve list)
#   foreground  Exec mlx-serve in the foreground (for supervisors / workspace
#               scripts that want to own the process directly)
#
# Defaults (override via env vars):
#   MLXSERVE_HOST=127.0.0.1
#   MLXSERVE_PORT=11234
#   MLXSERVE_MODEL_DIR=$HOME/.mlx-serve/models
#   MLXSERVE_EXTRA_ARGS=""   # appended to `mlx-serve --serve ...`
#
# State (gitignored) lives under .mlxserve/ in the repo root.
set -euo pipefail

HOST="${MLXSERVE_HOST:-127.0.0.1}"
PORT="${MLXSERVE_PORT:-11234}"
MODEL_DIR="${MLXSERVE_MODEL_DIR:-$HOME/.mlx-serve/models}"
EXTRA_ARGS="${MLXSERVE_EXTRA_ARGS:-}"

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
    log "Starting mlx-serve on $HOST:$PORT (model-dir=$MODEL_DIR)"
    # shellcheck disable=SC2086
    nohup "$MLX_BIN" --serve --host "$HOST" --port "$PORT" \
        --model-dir "$MODEL_DIR" $EXTRA_ARGS \
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

cmd_foreground() {
    require_bin
    log "Foreground: mlx-serve --serve --host $HOST --port $PORT"
    # shellcheck disable=SC2086
    exec "$MLX_BIN" --serve --host "$HOST" --port "$PORT" \
        --model-dir "$MODEL_DIR" $EXTRA_ARGS
}

case "${1:-}" in
    install)    cmd_install ;;
    start)      cmd_start ;;
    stop)       cmd_stop ;;
    restart)    cmd_stop; cmd_start ;;
    status)     cmd_status ;;
    health)     cmd_health ;;
    logs)       cmd_logs ;;
    models)     cmd_models ;;
    foreground) cmd_foreground ;;
    ""|-h|--help|help)
        sed -n '2,22p' "$0"; exit 0 ;;
    *) die "Unknown subcommand: $1 (see --help)" ;;
esac
