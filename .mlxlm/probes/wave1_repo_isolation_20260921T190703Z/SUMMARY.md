# Wave 1 — Repository-context isolation: evidence & verdict

Captured: 2026-09-21T19:07:03Z
Directory: `.mlxlm/probes/wave1_repo_isolation_20260921T190703Z/`

Read-only investigation, per task instructions. No production runtime
file was modified (`opencode.json`, `.mlxlm/serve.sh`, `.mlxlm/health.sh`,
model selection, model weights all untouched). MLXServe was not started
for this wave — all probes are `opencode debug ...` and shell/filesystem
inspection.

## Definition-of-Done status

| DoD item | Status | Evidence |
|---|---|---|
| Starting OpenCode from one git root does NOT enumerate sibling workspaces | ✅ Verified | `fixture_probes.txt` P0a / P0c / P0e (`Path escapes the location`) |
| Targeted retrieval works inside a repo | ✅ Verified | `fixture_probes.txt` P0a (`rg files` returns only repo files) |
| Starting from `~/intent/workspaces/` is clearly rejected or warned | ⚠️ Partial | See "Guard proposal" — a hard `.opencodeignore` guard **does not work**; operator discipline (per-repo `cd`) is the only proven mechanism today |
| Single-repository workflow remains functional | ✅ Verified | Local `opencode.json` unchanged; per-repo config confirmed across all sibling workspaces |
| Parent-level `.opencodeignore` behavior proven before production adoption | ✅ Verified NEGATIVE | `fixture_probes.txt` P1 / P1b — proposal REJECTED (see below) |

## Key findings

### 1. `opencode` file-walk behavior is **cwd-scoped, not ignore-scoped**

`opencode debug rg files` invokes ripgrep in a way that **ignores every
standard ignore file**: `.gitignore`, `.ignore`, `.rgignore`, and the
proposed `.opencodeignore` are all no-ops, whether placed at the parent
of a set of repos or inside a repo itself. Full matrix in
`fixture_probes.txt` (probes P1–P9):

| Ignore file location | File contents | Effect on `opencode debug rg files` |
|---|---|---|
| `parent/.opencodeignore` | `*` | **none** (all sibling repo files still listed) |
| `parent/.ignore` | `*` | **none** |
| `parent/.gitignore` (no parent `.git`) | `*` | **none** |
| `parent/.gitignore` + parent `.git` | `*` | **none** |
| `parent/.rgignore` | `*` | **none** |
| `repoA/.gitignore` | `src/` | **none** — `src/a.py` still listed |
| `repoA/.ignore` | `src/` | **none** |
| `repoA/.opencodeignore` | `src/` | **none** |
| `repoA/.rgignore` | `src/` | **none** |

Interpretation: opencode's ripgrep integration is invoked with something
equivalent to `--no-ignore` (and `--hidden`). Ignore-file-based scoping
is not a lever we have.

### 2. What DOES scope opencode

Two mechanisms are proven effective (probes P0a / P0c / P0d / P0e):

- **`cwd` bounds `debug rg files` and `rg search`.** Started from
  `repoA/`, ripgrep walks only `repoA/`. Sibling `repoB/` files are
  invisible. This is the trivially-effective isolation lever.
- **`debug file list` / `file read` enforce a "location" boundary.**
  Attempting to `file list ../repoB` (or an absolute path to a sibling)
  from `repoA/` returns `Path escapes the location`. Inside the location
  it works normally. This confirms an internal escape check.

Together these mean: **as long as opencode is launched from a per-repo
git root, cross-repo enumeration cannot occur via opencode's own tools.**

### 3. Cross-workspace inventory

- 47 workspaces under `~/intent/workspaces/`; 43 of them carry an
  `opencode.json` at the correct repo-root depth
  (`workspace/repo/opencode.json`), all byte-identical (md5
  `60a5e0e2c74bee8f92df53690a69d436`, 1386 B) except
  `fancy-alpaca/source` (1486 B, differs) and
  `worldwide-salamander/source` (151 B, a stub). Full listing in
  `inventory_current_state.txt`.
- **Hazard: `~/intent/workspaces/opencode.json` (parent-level) exists**
  and is byte-identical to this repo's config (same md5, 1386 B). If
  opencode is ever launched from `~/intent/workspaces/` the parent
  `opencode.json` **will** be resolved as config (opencode walks
  cwd-upward looking for `opencode.json`), and since the parent is not
  a git root, ripgrep-based tools would then enumerate every sibling
  repo (finding P0b: sibling files listed unconditionally).
