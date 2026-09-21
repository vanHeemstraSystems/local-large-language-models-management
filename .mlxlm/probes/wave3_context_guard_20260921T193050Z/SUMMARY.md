# Wave 3 — repository-root guard wrapper for opencode

Task note: `Add a repository-root guard wrapper for OpenCode`
(ID `627236a2-4776-44cb-8e5a-7514e9fb70fc`).

Timestamp (UTC): 2026-09-21T19:30:50Z (evidence dir name).

Context: the unavailable `Qwen3-Coder-8B-4bit` experiment (original Wave 3
target) is skipped permanently per user approval. Wave 3 was replaced with
this context-isolation follow-up — no model download, no server config
change, no memory-envelope change.

## Result: acceptance criteria all met

- New tracked file `scripts/opencode-single-repo.sh`, executable (`-rwxr-xr-x`).
- Bash 3.2-compatible (no `declare -A`, no `mapfile`/`readarray`, no
  `${var,,}`, no `[[ =~ ]]` reliance). Verified with `/bin/bash -n`
  (Bash 3.2.57) and `/usr/bin/env bash -n`; both clean.
- `shellcheck -s bash` (0.11.0) reports zero findings.
- From the repository root and a repository subdirectory the wrapper
  resolved the git top-level via `git rev-parse --show-toplevel`, `cd`'d
  there, and `exec`'d a fake opencode with all four original arguments
  preserved (including one arg containing a space).
- From `~/intent/workspaces/` (the workspaces parent) and from a fresh
  non-git `mktemp -d` directory the wrapper exited `2` with a clear
  remediation message on stderr, and the fake opencode was never invoked
  (invocation log delta = 0 for both refusal cases).
- Argument transparency demonstrated: recorded argv for s1/s2 is
  `["--model","qwen3-8b","--flag","<scenario> arg"]` with `argc=4`.
- Wrapper resolves the opencode binary from `OPENCODE_BIN` when set and
  otherwise from `command -v opencode`; refuses with exit `3` when neither
  resolves to an executable path.

## Scope adherence — nothing outside the task brief was touched

Explicitly verified (see `untouched_files_final.txt`, `opencodeignore_final.txt`):

- `~/intent/workspaces/opencode.json` unchanged (`sha256`
  `56cccfa51584d287ff4c1a47a3b3ff512aa2b1a163ae546388fbf18bb91d490d`,
  `mtime=2026-08-31T23:09:03Z`).
- Repo-root `opencode.json` unchanged (`sha256` identical to the parent
  file, `mtime=2026-08-24T00:11:11Z`).
- `.mlxlm/serve.sh` unchanged since Wave 2 (`sha256`
  `782bf87d7d90ffd9bb8d24fa74afea1012da0ab6e64e92a42db7e8322d6d1b48`,
  `mtime=2026-09-21T21:15:28Z` — predates this task start at 19:28Z UTC).
- `.mlxlm/health.sh` unchanged (`sha256`
  `e40dec0cd9894c8d8dc8715a56f8288b24b76d7d0b7241fc947d545b8529a668`,
  `mtime=2026-08-31T09:31:24Z`).
- No `.opencodeignore` created anywhere (checked repo root,
  `~/intent/workspaces/`, `~/intent/workspaces/favourite-coyote/`).
- Model weights directory `~/.mlx-serve/models/mlx-community/Qwen3-8B-4bit`
  untouched (`mtime` of the directory: `Aug 23 23:01`).

`git status --short` (see `git_status_final.txt`) shows exactly three
in-scope entries: `M QUICKSTART.md`, `M WARP.md`, and
`?? scripts/opencode-single-repo.sh`. No other production files modified.

## Files in this evidence directory

- `run_tests.sh` — the harness. Builds `fake_bin/opencode` (a Bash stub
  that appends `{scenario, cwd, argc, argv[]}` to
  `fake_opencode_invocations.log`), then runs the four scenarios and
  asserts exit code + launch delta.
- `run_tests.out` — full transcript of the harness run (`ALL SCENARIOS PASS`).
- `s1_repo_root.{stdout,stderr,exit}` — from `<repo>` root.
- `s2_repo_subdir.{stdout,stderr,exit}` — from `<repo>/scripts`.
- `s3_workspaces_parent.{stdout,stderr,exit}` — from
  `~/intent/workspaces/` (refusal path).
