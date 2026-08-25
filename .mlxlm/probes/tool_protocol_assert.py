#!/usr/bin/env python3
"""Assert the memo6 §7 tool-call contract against a captured response.

Usage:
  tool_protocol_assert.py nonstream <response.json>  <expected_fn_name>
  tool_protocol_assert.py stream    <response.sse>   <expected_fn_name>

Exit 0 on all pass; non-zero with a single-line FAIL: message on any failure.
"""
from __future__ import annotations
import json
import re
import sys
from collections import defaultdict


def die(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(2)


def ok(msg: str) -> None:
    print(f"PASS: {msg}")


def check_call_shape(call: dict, expected_name: str, where: str) -> None:
    # (1) call exists (implicit — we got here)
    # (2) id exists and non-null
    if "id" not in call:
        die(f"[{where}] tool_call missing 'id' key: {call!r}")
    if call["id"] is None or call["id"] == "":
        die(f"[{where}] tool_call id is null/empty: {call!r}")
    if not isinstance(call["id"], str):
        die(f"[{where}] tool_call id not a string: {type(call['id']).__name__}={call['id']!r}")
    ok(f"[{where}] id present and non-null: {call['id']}")

    # (3) type == "function"
    if call.get("type") != "function":
        die(f"[{where}] tool_call type != 'function': {call.get('type')!r}")
    ok(f"[{where}] type == 'function'")

    # (4) function.name correct
    fn = call.get("function") or {}
    name = fn.get("name")
    if name != expected_name:
        die(f"[{where}] function.name != {expected_name!r}, got {name!r}")
    ok(f"[{where}] function.name == {expected_name!r}")

    # (5) arguments is a valid JSON string parseable to an object
    args_raw = fn.get("arguments")
    if not isinstance(args_raw, str):
        die(f"[{where}] function.arguments not a string: {type(args_raw).__name__}")
    try:
        parsed = json.loads(args_raw)
    except Exception as e:
        die(f"[{where}] function.arguments not valid JSON: {e}; raw={args_raw!r}")
    if not isinstance(parsed, (dict, list, str, int, float, bool)) and parsed is not None:
        die(f"[{where}] arguments JSON has unexpected type: {type(parsed).__name__}")
    ok(f"[{where}] arguments valid JSON: {parsed!r}")


def run_nonstream(path: str, expected: str) -> None:
    with open(path) as f:
        data = json.load(f)
    choices = data.get("choices") or []
    if not choices:
        die("no choices in non-stream response")
    msg = choices[0].get("message") or {}
    calls = msg.get("tool_calls") or []
    if not calls:
        die(f"no tool_calls in non-stream response; finish_reason="
            f"{choices[0].get('finish_reason')!r}; content={msg.get('content')!r}")
    ok(f"[nonstream] tool_calls detected: count={len(calls)}")
    for i, c in enumerate(calls):
        check_call_shape(c, expected, f"nonstream.call[{i}]")


def parse_sse(path: str) -> list[dict]:
    events: list[dict] = []
    with open(path) as f:
        for raw in f:
            line = raw.rstrip("\r\n")
            if not line.startswith("data:"):
                continue
            payload = line[len("data:"):].strip()
            if payload == "" or payload == "[DONE]":
                continue
            try:
                events.append(json.loads(payload))
            except Exception as e:
                die(f"malformed SSE data line: {e}; raw={payload[:200]!r}")
    return events


def run_stream(path: str, expected: str) -> None:
    events = parse_sse(path)
    if not events:
        die("no SSE data events parsed")
    ok(f"[stream] parsed {len(events)} SSE events")

    # Reconstruct per-index tool calls. Track every non-null id observed
    # for each index to prove (7) stability across all deltas.
    reconstructed: dict[int, dict] = {}
    ids_by_index: dict[int, set[str]] = defaultdict(set)
    saw_tool_call_delta = False
    finish_reason = None

    for ev in events:
        for ch in ev.get("choices") or []:
            fr = ch.get("finish_reason")
            if fr:
                finish_reason = fr
            delta = ch.get("delta") or ch.get("message") or {}
            tcs = delta.get("tool_calls") or []
            for tc in tcs:
                saw_tool_call_delta = True
                idx = tc.get("index", 0)
                slot = reconstructed.setdefault(idx, {
                    "id": None, "type": None,
                    "function": {"name": None, "arguments": ""},
                })
                if tc.get("id") is not None:
                    ids_by_index[idx].add(tc["id"])
                    if slot["id"] is None:
                        slot["id"] = tc["id"]
                if tc.get("type") is not None:
                    slot["type"] = tc["type"]
                fn = tc.get("function") or {}
                if fn.get("name") is not None:
                    slot["function"]["name"] = fn["name"]
                if fn.get("arguments") is not None:
                    slot["function"]["arguments"] += fn["arguments"]

    if not saw_tool_call_delta:
        die(f"no tool_call deltas in stream; finish_reason={finish_reason!r}")
    ok(f"[stream] tool_call deltas observed across {len(reconstructed)} logical call(s); "
       f"finish_reason={finish_reason!r}")

    for idx, call in sorted(reconstructed.items()):
        # (7) id stable across all deltas of one logical call
        seen = ids_by_index[idx]
        if len(seen) == 0:
            die(f"[stream.call[{idx}]] no id observed in any delta")
        if len(seen) > 1:
            die(f"[stream.call[{idx}]] id NOT stable across deltas: {sorted(seen)!r}")
        ok(f"[stream.call[{idx}]] id stable across deltas: {next(iter(seen))!r}")
        # (6) reconstruction coherent: check the assembled call
        check_call_shape(call, expected, f"stream.call[{idx}]")


def main() -> None:
    if len(sys.argv) != 4 or sys.argv[1] not in {"nonstream", "stream"}:
        print(__doc__ or "", file=sys.stderr)
        sys.exit(64)
    mode, path, expected = sys.argv[1], sys.argv[2], sys.argv[3]
    if mode == "nonstream":
        run_nonstream(path, expected)
    else:
        run_stream(path, expected)


if __name__ == "__main__":
    main()
