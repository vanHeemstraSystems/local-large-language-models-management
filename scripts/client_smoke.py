#!/usr/bin/env python3
"""Repeatable OpenAI-compatible client smoke test for MLXServe.

Talks to MLXServe's `/v1/chat/completions` endpoint using only Python
stdlib (urllib + json). Two modes:

    non-streaming (default):
        POST /v1/chat/completions -> parse response body -> validate the
        OpenAI Chat Completions contract (choices[0].message.content,
        finish_reason, usage.{prompt,completion,total}_tokens).

    streaming (--stream):
        POST /v1/chat/completions with stream=true -> parse the SSE
        `data:` frames -> reassemble deltas -> validate that the stream
        terminated with the [DONE] sentinel and produced non-empty
        content.

Exit code 0 iff the contract validated. Any HTTP error, JSON error, or
missing required field exits non-zero with a short diagnostic on stderr.

Environment:
    MLXSERVE_HOST                (default 127.0.0.1)
    MLXSERVE_PORT                (default 11234)
    MLXSERVE_PRIMARY_MODEL       (default mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit)
    MLXSERVE_CLIENT_PROMPT       (default: a short Python coding prompt)
    MLXSERVE_CLIENT_MAX_TOKENS   (default 128)
    MLXSERVE_CLIENT_TIMEOUT      (default 120 seconds)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

DEFAULT_PROMPT = (
    "Write a Python one-liner that returns the sum of squares from 1 to n."
)


def endpoint() -> str:
    host = os.environ.get("MLXSERVE_HOST", "127.0.0.1")
    port = os.environ.get("MLXSERVE_PORT", "11234")
    return f"http://{host}:{port}/v1/chat/completions"


def build_body(stream: bool) -> dict:
    return {
        "model": os.environ.get(
            "MLXSERVE_PRIMARY_MODEL",
            "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit",
        ),
        "max_tokens": int(os.environ.get("MLXSERVE_CLIENT_MAX_TOKENS", "128")),
        "temperature": 0,
        "stream": stream,
        "messages": [
            {"role": "system", "content": "You are a concise coding assistant."},
            {"role": "user", "content": os.environ.get(
                "MLXSERVE_CLIENT_PROMPT", DEFAULT_PROMPT
            )},
        ],
    }


def _request(body: dict) -> urllib.request.Request:
    data = json.dumps(body).encode("utf-8")
    return urllib.request.Request(
        endpoint(),
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )


def run_non_streaming() -> int:
    body = build_body(stream=False)
    timeout = float(os.environ.get("MLXSERVE_CLIENT_TIMEOUT", "120"))
    t0 = time.time()
    with urllib.request.urlopen(_request(body), timeout=timeout) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    elapsed = time.time() - t0

    choices = payload.get("choices") or []
    if not choices:
        print("FAIL: response has no choices[]", file=sys.stderr)
        return 1
    msg = (choices[0].get("message") or {}).get("content")
    if not msg:
        print("FAIL: choices[0].message.content is empty", file=sys.stderr)
        return 1
    finish = choices[0].get("finish_reason")
    if finish != "stop":
        print(f"FAIL: finish_reason={finish!r} (expected 'stop')", file=sys.stderr)
        return 1
    usage = payload.get("usage") or {}
    for key in ("prompt_tokens", "completion_tokens", "total_tokens"):
        if key not in usage:
            print(f"FAIL: usage.{key} missing", file=sys.stderr)
            return 1

    print(f"OK non-streaming  model={payload.get('model')} "
          f"prompt={usage['prompt_tokens']} completion={usage['completion_tokens']} "
          f"total={usage['total_tokens']} elapsed={elapsed:.2f}s "
          f"finish={finish}")
    print(f"--- content ---\n{msg.strip()}\n--- end ---")
    return 0


def run_streaming() -> int:
    body = build_body(stream=True)
    timeout = float(os.environ.get("MLXSERVE_CLIENT_TIMEOUT", "120"))
    chunks: list[str] = []
    saw_done = False
    frames = 0
    t0 = time.time()
    with urllib.request.urlopen(_request(body), timeout=timeout) as resp:
        for raw in resp:
            line = raw.decode("utf-8").rstrip("\n")
            if not line.startswith("data:"):
                continue
            payload = line[len("data:"):].strip()
            if payload == "[DONE]":
                saw_done = True
                break
            frames += 1
            try:
                obj = json.loads(payload)
            except json.JSONDecodeError:
                print(f"FAIL: non-JSON SSE frame: {payload[:80]!r}", file=sys.stderr)
                return 1
            delta = ((obj.get("choices") or [{}])[0].get("delta") or {}).get("content")
            if delta:
                chunks.append(delta)
    elapsed = time.time() - t0

    if not saw_done:
        print("FAIL: SSE stream ended without [DONE] sentinel", file=sys.stderr)
        return 1
    content = "".join(chunks).strip()
    if not content:
        print("FAIL: streamed content is empty", file=sys.stderr)
        return 1
    print(f"OK streaming      frames={frames} chars={len(content)} "
          f"elapsed={elapsed:.2f}s")
    print(f"--- content ---\n{content}\n--- end ---")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="MLXServe OpenAI-compat client smoke.")
    ap.add_argument("--stream", action="store_true", help="Use SSE streaming mode.")
    args = ap.parse_args(argv)
    try:
        return run_streaming() if args.stream else run_non_streaming()
    except urllib.error.HTTPError as e:
        print(f"FAIL: HTTP {e.code} {e.reason}: {e.read().decode('utf-8', 'replace')[:200]}",
              file=sys.stderr)
        return 1
    except urllib.error.URLError as e:
        print(f"FAIL: URL error: {e.reason}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