- `s4_non_git_tmp.{stdout,stderr,exit}` — from `mktemp -d` (refusal path).
- `fake_opencode_invocations.log` — the ONLY place opencode invocations
  were recorded; contains exactly two lines (s1 and s2). No entries for
  s3/s4, proving no launch.
- `checks.txt` — `bash -n` and `shellcheck` output.
- `untouched_files{,_final}.txt`, `opencodeignore_check{,_final}.txt`,
  `git_status{,_final}.txt`, `model_weights_check.txt` — scope-adherence
  evidence before and after the doc edits.

## Verification results

### Syntax / lint (`checks.txt`)

- `/bin/bash --version` → `GNU bash, version 3.2.57(1)-release`.
- `/bin/bash -n scripts/opencode-single-repo.sh` → OK.
- `/usr/bin/env bash -n scripts/opencode-single-repo.sh` → OK.
- `shellcheck -s bash scripts/opencode-single-repo.sh` → exit 0, zero findings.

### Four scenarios (`run_tests.out`)

| Scenario | Launched from | Expected exit | Observed exit | Fake-opencode launched? | Verdict |
|---|---|---|---|---|---|
| s1 repo root | `<repo>` root | 0 | 0 | yes (1 line in log) | PASS |
| s2 repo subdirectory | `<repo>/scripts` | 0 | 0 | yes (1 line in log) | PASS |
| s3 workspaces parent | `~/intent/workspaces` | 2 | 2 | no (0 lines added) | PASS |
| s4 non-git tmp dir | `$(mktemp -d)` | 2 | 2 | no (0 lines added) | PASS |

Recorded cwd inside the fake opencode for s1 and s2 was
`<repo>` root in both cases (proving the `cd $(git rev-parse
--show-toplevel)` step ran). Recorded argv for both was
`["--model","qwen3-8b","--flag","<scenario> arg"]` with `argc=4` (proving
argument preservation, including an argument containing whitespace).

### Refusal messages (excerpts from `s3_*.stderr` / `s4_*.stderr`)

- s3 (workspaces parent): "refusing to launch opencode from the workspaces
  parent directory: cwd = /Users/…/intent/workspaces" + rationale + `cd
  …/<workspace>/<repo>` remediation.
- s4 (non-git): "refusing to launch opencode: current directory is not
  inside a git worktree." + rationale + `cd` remediation.

Both refusals hit exit code `2`. Neither wrote to stdout. Neither invoked
the fake opencode.

## Documentation changes (scope-limited, focused on the wrapper)

- `QUICKSTART.md`: step 3 of the daily workflow renamed to "Launch OpenCode
  via the single-repository guard wrapper"; command is
  `scripts/opencode-single-repo.sh`; two-tab Warp table row updated;
  preflight step 3 updated to reference the wrapper and its refusal
  behavior; end-to-end example updated to invoke the wrapper.
- `WARP.md`: two-tab launch line updated to call the wrapper; added a
  short "Why use the guard wrapper instead of plain `opencode`?" section
  explaining the parent-`opencode.json` hazard and the single-repo
  guarantee.

No other production files were modified. `opencode.json`,
`.mlxlm/serve.sh`, `.mlxlm/health.sh`, model weights, server limits, and
`~/intent/workspaces/opencode.json` are untouched.

## Honest limitations

- The wrapper's `WORKSPACES_DIR` default is `$HOME/intent/workspaces`.
  Users with a different Intent workspaces layout must override
  `WORKSPACES_DIR`; the wrapper still catches non-git directories via
  `git rev-parse --show-toplevel`, but the parent-directory refusal will
  not fire against a different literal path unless overridden.
- The tests use a fake opencode. They prove the guard behavior and
  argument preservation, but do NOT run a real MCP tool loop against the
  live server. That is out of scope for this task and is already
  exercised by Waves 0–2 and the committed baseline.
- `.mlxlm/` is `.gitignore`d; this evidence directory follows the
  established pattern of force-adding wave evidence.
