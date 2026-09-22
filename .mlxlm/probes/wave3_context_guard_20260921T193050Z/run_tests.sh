#!/usr/bin/env bash
# Test harness for scripts/opencode-single-repo.sh
# Uses a fake opencode that captures cwd + args to prove no real session
# starts and to prove argument preservation.
set -eu

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
EVID_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WRAPPER="$REPO_ROOT/scripts/opencode-single-repo.sh"

echo "REPO_ROOT=$REPO_ROOT"
echo "EVID_DIR=$EVID_DIR"
echo "WRAPPER=$WRAPPER"

FAKE_DIR="$EVID_DIR/fake_bin"
FAKE_LOG="$EVID_DIR/fake_opencode_invocations.log"
mkdir -p "$FAKE_DIR"
: > "$FAKE_LOG"

# The fake opencode: writes a JSON-ish line with cwd + args to $FAKE_LOG,
# then exits 0. If this file is never touched, we know no launch occurred.
cat > "$FAKE_DIR/opencode" <<FAKE
#!/usr/bin/env bash
printf '{"scenario":"%s","cwd":"%s","argc":%d,"argv":[' "\${SCENARIO:-unset}" "\$(pwd -P)" "\$#" >> "$FAKE_LOG"
sep=""
for a in "\$@"; do
    printf '%s"%s"' "\$sep" "\$a" >> "$FAKE_LOG"
    sep=","
done
printf ']}\n' >> "$FAKE_LOG"
FAKE
chmod +x "$FAKE_DIR/opencode"

# Non-git scratch directory (outside any repo).
NON_GIT_DIR="$(mktemp -d -t wave3_nongit.XXXXXX)"
echo "NON_GIT_DIR=$NON_GIT_DIR"

# Workspaces parent (must already exist for a meaningful test).
WORKSPACES_PARENT="$HOME/intent/workspaces"
echo "WORKSPACES_PARENT=$WORKSPACES_PARENT"
[ -d "$WORKSPACES_PARENT" ] || { echo "SKIP: $WORKSPACES_PARENT does not exist"; exit 3; }

run_scenario() {
    scenario="$1"
    from_dir="$2"
    expected_exit="$3"
    expected_launch="$4"   # yes | no

    OUT="$EVID_DIR/${scenario}.stdout"
    ERR="$EVID_DIR/${scenario}.stderr"
    EXIT_FILE="$EVID_DIR/${scenario}.exit"
    LAUNCH_BEFORE="$(wc -l < "$FAKE_LOG" | tr -d ' ')"

    echo "--- scenario=$scenario from=$from_dir ---"
    set +e
    ( cd -- "$from_dir" && OPENCODE_BIN="$FAKE_DIR/opencode" SCENARIO="$scenario" \
        "$WRAPPER" --model qwen3-8b --flag "$scenario arg" ) \
        >"$OUT" 2>"$ERR"
    rc=$?
    set -e
    echo "$rc" > "$EXIT_FILE"

    LAUNCH_AFTER="$(wc -l < "$FAKE_LOG" | tr -d ' ')"
    LAUNCH_DELTA=$((LAUNCH_AFTER - LAUNCH_BEFORE))

    echo "  exit=$rc (expected=$expected_exit)"
    echo "  launch_delta=$LAUNCH_DELTA (expected=$expected_launch)"

    fail=0
    if [ "$rc" != "$expected_exit" ]; then
        echo "  FAIL: exit mismatch"; fail=1
    fi
    case "$expected_launch" in
        yes) [ "$LAUNCH_DELTA" -eq 1 ] || { echo "  FAIL: expected 1 launch"; fail=1; } ;;
        no)  [ "$LAUNCH_DELTA" -eq 0 ] || { echo "  FAIL: expected NO launch"; fail=1; } ;;
    esac
    if [ "$fail" -eq 0 ]; then
        echo "  PASS"
    else
        echo "  ----- stderr -----"; sed 's/^/    /' "$ERR"
        echo "  ----- stdout -----"; sed 's/^/    /' "$OUT"
        return 1
    fi
}

FAIL=0
run_scenario s1_repo_root       "$REPO_ROOT"                   0 yes || FAIL=1
run_scenario s2_repo_subdir     "$REPO_ROOT/scripts"           0 yes || FAIL=1
run_scenario s3_workspaces_parent "$WORKSPACES_PARENT"         2 no  || FAIL=1
run_scenario s4_non_git_tmp     "$NON_GIT_DIR"                 2 no  || FAIL=1

echo "--- fake_opencode_invocations.log ---"
cat "$FAKE_LOG"

echo "--- cleanup ---"
rmdir "$NON_GIT_DIR" 2>/dev/null || true

if [ "$FAIL" -eq 0 ]; then
    echo "ALL SCENARIOS PASS"
else
    echo "SOME SCENARIOS FAILED"
    exit 1
fi
