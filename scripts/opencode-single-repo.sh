#!/usr/bin/env bash
# scripts/opencode-single-repo.sh — Bash 3.2-safe guard wrapper for opencode.
#
# Refuses to launch opencode from the ~/intent/workspaces/ parent directory
# or any directory that is not inside a git worktree. From inside a git
# worktree, resolves the repository root via `git rev-parse --show-toplevel`,
# `cd`s to it, and `exec`s opencode with all original arguments preserved.
# The guard runs before any opencode process is started.
#
# Rationale: a parent-level opencode.json (for example
# ~/intent/workspaces/opencode.json) is picked up by opencode when launched
# from that parent directory. A single opencode session there can then read
# across every repository beneath it, defeating single-repository isolation.
#
# Overrides (env vars):
#   OPENCODE_BIN    Path to the opencode binary (default: `command -v opencode`)
#   WORKSPACES_DIR  Parent workspaces directory to refuse
#                   (default: $HOME/intent/workspaces)
#
# Exit codes:
#   0  opencode exec'd from the resolved repository root
#   2  refused: cwd is the workspaces parent, or cwd is not inside a git worktree
#   3  opencode binary not found or not executable
#
# Bash 3.2 compatibility: no associative arrays, no `mapfile`, no `${var,,}`,
# no `[[ =~ ]]` reliance for parsing, no `readarray`. `pwd -P`, `cd --`,
# `command -v`, `exec`, and single-`case` constructs only.
set -eu

log() { printf 'opencode-single-repo: %s\n' "$*" >&2; }

resolve_dir() {
    # Bash 3.2-safe canonicalization: cd into the directory in a subshell and
    # print `pwd -P`. Emits nothing on failure. Caller must fall back.
    ( cd -- "$1" 2>/dev/null && pwd -P )
}

workspaces_default="${HOME}/intent/workspaces"
WORKSPACES_DIR="${WORKSPACES_DIR:-$workspaces_default}"
workspaces_resolved="$(resolve_dir "$WORKSPACES_DIR" || true)"
[ -n "$workspaces_resolved" ] || workspaces_resolved="$WORKSPACES_DIR"

cwd="$(pwd -P)"

if [ "$cwd" = "$workspaces_resolved" ]; then
    log "refusing to launch opencode from the workspaces parent directory:"
    log "  cwd = $cwd"
    log ""
    log "That directory is not a per-repository git worktree. Any opencode.json"
    log "placed there is picked up by opencode and shared across every"
    log "workspace beneath it, letting a single session read across multiple"
    log "repositories."
    log ""
    log "Remediation: cd into the specific repository you want to work on,"
    log "then re-run this wrapper. Example:"
    log "  cd $workspaces_resolved/<workspace>/<repo>"
    log "  $(basename "$0")"
    exit 2
fi

if ! toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    log "refusing to launch opencode: current directory is not inside a git worktree."
    log "  cwd = $cwd"
    log ""
    log "opencode's tool loop reads from and writes to the working directory."
    log "Running it outside a git repository lets edits escape any repository's"
    log "history and blends unrelated files into one session's context."
    log ""
    log "Remediation: cd into a git repository (its root or a subdirectory),"
    log "then re-run this wrapper."
    exit 2
fi

toplevel_resolved="$(resolve_dir "$toplevel" || true)"
if [ -z "$toplevel_resolved" ]; then
    log "refusing to launch opencode: git rev-parse returned an unresolvable path."
    log "  git rev-parse output = $toplevel"
    exit 2
fi

if [ "$toplevel_resolved" = "$workspaces_resolved" ]; then
    log "refusing to launch opencode: resolved git root equals the workspaces parent."
    log "  git root = $toplevel_resolved"
    log "  workspaces parent = $workspaces_resolved"
    exit 2
fi

opencode_bin="${OPENCODE_BIN:-}"
if [ -z "$opencode_bin" ]; then
    opencode_bin="$(command -v opencode 2>/dev/null || true)"
fi
if [ -z "$opencode_bin" ]; then
    log "opencode binary not found on PATH and OPENCODE_BIN is unset."
    log "Install it (brew install opencode) or set OPENCODE_BIN=/abs/path/to/opencode."
    exit 3
fi
if [ ! -x "$opencode_bin" ]; then
    log "opencode binary is not executable: $opencode_bin"
    exit 3
fi

cd -- "$toplevel_resolved"
log "launching opencode from $toplevel_resolved (bin=$opencode_bin)"
exec "$opencode_bin" "$@"
