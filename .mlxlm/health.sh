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

# Check 3: Server process and RSS
if ! pgrep -f mlx_lm.server &> /dev/null; then
  echo "[OK] Server not running (RSS check skipped)"
else
  PID=$(pgrep -f mlx_lm.server | head -n 1)
  RSS=$(ps -o rss= -p "$PID")
  GiB=$(awk -v r="$RSS" 'BEGIN{printf "%.2f", r/1024/1024}')
  CAP_GB=18
  if (( $(echo "$GiB < $CAP_GB" | bc -l) )); then
    echo "[OK] Server RSS ${GiB} GiB under ${CAP_GB} GB cap"
  else
    echo "[FAIL] Server RSS ${GiB} GiB over ${CAP_GB} GB cap"
    exit 1
  fi
fi

exit 0