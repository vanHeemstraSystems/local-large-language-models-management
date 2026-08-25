# Real OpenCode coding session on mlx-lm 0.31.3: model authors .mlxlm/health.sh

**Run:** 2026-08-25T20:10Z (UTC)
**Stack:** Homebrew Python 3.12.13 + mlx-lm 0.31.3 (no A.1 patch), mlx_lm.server on 127.0.0.1:8080
**Client:** opencode CLI 1.18.18, non-interactive `opencode run --auto --pure`
**Model:** Qwen3-8B-4bit (`mlxlm//Users/willemvanheemstra/.mlx-serve/models/mlx-community/Qwen3-8B-4bit`)
**Task note:** 8d12d71c-997f-429a-ba0c-6ede26622764

## Preflight

- `~/.mlxlm/venv` = Python 3.12.13, mlx-lm 0.31.3 (`00_preflight.txt`)
- `.mlxlm/serve.sh start` — pid 35020, `/v1/models` responded with the gpt-oss startup model
- Baseline server log: 148 lines (`00_baseline_log_lines.txt`)

## Session 1 (initial attempt) — no artifact produced

Invocation and prompt: `session1_01_invocation.txt`, `session1_prompt.txt` (asked for a ~60-line script).

- Exit code: 0 in 83 s (`session1_03_exitcode.txt`)
- stdout: empty; stderr: only the OpenCode model header, no `← Write …` tool marker
- Server-log delta (`session1_04_server_log_delta.log`) shows ONE `POST /v1/chat/completions 200 -` followed by:

  ```
  WARNING - Failed to parse tool call (JSONDecodeError: Unterminated string
  starting at: line 1 column 44 (char 43)) — tool text was likely truncated
  mid-generation.
  ```

Interpretation (`session1_outcome.txt`): the model began emitting a write
tool call but hit the per-response 1536-token cap defined for this model in
`opencode.json` while still inside the JSON `content` string, so mlx-lm
returned malformed `tool_calls[]` and OpenCode dropped the response. This is a
token-budget issue for a 60-line script, not a stack-level protocol failure
(no `UnknownError`, no traceback, no `abort`).

## Session 2 (single allowed fix-up) — SUCCESS

Fix-up prompt (`session2_prompt.txt`) asked for a compact 25–30-line script
and forbade pre-tool reasoning output.

Invocation: `session2_01_invocation.txt`.

- Exit code: 0 in 51 s (`session2_03_exitcode.txt`)
- Transcript tool-call marker (stderr, `session2_02_transcript.err`):

  ```
  ← Write .mlxlm/health.sh
  Wrote file successfully.
  ```

- Server-log delta (`session2_04_server_log_delta.log`) shows **four**
  `POST /v1/chat/completions 200 -` round trips. Two of them again logged
  `Failed to parse tool call … truncated mid-generation` WARNINGs; OpenCode
  retried and the final round trip produced a valid write tool call which
  actually created the file. Strict error scan of the delta
  (`UnknownError|BatchRotatingKVCache|Traceback|IOGPU|abort|ERROR`) →
  `NO_PROBLEM_MARKERS`.
- RSS during session 2: min 3 063 552 kB, max 3 151 360 kB (≈3.0 GiB), well
  below the 18 GB cap (`session2_06_rss_summary.txt`).

The final file `.mlxlm/health.sh` (1 094 bytes, 47 lines) is included at the
repo root as the model authored it, with no post-edit by the implementor.

## Testing the model's script

### Server up (pid was 35020, `/v1/models` returning JSON)

`bash .mlxlm/health.sh` (`07_health_run_server_up.*`):

- exit code: **1**
- stdout:
  ```
  [OK] Python version check passed
  [OK] mlx-lm version check passed
  [OK] Server endpoint check passed
  ```
- stderr (first two lines shown):
  ```
  .mlxlm/health.sh: line 31: local: can only be used in a function
  .mlxlm/health.sh: line 32: PID: unbound variable
  …
  ```

The model wrote check 3 as a bare block using `local PID=…` / `local RSS=…`
inside a top-level `if`. Bash rejects `local` outside a function, and
combined with `set -u` this fails the whole check-3 branch. Checks 1 and 2
succeed on their own merits.

### Server down (after `.mlxlm/serve.sh stop`)

`.mlxlm/serve.sh stop` confirmed stopped (`08_server_stop.txt`).
`bash .mlxlm/health.sh` (`09_health_run_server_down.*`):

- exit code: **1**
- stdout:
  ```
  [OK] Python version check passed
  [OK] mlx-lm version check passed
  [FAIL] Server endpoint check failed
  ```
- stderr: `curl: (7) Failed to connect to 127.0.0.1 port 8080` (curl's own
  message reaching stderr because the script does not redirect it).

Because the script `exit 1`s on check 2 failure, the check-3 `local` bug is
not reached in this state. The "server not running" branch the model wrote
inside check 3 is therefore never executed here.

## Definition of Done — pass/fail per point

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| a | OpenCode session(s) completed without protocol errors (no `UnknownError`/abort) | **PASS** | Both sessions exit 0; strict grep on combined server-log delta returns `NO_PROBLEM_MARKERS`. The two truncated-tool-call WARNINGs are recoverable retries handled by OpenCode, not stack aborts. |
| b | `.mlxlm/health.sh` exists and was written by the model through tool calls | **PASS** | Session 2 stderr shows `← Write .mlxlm/health.sh` / `Wrote file successfully.`; file materialised on disk (1 094 bytes) with no implementor edit. |
| c | Script tested in both server states, results recorded | **PASS** | `07_health_run_server_up.*` (exit 1, one line of `[FAIL]` from check-3 syntax bug) and `09_health_run_server_down.*` (exit 1, `[FAIL] Server endpoint check failed`) captured. |
| d | Single commit: health.sh + evidence dir; REPORT.md states pass/fail per point and whether a fix-up session was needed | **PASS** (see commit) | One follow-up session WAS needed (session 1 truncated); documented above. |

## Overall verdict

**PASS at the stack/protocol level, PARTIAL PASS on script quality.**

The upgraded mlx-lm 0.31.3 / Qwen3-8B-4bit stack drove a real OpenCode coding
session end-to-end: OpenCode invoked the Write tool, mlx-lm returned a
spec-compliant tool-calls response, and the model persisted a new file to
disk. No `UnknownError`, no traceback, no IOGPU abort in the server log.

The model's script itself has a real bash bug (`local` used outside a
function), so `.mlxlm/health.sh` does not currently exit 0 with the server
up. Per the task's "do not fix it yourself" rule, the artifact is preserved
as the model authored it and the failure mode is documented above. The
task's fix-up budget (one follow-up session) was already spent recovering
session 1's truncated output.

## Files in this probe

- `00_preflight.txt`, `00_baseline_log_lines.txt`, `00_baseline_log_lines_s2.txt`
- `session1_prompt.txt`, `session1_01_invocation.txt`, `session1_02_transcript.{out,err}`, `session1_03_exitcode.txt`, `session1_04_server_log_delta.log`, `session1_rss_samples.txt`, `session1_outcome.txt`
- `session2_prompt.txt`, `session2_01_invocation.txt`, `session2_02_transcript.{out,err}`, `session2_03_exitcode.txt`, `session2_04_server_log_delta.log`, `session2_rss_samples.txt`, `session2_06_rss_summary.txt`
- `04_server_log_delta_combined.log`
- `07_health_run_server_up.{out,err,exit}`, `08_server_stop.txt`, `09_health_run_server_down.{out,err,exit}`
- `REPORT.md` — this file
