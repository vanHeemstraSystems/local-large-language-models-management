#!/usr/bin/env bash
# scripts/route-log.sh — Minimal local-only routing telemetry (memo 12 §6, memo 16 §14).
#
# Appends one JSON line per task to .mlxlm/routing/decisions.jsonl so local-vs-cloud
# escalation outcomes become measurable before any automated router is considered.
# No network calls, no provider lookups, no Jev.
#
# Subcommands:
#   add       Append one decision record.
#   summary   Print per-model success/timeout/escalation counts from the log.
#
# `add` flags:
#   --category <str>        Task category (free-form, e.g. small-edit | multi-file).
#   --model <str>           Selected model (e.g. qwen3-8b-4bit | kimi-code).
#   --outcome <str>         One of: completed | timeout | tool_failure |
#                           tests_failed | context_overflow.
#   --escalated             Mark this task as escalated (default: false).
#   --escalated-to <str>    Target model used after escalation (requires --escalated).
#   --duration <int>        Elapsed seconds for the task (integer, optional).
#   --notes <str>           Free-form note (optional).
#   --file <path>           Override log path (default: .mlxlm/routing/decisions.jsonl).
#
# `summary` flags:
#   --file <path>           Override log path (default: .mlxlm/routing/decisions.jsonl).
#
# Exit codes:
#   0  success
#   2  usage / validation error
#
# Dependencies: Bash 3.2+, awk, sed. Uses `jq` only if already installed; otherwise
# both JSON emission and parsing degrade to plain printf/awk.
set -eu

DEFAULT_LOG=".mlxlm/routing/decisions.jsonl"

usage() {
    cat >&2 <<'EOF'
usage:
  route-log.sh add --category <c> --model <m> --outcome <o>
                   [--escalated] [--escalated-to <m>]
                   [--duration <s>] [--notes <text>] [--file <path>]
  route-log.sh summary [--file <path>]

outcome ∈ { completed | timeout | tool_failure | tests_failed | context_overflow }
EOF
}

have_jq() { command -v jq >/dev/null 2>&1; }

# Escape a string for safe embedding inside a JSON double-quoted value without jq.
# Handles: backslash, double quote, newline, carriage return, tab. Other control
# characters are stripped to keep the output valid JSON on Bash 3.2.
json_escape() {
    printf '%s' "$1" | awk '
        BEGIN { ORS = "" }
        {
            if (NR > 1) printf "\\n"
            s = $0
            gsub(/\\/, "\\\\", s)
            gsub(/"/,  "\\\"", s)
            gsub(/\t/, "\\t",  s)
            gsub(/\r/, "\\r",  s)
            # strip remaining control chars (0x00–0x1F) other than those handled above
            gsub(/[\000-\010\013\014\016-\037]/, "", s)
            printf "%s", s
        }
    '
}

validate_outcome() {
    case "$1" in
        completed|timeout|tool_failure|tests_failed|context_overflow) return 0 ;;
        *) printf 'route-log.sh: invalid --outcome: %s\n' "$1" >&2; return 1 ;;
    esac
}

cmd_add() {
    category=""; model=""; outcome=""; escalated="false"; escalated_to=""
    duration=""; notes=""; log_path="$DEFAULT_LOG"

    while [ $# -gt 0 ]; do
        case "$1" in
            --category)      category="${2:-}";      shift 2 ;;
            --model)         model="${2:-}";         shift 2 ;;
            --outcome)       outcome="${2:-}";       shift 2 ;;
            --escalated)     escalated="true";       shift ;;
            --escalated-to) escalated_to="${2:-}";  shift 2 ;;
            --duration)      duration="${2:-}";      shift 2 ;;
            --notes)         notes="${2:-}";         shift 2 ;;
            --file)          log_path="${2:-}";      shift 2 ;;
            -h|--help)       usage; return 0 ;;
            *) printf 'route-log.sh: unknown flag: %s\n' "$1" >&2; usage; return 2 ;;
        esac
    done

    [ -n "$category" ] || { printf 'route-log.sh: --category is required\n' >&2; return 2; }
    [ -n "$model" ]    || { printf 'route-log.sh: --model is required\n' >&2;    return 2; }
    [ -n "$outcome" ]  || { printf 'route-log.sh: --outcome is required\n' >&2;  return 2; }
    validate_outcome "$outcome" || return 2

    if [ -n "$duration" ]; then
        case "$duration" in
            ''|*[!0-9]*) printf 'route-log.sh: --duration must be a non-negative integer\n' >&2; return 2 ;;
        esac
    fi

    if [ "$escalated" = "false" ] && [ -n "$escalated_to" ]; then
        printf 'route-log.sh: --escalated-to requires --escalated\n' >&2
        return 2
    fi

    ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    log_dir="$(dirname -- "$log_path")"
    mkdir -p -- "$log_dir"

    if have_jq; then
        dur_json="null"
        [ -n "$duration" ] && dur_json="$duration"
        jq -cn \
            --arg ts "$ts" \
            --arg cat "$category" \
            --arg mdl "$model" \
            --arg out "$outcome" \
            --argjson esc "$escalated" \
            --arg escto "$escalated_to" \
            --argjson dur "$dur_json" \
            --arg notes "$notes" \
            '{timestamp:$ts, task_category:$cat, selected_model:$mdl, outcome:$out,
              escalated:$esc, escalated_to:(if $escto=="" then null else $escto end),
              duration_s:$dur, notes:(if $notes=="" then null else $notes end)}' \
            >>"$log_path"
    else
        e_cat="$(json_escape "$category")"
        e_mdl="$(json_escape "$model")"
        e_out="$(json_escape "$outcome")"
        if [ -n "$escalated_to" ]; then
            e_escto="\"$(json_escape "$escalated_to")\""
        else
            e_escto="null"
        fi
        if [ -n "$duration" ]; then
            dur_json="$duration"
        else
            dur_json="null"
        fi
        if [ -n "$notes" ]; then
            e_notes="\"$(json_escape "$notes")\""
        else
            e_notes="null"
        fi
        printf '{"timestamp":"%s","task_category":"%s","selected_model":"%s","outcome":"%s","escalated":%s,"escalated_to":%s,"duration_s":%s,"notes":%s}\n' \
            "$ts" "$e_cat" "$e_mdl" "$e_out" "$escalated" "$e_escto" "$dur_json" "$e_notes" \
            >>"$log_path"
    fi

    printf 'route-log.sh: appended record to %s\n' "$log_path" >&2
}

