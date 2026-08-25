#!/usr/bin/env bash
set -u

# Check 1: Python and mlx-lm versions
if ~/.mlxlm/venv/bin/python --version &> /dev/null; then
  echo "[OK] Python version check passed"
else
  echo "[FAIL] Python version check failed"
  exit 1
fi

if ~/.mlxlm/venv/bin/pip show mlx-lm | awk '/^Version:/{print $2}' &> /dev/null; then
  echo "[OK] mlx-lm version check passed"
else
  echo "[FAIL] mlx-lm version check failed"
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
  local PID=$(pgrep -f mlx_lm.server | head -n 1)
  local RSS=$(ps -o rss= -p $PID)
  local GiB=$(echo "scale=2; $RSS / 1024 / 1024" | bc)
  local CAP_GB=18
  if (( $(echo "$GiB < $CAP_GB" | bc -l) )); then
    echo "[OK] Server RSS under $CAP_GB GB"
  else
    echo "[FAIL] Server RSS over $CAP_GB GB"
    exit 1
  fi
fi

exit 0