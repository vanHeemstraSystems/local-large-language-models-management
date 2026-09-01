#!/usr/bin/env bash
# scripts/memo-sweep.sh — scan open-engineering-* workspaces for pending memos
# and ship completed ones. Deterministic scaffold; NO LLM calls.
#
# Bash 3.2 compatible (macOS default). Uses git + gh (+ jq for --json).
#
# Subcommands:
#   scan [--json] [--ff-only]   Enumerate ~/intent/workspaces/*/ for repos whose
#                               origin belongs to org open-engineering-*.
#                               Report branch state and root-level memo*.md
#                               files (excluding archive/). Never modifies repos
#                               except when --ff-only is passed AND the working
#                               tree is clean AND the current branch tracks the
#                               remote default branch.
#   ship <repo-path> <memo>     Move <memo> (a memo*.md at repo root) into
#                               archive/, commit "docs: archive <memo>
#                               (implemented)", push, and (if not on default
#                               branch) open a PR titled the same and squash-
#                               merge it. Refuses if the working tree has
#                               changes unrelated to <memo>, or if gh is not
#                               authenticated.
#   help | -h | --help          Show this help.
#
# Non-goals:
#   - Does NOT implement memo content (that stays with agents / humans).
#   - Does NOT touch repos outside org open-engineering-*.
#   - `scan` never modifies repos except optional fast-forward under --ff-only.

set -euo pipefail

WORKSPACES_ROOT="${MEMO_SWEEP_WORKSPACES:-$HOME/intent/workspaces}"
ORG_PREFIX="open-engineering-"

# ---------- helpers ----------

log()  { printf '%s\n' "$*" >&2; }
die()  { printf 'memo-sweep: %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
}

# json_escape <string>  -> emits a JSON-safe string (without surrounding quotes)
json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# parse_org_repo <origin-url>  -> prints "org<TAB>repo" or empty string
parse_org_repo() {
    local url=$1
    local stripped=${url%.git}
    local path=""
    case "$stripped" in
        git@github.com:*)         path=${stripped#git@github.com:} ;;
        ssh://git@github.com/*)   path=${stripped#ssh://git@github.com/} ;;
        https://github.com/*)     path=${stripped#https://github.com/} ;;
        http://github.com/*)      path=${stripped#http://github.com/} ;;
        *) return 0 ;;
    esac
    local org=${path%%/*}
    local repo=${path#*/}
    [ -n "$org" ] && [ -n "$repo" ] && [ "$org" != "$path" ] && printf '%s\t%s' "$org" "$repo"
}