- No `.opencodeignore` file exists anywhere under `~/intent/workspaces/`
  today — consistent with Wave 0.
- `opencode debug scrap` shows 5 previously-indexed projects under
  `~/intent/workspaces/`, all git roots at the correct depth. The parent
  directory has never been registered as a project (`opencode_scrap.txt`
  → "Parent workspaces/ directory ever registered as project: NO").
  Operator discipline has held historically.

### 4. `auggie --mcp --mcp-auto-workspace` scoping

Wave 0 already established that `--mcp-auto-workspace` makes the
`codebase-retrieval` MCP tool require a `directory_path` argument per
call, i.e. the workspace decision is delegated to the MCP client
(opencode). Combined with §2, this means auggie inherits opencode's
git-root scoping automatically — no additional configuration needed.
`auggie_workspace_scoping.txt` records the flag help verbatim.

## Verdict on the ADVISE_x5f_REFACTOR_x5f_V2.md proposal

ADVISE_x5f_REFACTOR_x5f_V2.md §3.1 step 2 proposes:

```
Create ~/intent/workspaces/.opencodeignore:
*
```

**REJECTED as ineffective.** Proven by probe P1 in
`fixture_probes.txt`: with a parent-level `.opencodeignore` containing
`*`, opencode's file walk still enumerates every sibling repo. The
underlying reason is that opencode invokes ripgrep with ignore-file
processing disabled. Do **not** create this file — it would be
misleading (looks like protection, provides none).

The `.mlxlm/health.sh` snippet in the same ADVISE section is a plausible
guard but out of scope for this task (health.sh must remain untouched
per user instructions). See "Guard proposal" below.

## Guard proposal (documentation-only, captured for coordinator decision)

Since ignore-file-based defense is not available, the only reliable
mitigation is **operator discipline enforced by a preflight check**.
Two candidate snippets are captured here for the coordinator to review
before any production edit is proposed. Neither is applied in this
wave.

Bash-3 compatible (works with macOS default `/bin/bash` 3.2.57):

```sh
# Refuse to run opencode from the ~/intent/workspaces/ parent directory.
case "$PWD" in
  "$HOME/intent/workspaces"|"$HOME/intent/workspaces/")
    echo "ERROR: cwd is the workspaces parent; cd into a specific repo first." >&2
    exit 1
    ;;
esac
if [ ! -d "$PWD/.git" ] && [ ! -f "$PWD/.git" ]; then
  echo "WARN: cwd is not a git root; opencode's file scope may exceed one repo." >&2
fi
```

- Placement candidates (NOT applied): a new operator preflight snippet
  in `QUICKSTART.md`, or a wrapper script in `scripts/` that users
  invoke instead of `opencode` directly. Modifying
  `.mlxlm/health.sh`, `.mlxlm/serve.sh`, or `opencode.json` is
  explicitly forbidden by the task instructions.
- The parent-level `~/intent/workspaces/opencode.json` (identical to
  this repo's) is also a candidate for removal to eliminate the config
  vector for parent-directory launches; that file lives outside this
  repo's git worktree and remediation is out of scope for this task —
  reported so the coordinator can decide.

## Rollback

Nothing to roll back. This wave modified only files under
`.mlxlm/probes/wave1_repo_isolation_20260921T190703Z/`. The disposable
fixture at `/tmp/wave1_fixture_66069/` can be removed with
`rm -rf /tmp/wave1_fixture_66069`. Wave-0 rollback snapshots
(`.mlxlm/probes/wave0_baseline_20260921T185423Z/runtime_snapshots/`)
remain the authoritative rollback for `opencode.json`, `serve.sh`,
`health.sh`.

## Evidence files

- `environment.txt` — versions of opencode / auggie / python / bash /
  kernel at capture time.
- `inventory_current_state.txt` — every `opencode.json` under
  `~/intent/workspaces/` (md5 + size + path), parent-file hazard note,
  `.opencodeignore` and `.git` inventory.
- `opencode_scrap.txt` — full list of projects opencode has ever
  registered, with confirmation that the parent has never been
  registered.
- `fixture_probes.txt` — 15 probes against the disposable fixture at
  `/tmp/wave1_fixture_66069/`, covering baseline behavior, all four
  ignore-file variants at parent, all four ignore-file variants inside
  a repo, and location-escape checks.
- `auggie_workspace_scoping.txt` — auggie `--help` excerpt confirming
  `--mcp-auto-workspace` delegates workspace scope to the MCP client.