cmd_summary() {
    log_path="$DEFAULT_LOG"
    while [ $# -gt 0 ]; do
        case "$1" in
            --file)    log_path="${2:-}"; shift 2 ;;
            -h|--help) usage; return 0 ;;
            *) printf 'route-log.sh: unknown flag: %s\n' "$1" >&2; usage; return 2 ;;
        esac
    done

    if [ ! -s "$log_path" ]; then
        printf 'route-log.sh: no records at %s\n' "$log_path" >&2
        return 0
    fi

    if have_jq; then
        total="$(wc -l <"$log_path" | awk '{print $1}')"
        printf 'routing telemetry — %s (%s records)\n' "$log_path" "$total"
        printf '\nper selected_model × outcome:\n'
        jq -r '[.selected_model, .outcome] | @tsv' "$log_path" \
            | sort | uniq -c | awk '{printf "  %-6s %-32s %s\n", $1, $2, $3}'
        printf '\nescalation counts:\n'
        jq -r '"\(.selected_model)\t\(.escalated)\t\(.escalated_to // "-")"' "$log_path" \
            | sort | uniq -c \
            | awk '{printf "  %-6s model=%-24s escalated=%-5s to=%s\n", $1, $2, $3, $4}'
        return 0
    fi

    # jq-less fallback: naive key extraction with awk/sed. Assumes values do not
    # contain unescaped quotes (json_escape above enforces this).
    total="$(wc -l <"$log_path" | awk '{print $1}')"
    printf 'routing telemetry — %s (%s records)\n' "$log_path" "$total"
    printf '\nper selected_model × outcome:\n'
    awk '
        {
            m=""; o=""
            if (match($0, /"selected_model":"[^"]*"/))  { m=substr($0, RSTART+18, RLENGTH-19) }
            if (match($0, /"outcome":"[^"]*"/))         { o=substr($0, RSTART+11, RLENGTH-12) }
            if (m != "" && o != "") printf "%s\t%s\n", m, o
        }
    ' "$log_path" | sort | uniq -c | awk '{printf "  %-6s %-32s %s\n", $1, $2, $3}'
    printf '\nescalation counts:\n'
    awk '
        {
            m=""; e="false"; t="-"
            if (match($0, /"selected_model":"[^"]*"/))  { m=substr($0, RSTART+18, RLENGTH-19) }
            if (match($0, /"escalated":true/))          { e="true" }
            if (match($0, /"escalated_to":"[^"]*"/))    { t=substr($0, RSTART+16, RLENGTH-17) }
            if (m != "") printf "%s\t%s\t%s\n", m, e, t
        }
    ' "$log_path" | sort | uniq -c \
      | awk '{printf "  %-6s model=%-24s escalated=%-5s to=%s\n", $1, $2, $3, $4}'
}

[ $# -ge 1 ] || { usage; exit 2; }
sub="$1"; shift
case "$sub" in
    add)     cmd_add "$@" ;;
    summary) cmd_summary "$@" ;;
    -h|--help) usage ;;
    *) printf 'route-log.sh: unknown subcommand: %s\n' "$sub" >&2; usage; exit 2 ;;
esac