# is_git_repo <dir>
is_git_repo() {
    git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

# default_branch_of_origin <repo-dir>  -> prints e.g. "main"
default_branch_of_origin() {
    local d=$1 ref
    ref=$(git -C "$d" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -n "$ref" ]; then
        printf '%s' "${ref##*/}"
        return
    fi
    # Fallback: ask remote directly (network call). Only used if symbolic-ref missing.
    ref=$(git -C "$d" ls-remote --symref origin HEAD 2>/dev/null | awk 'NR==1 && $1=="ref:" { sub("refs/heads/","",$2); print $2 }')
    printf '%s' "$ref"
}

# first_heading <file>  -> prints first `# ` heading or first non-empty line
first_heading() {
    local f=$1 line=""
    line=$(grep -m1 '^#' "$f" 2>/dev/null || true)
    if [ -z "$line" ]; then
        line=$(awk 'NF { print; exit }' "$f" 2>/dev/null || true)
    fi
    printf '%s' "$line"
}

# list_root_memos <repo-dir>  -> prints filenames (one per line), sorted, no path
list_root_memos() {
    local d=$1 f base
    for f in "$d"/memo*.md; do
        [ -e "$f" ] || continue
        base=${f##*/}
        printf '%s\n' "$base"
    done | LC_ALL=C sort
}

# candidate_repos <workspace-dir>  -> prints absolute paths of candidate repos
candidate_repos() {
    local ws=$1 sub
    if is_git_repo "$ws"; then
        printf '%s\n' "$ws"
    fi
    for sub in "$ws"/*/; do
        [ -d "$sub" ] || continue
        sub=${sub%/}
        if is_git_repo "$sub"; then
            printf '%s\n' "$sub"
        fi
    done
}

# working_tree_clean <repo-dir>
working_tree_clean() {
    [ -z "$(git -C "$1" status --porcelain 2>/dev/null)" ]
}


# ---------- scan ----------

# scan_repo <repo-dir> <workspace-name> <ff_only>
scan_repo() {
    local d=$1 ws_name=$2 ff_only=$3
    local origin org_repo="" org="" repo="" matched="false" skip_reason=""
    local default_branch="" current_branch="" behind=0 ahead=0 clean="true"
    local memos_json="[]"

    origin=$(git -C "$d" remote get-url origin 2>/dev/null || true)
    if [ -z "$origin" ]; then
        skip_reason="no-origin"
    else
        local parsed
        parsed=$(parse_org_repo "$origin")
        if [ -z "$parsed" ]; then
            skip_reason="unrecognized-remote"
            org_repo="$origin"
        else
            org=$(printf '%s' "$parsed" | cut -f1)
            repo=$(printf '%s' "$parsed" | cut -f2)
            org_repo="$org/$repo"
            case "$org" in
                ${ORG_PREFIX}*) matched="true" ;;
                *) skip_reason="org-not-open-engineering" ;;
            esac
        fi
    fi

    current_branch=$(git -C "$d" symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'DETACHED')
    working_tree_clean "$d" || clean="false"

    if [ "$matched" = "true" ]; then
        if ! git -C "$d" fetch --quiet origin 2>/dev/null; then
            log "  ! fetch failed for $d"
        fi
        default_branch=$(default_branch_of_origin "$d")
        if [ -n "$default_branch" ]; then
            behind=$(git -C "$d" rev-list --count "HEAD..origin/${default_branch}" 2>/dev/null || printf '0')
            ahead=$(git -C "$d" rev-list --count "origin/${default_branch}..HEAD" 2>/dev/null || printf '0')
        fi
        if [ "$ff_only" = "true" ] && [ "$clean" = "true" ] \
           && [ -n "$default_branch" ] && [ "$current_branch" = "$default_branch" ] \
           && [ "$behind" -gt 0 ] && [ "$ahead" = "0" ]; then
            if git -C "$d" merge --ff-only --quiet "origin/${default_branch}" 2>/dev/null; then
                log "  ✓ fast-forwarded $d to origin/${default_branch}"
                behind=0
            fi
        fi
    fi

    local memos_list memo heading
    memos_list=$(list_root_memos "$d")

    if [ "$JSON_MODE" = "true" ]; then
        local items="" first=1
        if [ -n "$memos_list" ]; then
            while IFS= read -r memo; do
                heading=$(first_heading "$d/$memo")
                if [ $first -eq 1 ]; then first=0; else items="${items},"; fi
                items="${items}{\"file\":\"$(json_escape "$memo")\",\"heading\":\"$(json_escape "$heading")\"}"
            done <<EOF
$memos_list
EOF
        fi
        memos_json="[${items}]"

        printf '{"workspace":"%s","path":"%s","origin":"%s","orgRepo":"%s","matched":%s,"skipReason":"%s","defaultBranch":"%s","currentBranch":"%s","behindDefault":%s,"aheadDefault":%s,"workingTreeClean":%s,"pendingMemos":%s}\n' \
            "$(json_escape "$ws_name")" \
            "$(json_escape "$d")" \
            "$(json_escape "${origin:-}")" \
            "$(json_escape "$org_repo")" \
            "$matched" \
            "$(json_escape "$skip_reason")" \
            "$(json_escape "$default_branch")" \
            "$(json_escape "$current_branch")" \
            "${behind:-0}" \
            "${ahead:-0}" \
            "$clean" \
            "$memos_json" \
            >> "$JSON_TMP"
    else
        if [ "$matched" = "true" ]; then
            printf '  ✓ %s\n' "$org_repo"
        else
            printf '  · %s  [skipped: %s]\n' "${org_repo:-$d}" "${skip_reason:-unknown}"
        fi
        printf '      path:     %s\n' "$d"
        printf '      branch:   %s' "$current_branch"
        if [ "$matched" = "true" ] && [ -n "$default_branch" ]; then
            printf '   (default=%s, behind=%s, ahead=%s' "$default_branch" "$behind" "$ahead"
            if [ "$clean" = "true" ]; then printf ', clean)'; else printf ', dirty)'; fi
        else
            [ "$clean" = "true" ] || printf '   (dirty)'
        fi
        printf '\n'
        if [ -z "$memos_list" ]; then
            printf '      memos:    (none)\n'
        else
            printf '      memos:\n'
            while IFS= read -r memo; do
                heading=$(first_heading "$d/$memo")
                printf '        - %s   %s\n' "$memo" "${heading:-(no heading)}"
            done <<EOF
$memos_list
EOF
        fi
    fi
}

cmd_scan() {
    local ff_only="false"
    JSON_MODE="false"
    while [ $# -gt 0 ]; do
        case "$1" in
            --json)     JSON_MODE="true" ;;
            --ff-only)  ff_only="true" ;;
            -h|--help)  usage; exit 0 ;;
            *)          die "unknown scan option: $1" ;;
        esac
        shift
    done

    [ -d "$WORKSPACES_ROOT" ] || die "workspaces root not found: $WORKSPACES_ROOT"

    if [ "$JSON_MODE" = "true" ]; then
        JSON_TMP=$(mktemp -t memo-sweep.XXXXXX)
        trap 'rm -f "$JSON_TMP"' EXIT
    else
        printf 'memo-sweep scan (root=%s, org=%s*)\n' "$WORKSPACES_ROOT" "$ORG_PREFIX"
    fi

    local ws ws_name repo had_candidate
    for ws in "$WORKSPACES_ROOT"/*/; do
        [ -d "$ws" ] || continue
        ws=${ws%/}
        ws_name=${ws##*/}
        [ "$JSON_MODE" = "true" ] || printf '\nworkspace: %s\n' "$ws_name"
        had_candidate="false"
        while IFS= read -r repo; do
            [ -n "$repo" ] || continue
            had_candidate="true"
            scan_repo "$repo" "$ws_name" "$ff_only"
        done < <(candidate_repos "$ws")
        if [ "$had_candidate" = "false" ] && [ "$JSON_MODE" != "true" ]; then
            printf '  (no git repos)\n'
        fi
    done

    if [ "$JSON_MODE" = "true" ]; then
        {
            printf '['
            local first=1 line
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                if [ $first -eq 1 ]; then first=0; else printf ','; fi
                printf '%s' "$line"
            done < "$JSON_TMP"
            printf ']\n'
        } | jq '{ repos: . }'
    fi
}

# ---------- ship ----------

cmd_ship() {
    local repo_path="" memo=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)  usage; exit 0 ;;
            --)         shift; break ;;
            -*)         die "unknown ship option: $1" ;;
            *)
                if [ -z "$repo_path" ]; then repo_path=$1
                elif [ -z "$memo" ]; then memo=$1
                else die "unexpected extra arg: $1"
                fi
                ;;
        esac
        shift
    done
    [ -n "$repo_path" ] || die "ship requires <repo-path>"
    [ -n "$memo" ]      || die "ship requires <memo-file>"

    # Normalize
    [ -d "$repo_path" ] || die "not a directory: $repo_path"
    is_git_repo "$repo_path" || die "not a git repo: $repo_path"
    case "$memo" in */*) die "memo must be a bare filename at repo root, not a path: $memo" ;; esac
    [ -f "$repo_path/$memo" ] || die "memo not found at repo root: $repo_path/$memo"

    # gh auth
    gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run 'gh auth login')"

    # Uncommitted-changes check (allow only lines referring to $memo)
    local unrelated
    unrelated=$(git -C "$repo_path" status --porcelain 2>/dev/null \
        | awk -v m="$memo" '{ p=substr($0,4); sub(/ -> .*$/,"",p); gsub(/^"|"$/,"",p); if (p != m && p != "archive/"m) print }')
    if [ -n "$unrelated" ]; then
        log "memo-sweep: refusing to ship — repo has unrelated uncommitted changes:"
        printf '%s\n' "$unrelated" >&2
        exit 1
    fi

    local current_branch default_branch origin_url org_repo="" parsed
    current_branch=$(git -C "$repo_path" symbolic-ref --quiet --short HEAD 2>/dev/null) \
        || die "cannot ship from detached HEAD"
    default_branch=$(default_branch_of_origin "$repo_path")
    [ -n "$default_branch" ] || die "cannot determine origin default branch"
    origin_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)
    parsed=$(parse_org_repo "$origin_url")
    if [ -n "$parsed" ]; then
        org_repo=$(printf '%s' "$parsed" | tr '\t' '/')
    fi

    log "memo-sweep: shipping $memo in ${org_repo:-$origin_url} (branch=$current_branch, default=$default_branch)"

    mkdir -p "$repo_path/archive"
    git -C "$repo_path" mv "$memo" "archive/$memo"
    git -C "$repo_path" commit -m "docs: archive ${memo} (implemented)" >/dev/null
    local sha
    sha=$(git -C "$repo_path" rev-parse HEAD)
    log "  commit: $sha"

    if [ "$current_branch" = "$default_branch" ]; then
        git -C "$repo_path" push origin "$current_branch"
        log "  pushed to origin/$current_branch (no PR needed)"
        printf 'shipped: repo=%s memo=%s commit=%s branch=%s pr=none\n' \
            "${org_repo:-$origin_url}" "$memo" "$sha" "$current_branch"
        return 0
    fi

    [ -n "$org_repo" ] || die "cannot parse GitHub org/repo from origin: $origin_url (needed to open PR)"
    git -C "$repo_path" push -u origin "$current_branch"

    local pr_title="docs: archive ${memo}"
    local pr_body="Automated by scripts/memo-sweep.sh: archiving ${memo} after implementation."
    local pr_url pr_number
    pr_url=$(gh -R "$org_repo" pr create \
        --title "$pr_title" --body "$pr_body" \
        --base "$default_branch" --head "$current_branch")
    pr_number=${pr_url##*/}
    log "  PR: $pr_url"

    gh -R "$org_repo" pr merge "$pr_number" --squash --delete-branch=false >/dev/null
    local state
    state=$(gh -R "$org_repo" pr view "$pr_number" --json state -q .state)
    log "  PR state: $state"
    [ "$state" = "MERGED" ] || die "PR $pr_number did not merge (state=$state)"

    printf 'shipped: repo=%s memo=%s commit=%s branch=%s pr=%s state=%s\n' \
        "$org_repo" "$memo" "$sha" "$current_branch" "$pr_url" "$state"
}

# ---------- dispatch ----------

main() {
    local sub=${1:-scan}
    case "$sub" in
        scan)          shift; cmd_scan "$@" ;;
        ship)          shift; cmd_ship "$@" ;;
        help|-h|--help) usage ;;
        --json|--ff-only) cmd_scan "$@" ;;
        *)             die "unknown subcommand: $sub (try 'help')" ;;
    esac
}

main "$@"
