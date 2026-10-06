#!/usr/bin/env bash
set -u

# Check 1: Python and mlx-lm versions
PY_VERSION=$(~/.mlxlm/venv/bin/python --version 2>&1)
if [ -n "$PY_VERSION" ]; then
  echo "[OK] Python version: $PY_VERSION"
else
  echo "[FAIL] Python version check failed"
  exit 1
fi

MLXLM_VERSION=$(~/.mlxlm/venv/bin/pip show mlx-lm 2>/dev/null | awk '/^Version:/{print $2}')
if [ "$MLXLM_VERSION" = "0.31.3" ]; then
  echo "[OK] mlx-lm version: $MLXLM_VERSION"
else
  echo "[FAIL] mlx-lm version: ${MLXLM_VERSION:-unknown} (expected 0.31.3)"
  exit 1
fi

# Check 2: Server endpoint
if curl -sS -m 3 http://127.0.0.1:8080/v1/models | grep -q "\"data\""; then
  echo "[OK] Server endpoint check passed"
else
  echo "[FAIL] Server endpoint check failed"
  exit 1
fi

# Check 3: Server process memory posture (Metal-aware)
#   - RSS: reported for continuity (informational, no cap).
#   - Physical footprint: capped at CAP_GB (default 18 GB) — the unified-memory
#     measure that correlates with Metal OOMs on Apple Silicon. Falls back from
#     /usr/bin/footprint to `vmmap --summary` if footprint output is empty.
#   - Prompt Cache: parses the most recent `Prompt Cache: N sequences, X GB`
#     line from .mlxlm/mlxlm-serve.log and FAILs if X exceeds the configured
#     --prompt-cache-bytes (MLXLM_PROMPT_CACHE_BYTES, default 6 GB) +10%.
if ! pgrep -f mlx_lm.server &> /dev/null; then
  echo "[OK] Server not running (RSS/footprint/prompt-cache checks skipped)"
else
  PID=$(pgrep -f mlx_lm.server | head -n 1)
  RSS=$(ps -o rss= -p "$PID")
  GiB=$(awk -v r="$RSS" 'BEGIN{printf "%.2f", r/1024/1024}')
  echo "[OK] Server RSS ${GiB} GiB (pid=${PID}, informational)"

  CAP_GB=18
  # /usr/bin/footprint header: "Python [PID]: 64-bit    Footprint: 4662 MB (16384 ...)"
  # Fields: 1=name 2=[pid] 3=arch 4=Footprint: 5=value 6=unit (KB|MB|GB)
  FOOT_RAW=$(/usr/bin/footprint "$PID" 2>/dev/null \
    | awk '/Footprint:/ {print $5 $6; exit}')
  if [ -z "$FOOT_RAW" ]; then
    # vmmap --summary header: "Physical footprint:         4.6G" or "1584K"
    FOOT_RAW=$(vmmap --summary "$PID" 2>/dev/null \
      | awk '/^Physical footprint:/ {print $3; exit}' \
      | sed 's/K$/KB/;s/M$/MB/;s/G$/GB/;s/T$/TB/')
  fi
  if [ -n "$FOOT_RAW" ]; then
    FOOT_GIB=$(awk -v s="$FOOT_RAW" 'BEGIN{
      u=substr(s,length(s)-1); v=substr(s,1,length(s)-2)+0
      if (u=="KB") g=v/1024/1024
      else if (u=="MB") g=v/1024
      else if (u=="GB") g=v
      else if (u=="TB") g=v*1024
      else { print "-"; exit }
      printf "%.2f", g
    }')
    if [ "$FOOT_GIB" != "-" ] && \
       awk -v f="$FOOT_GIB" -v c="$CAP_GB" 'BEGIN{exit !(f < c)}'; then
      echo "[OK] Server physical footprint ${FOOT_GIB} GiB (${FOOT_RAW}) under ${CAP_GB} GB cap"
    else
      echo "[FAIL] Server physical footprint ${FOOT_GIB} GiB (${FOOT_RAW}) over ${CAP_GB} GB cap"
      exit 1
    fi
  else
    echo "[FAIL] Could not read physical footprint for pid=${PID}"
    exit 1
  fi

  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  SERVE_LOG="${MLXLM_SERVE_LOG:-$SCRIPT_DIR/mlxlm-serve.log}"
  PC_BYTES_CAP="${MLXLM_PROMPT_CACHE_BYTES:-6442450944}"
  PC_GB_CAP=$(awk -v b="$PC_BYTES_CAP" \
    'BEGIN{printf "%.2f", (b/1024/1024/1024) * 1.10}')
  # Scope the "most recent" prompt-cache check to lines emitted during the
  # current server run: convert `ps lstart` to the log's "YYYY-MM-DD HH:MM:SS"
  # prefix and keep lines whose ISO-prefix (lex-sorted = time-sorted) >= start.
  LSTART=$(ps -p "$PID" -o lstart= 2>/dev/null | sed 's/[[:space:]]*$//')
  START_STR=$(date -j -f "%a %b %e %T %Y" "$LSTART" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
  PC_LINE=""
  if [ -n "$START_STR" ] && [ -f "$SERVE_LOG" ]; then
    PC_LINE=$(awk -v start="$START_STR" '
      {
        ts = substr($0, 1, 19)
        if (ts >= start && index($0, "Prompt Cache: ") > 0) last=$0
      }
      END { if (last) print last }
    ' "$SERVE_LOG")
  fi
  if [ -n "$PC_LINE" ]; then
    PC_GB=$(printf '%s\n' "$PC_LINE" \
      | awk '{for(i=1;i<=NF;i++) if($i=="GB"){print $(i-1); exit}}')
    if awk -v g="$PC_GB" -v c="$PC_GB_CAP" 'BEGIN{exit !(g <= c)}'; then
      echo "[OK] Last prompt-cache ${PC_GB} GB <= cap ${PC_GB_CAP} GB (--prompt-cache-bytes +10%)"
      echo "     source: ${PC_LINE}"
    else
      echo "[FAIL] Last prompt-cache ${PC_GB} GB > cap ${PC_GB_CAP} GB (--prompt-cache-bytes +10%)"
      echo "       source: ${PC_LINE}"
      exit 1
    fi
  else
    echo "[OK] No Prompt Cache lines since server start (${START_STR:-unknown})"
  fi
fi

exit 0