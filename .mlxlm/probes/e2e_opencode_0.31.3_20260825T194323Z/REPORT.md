# End-to-end OpenCode → mlx-lm 0.31.3 → Qwen3-8B-4bit

**Run:** 2026-08-25T19:43Z (UTC)
**Stack:** Homebrew Python 3.12.13 + mlx-lm 0.31.3 (no A.1 patch), mlx_lm.server on 127.0.0.1:8080
**Client:** opencode CLI (Homebrew), non-interactive `opencode run`
**Task note:** a92bef68-d8b7-4049-ae63-2566140c237d

## Invocation

```
opencode run --auto --pure \
  -m "mlxlm//Users/willemvanheemstra/.mlx-serve/models/mlx-community/Qwen3-8B-4bit" \
  "Read the file .mlxlm/PATCHES.md and quote the exact status line that says the A.1 patch is retired. Use your file-reading tool; do not guess."
```

`--pure` disables external plugins (no `augment-context-engine` MCP), keeping the round trip a pure OpenCode ↔ mlx-lm exchange. `--auto` auto-approves the Read tool. Model selected explicitly on the CLI (`-m …/Qwen3-8B-4bit`) so the session hits the Qwen3-8B-4bit head named in the task, not the workspace default that resolves to gpt-oss.

## Result

- **Exit code:** 0
- **Elapsed:** 59 s
- **Tool call observed (stderr):** `→ Read .mlxlm/PATCHES.md [offset=0, limit=2000]`
- **Model final answer (stdout, verbatim):**

  > `"RETIRED" in the title line of the A.1 patch section (line 3) is the exact status line indicating the patch is retired.`

- **HTTP round trips (server log delta):** two `POST /v1/chat/completions … 200 -`
  1. 21:43:43 — initial prompt, 8358 prompt tokens, produces a `tool_calls[]` response
  2. 21:44:21 — continuation with tool result appended, 1193 prompt tokens, produces the final assistant message
- **Server-side errors:** none (`grep -nE "UnknownError|BatchRotatingKVCache|Traceback|IOGPU|abort|ERROR"` on the delta → NO_PROBLEM_MARKERS)
- **RSS during session:** min 2 534 272 kB, max 5 112 448 kB (≈4.9 GiB), last 4 348 096 kB — far below the 18 GB safety cap
- **Prompt cache at end:** 1 sequence, 1.28 GB (assistant), consistent with a completed streamed generation

## PATCHES.md ground truth (for validation point c)

`.mlxlm/PATCHES.md` line 3:

```
## A.1 — tool_calls[].id null → OpenAI-spec-compliant string (RETIRED)
```

`.mlxlm/PATCHES.md` line 5 (the explicit status paragraph):

```
**Status:** Retired as of mlx-lm **0.31.3** (2026-08-25). …
```

The model's answer names line 3 correctly and puts the marker word `RETIRED` in quotes, which is the substring that actually appears in the file at that location — evidence that the tool result reached the model. The response does not paste the whole line verbatim; it identifies it.

## Validation checklist

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| a | Session completed without UnknownError / abort | **PASS** | `exit_code=0`, both POSTs 200, no error markers in delta |
| b | ≥1 tool call executed and its result consumed | **PASS** | `Read .mlxlm/PATCHES.md` visible in stderr; second POST carries a 1193-token continuation (system + prior turn + tool result), followed by a coherent final answer |
| c | Final answer quotes the retired-status line | **PARTIAL PASS** | Model quotes the marker word `"RETIRED"` from line 3 and identifies the line; it does not reproduce the full line verbatim. The tool result plainly reached the model (line index and marker are both correct), so the round-trip semantics are proven, but the response formatting is weaker than the prompt asked for. |
| d | No BatchRotatingKVCache / traceback / IOGPU errors in log delta | **PASS** | `grep` on the 20-line delta returns NO_PROBLEM_MARKERS |
| e | RSS well below the 18 GB cap | **PASS** | Max 5 112 448 kB ≈ 4.9 GiB, ≈27% of cap |

## Overall verdict

**PASS — the end-to-end loop works on the upgraded 0.31.3 stack.**

The upgraded, unpatched Python 3.12 / mlx-lm 0.31.3 / Qwen3-8B-4bit stack completed a real OpenCode agent turn with a tool round-trip: OpenCode issued a `Read` tool call, mlx-lm returned a spec-compliant `tool_calls[]` (no `UnknownError` from ai-sdk), OpenCode fed the tool result back, and the model produced a `finish_reason=stop` final message that references the correct file content. Validation point (c) is a soft partial on answer quality only (the model identified rather than pasted the line); it is not a stack-level failure.

## Files in this probe

- `00_preflight.txt` — pip show mlx-lm, serve.sh status, baseline log line count
- `01_invocation.txt` — exact command and CWD
- `02_transcript.out` / `02_transcript.err` — opencode stdout / stderr
- `03_exitcode.txt` — exit code + elapsed
- `04_server_log_delta.log` — server log lines added during the session
- `05_server_stop.txt` — stop confirmation
- `06_rss_summary.txt` — min/max/last RSS in kB
- `rss_samples.txt` — 2 s cadence RSS samples during the session
- `REPORT.md` — this file
