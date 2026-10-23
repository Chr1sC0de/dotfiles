#!/usr/bin/env bash
set -euo pipefail
# Resolve each link relative to its own directory before loading sibling files.
SOURCE=${BASH_SOURCE[0]}
while [[ -L $SOURCE ]]; do
    HERE=$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)
    SOURCE=$(readlink -- "$SOURCE")
    [[ $SOURCE == /* ]] || SOURCE="$HERE/$SOURCE"
done
HERE=$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)
# shellcheck source=common.sh
source "$HERE/common.sh"
[[ ${1:-} == projects || ${1:-} == worktrees || ${1:-} == remove-current ]] ||
    fail 'Usage: herdr-sessionizer projects|worktrees|remove-current'
dependencies=(git herdr fzf jq)
[[ $1 == remove-current ]] || dependencies+=(uv)
for dependency in "${dependencies[@]}"; do
    command -v "$dependency" >/dev/null || fail "Missing $dependency; run the dotfiles dependency installer and install Herdr."
done
TMP=$(mktemp -d)
REMOVE_WORKSPACE_TO_CLOSE=''
REMOVE_PROJECT_ROOT=''
REMOVE_PROJECT_COMMON=''
cleanup() {
    local status=$?
    rm -rf -- "$TMP"
    if ((status != 0)) && [[ -t 0 && -t 2 ]]; then
        printf '\nPress any key to close.' >&2
        read -rsn1 _ || true
    fi
    # Return to the same project before closing the target workspace. Closing can
    # kill this popup, so branch handling and temporary-file cleanup are already done.
    if [[ -n $REMOVE_WORKSPACE_TO_CLOSE ]]; then
        if ! remove_focus_root; then
            printf 'herdr picker: Checkout removed; cannot return to project root %s. Workspace %s was left open.\n' \
                "$REMOVE_PROJECT_ROOT" "$REMOVE_WORKSPACE_TO_CLOSE" >&2
            if [[ -t 0 && -t 2 ]]; then
                printf '\nPress any key to close.' >&2
                read -rsn1 _ || true
            fi
            exit 1
        fi
        if ! herdr workspace close "$REMOVE_WORKSPACE_TO_CLOSE" >/dev/null; then
            printf 'herdr picker: Checkout removed; cannot close Herdr workspace %s.\n' "$REMOVE_WORKSPACE_TO_CLOSE" >&2
            if [[ -t 0 && -t 2 ]]; then
                printf '\nPress any key to close.' >&2
                read -rsn1 _ || true
            fi
            exit 1
        fi
    fi
}
trap cleanup EXIT
trap 'exit 0' INT TERM
if [[ $1 == remove-current ]]; then
    # Git's unmerged-branch refusal is checked before offering force deletion.
    export LC_ALL=C
    # shellcheck source=remove.sh
    source "$HERE/remove.sh"
    remove_current
    exit 0
fi
# shellcheck source=config.sh
source "$HERE/config.sh"
discover() {
    local i root depth marker path
    local -a limits
    declare -A seen=()
    for i in "${!SEARCH_ROOTS[@]}"; do
        root=${SEARCH_ROOTS[$i]} depth=${SEARCH_DEPTHS[$i]}
        limits=()
        if [[ $depth != recursive ]]; then
            [[ $depth =~ ^[0-9]+$ ]] || fail "Invalid search depth: $depth"
            limits=(-maxdepth "$((10#$depth + 1))")
        fi
        [[ -d $root ]] || continue
        find "$root" "${limits[@]}" -name .git -print0 -prune >"$TMP/discovery" || fail "Cannot search $root"
        while IFS= read -r -d '' marker; do
            path=$(git -C "${marker%/.git}" rev-parse --show-toplevel 2>/dev/null) || continue
            [[ -z ${seen[$path]:-} ]] || continue
            seen[$path]=1
            printf '%s\0' "$path"
        done <"$TMP/discovery"
    done | path_rows project
}
refresh() {
    snapshot "$TMP/snapshot"
    workspaces "$TMP/snapshot" >"$TMP/workspaces"
}
choose() {
    local prompt=$1 new=${2:-false} item id=0 preview status
    mkdir -p "$TMP/rows"
    cat >"$TMP/choice-items"
    while IFS= read -r item; do
        id=$((id + 1))
        printf '%s\n' "$item" >"$TMP/rows/$id.json"
    done <"$TMP/choice-items"
    jq -rs '
        def basename: sub("/+$"; "") | if . == "" then "/" else split("/") | last end;
        to_entries[] | (.key + 1 | tostring) as $id | .value |
        (if .kind == "project" or .kind == "checkout" then .path | basename
         elif .kind == "workspace" and (.label | startswith("/")) then .label | basename
         else .label end) as $name |
        [$id, ("["+.kind+"] "+$name)] | @tsv' "$TMP/choice-items" >"$TMP/menu"
    printf -v preview '%q %q {1}' "$HERE/preview.sh" "$TMP/rows"
    local -a bindings=(--bind 'esc:abort,ctrl-c:abort,ctrl-r:refresh-preview')
    [[ $new != true ]] || bindings+=(--expect ctrl-n)
    status=0
    # Ignore user fzf defaults that could change output format or cancellation.
    FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' SHELL=/bin/bash fzf --delimiter=$'\t' --with-nth=2.. --layout=reverse \
        --no-sort --no-multi --prompt="$prompt" --preview="$preview" --preview-window=right:50% \
        "${bindings[@]}" <"$TMP/menu" >"$TMP/selection" || status=$?
    case $status in 0) ;; 1 | 130) exit 0 ;; *) fail "fzf failed (exit $status)." ;; esac
    if [[ $new == true && $(head -n 1 "$TMP/selection") == ctrl-n ]]; then
        SELECTED='{"kind":"new"}'
    else
        id=$(tail -n 1 "$TMP/selection")
        id=${id%%$'\t'*}
        [[ $id =~ ^[0-9]+$ && -f $TMP/rows/$id.json ]] || exit 0
        SELECTED=$(cat "$TMP/rows/$id.json")
    fi
}
run_herdr() { herdr "$@" >"$TMP/result" || fail "Herdr $1 $2 failed; see the error above."; }
focus_existing() {
    local path=$1 id
    refresh
    id=$(jq -rs --arg path "$path" '[.[] | select(.path==$path)][0].workspace // empty' "$TMP/workspaces")
    [[ -n $id ]] || return 1
    run_herdr workspace focus "$id"
}
open_branch() {
    local branch=$1 field path=''
    git -C "$repo" worktree list --porcelain -z >"$TMP/latest-checkouts" || fail "Cannot list checkouts in $repo"
    while IFS= read -r -d '' field; do
        case $field in
        'worktree '*) path=${field#worktree } ;;
        "branch refs/heads/$branch")
            path=$(checkout "$path")
            focus_existing "$path" || run_herdr worktree open --cwd "$repo" --path "$path" --focus
            return
            ;;
        esac
    done <"$TMP/latest-checkouts"
    run_herdr worktree create --cwd "$repo" --branch "$branch" --focus
}
# The repository picker does not need workspace state until a repo is chosen.
if [[ $1 == projects ]]; then refresh; fi
discover >"$TMP/projects"
if [[ $1 == projects ]]; then
    {
        cat "$TMP/workspaces"
        jq -c --slurpfile open "$TMP/workspaces" 'select(.path as $p | all($open[]; .path != $p))' "$TMP/projects"
    } >"$TMP/candidates"
    choose 'Projects > ' <"$TMP/candidates"
    if [[ $(jq -r '.kind' <<<"$SELECTED") == workspace ]]; then
        run_herdr workspace focus "$(jq -r '.workspace' <<<"$SELECTED")"
    else
        path=$(jq -r '.path' <<<"$SELECTED")
        focus_existing "$path" || run_herdr workspace create --cwd "$path" --focus
    fi
    exit 0
fi
choose 'Repository > ' <"$TMP/projects"
repo=$(jq -r '.path' <<<"$SELECTED")
key=$(repo_key "$repo") || fail "Cannot read repository: $repo"
refresh
: >"$TMP/candidates"
while IFS= read -r -d '' item && IFS= read -r -d '' path; do
    if [[ $(repo_key "$path" || true) == "$key" ]]; then printf '%s\n' "$item" >>"$TMP/candidates"; fi
done < <(jq -j '(tojson), "\u0000", .path, "\u0000"' "$TMP/workspaces")
git -C "$repo" worktree list --porcelain -z >"$TMP/checkouts" || fail "Cannot list checkouts in $repo"
while IFS= read -r -d '' field; do
    [[ $field == 'worktree '* ]] || continue
    path=$(checkout "${field#worktree }")
    printf '%s\0' "$path"
done <"$TMP/checkouts" | path_rows checkout >>"$TMP/candidates"
git -C "$repo" for-each-ref --format='%(refname) %(symref)' refs/heads refs/remotes >"$TMP/refs" || fail "Cannot list branches in $repo"
jq -Rc --arg path "$repo" '
    split(" ") | select(.[1] == "") | .[0] as $ref |
    if $ref | startswith("refs/heads/") then
        {kind:"local", path:$path, ref:$ref, label:($ref | ltrimstr("refs/heads/"))}
    else
        {kind:"remote", path:$path, ref:$ref, label:($ref | ltrimstr("refs/remotes/"))}
    end' "$TMP/refs" >>"$TMP/candidates"
jq -cn --arg path "$repo" '{kind:"new",path:$path,label:"New branch (Ctrl+N)"}' >>"$TMP/candidates"
choose 'Worktrees > ' true <"$TMP/candidates"
kind=$(jq -r '.kind' <<<"$SELECTED")
case $kind in
workspace) run_herdr workspace focus "$(jq -r '.workspace' <<<"$SELECTED")" ;;
checkout)
    path=$(jq -r '.path' <<<"$SELECTED")
    focus_existing "$path" || run_herdr worktree open --cwd "$repo" --path "$path" --focus
    ;;
local) open_branch "$(jq -r '.label' <<<"$SELECTED")" ;;
remote)
    ref=$(jq -r '.ref' <<<"$SELECTED")
    branch=${ref#refs/remotes/}
    branch=${branch#*/}
    # An existing local branch must not silently replace the chosen remote ref.
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
        fail "Local branch '$branch' already exists. Choose its local row, or create a differently named branch."
    fi
    run_herdr worktree create --cwd "$repo" --branch "$branch" --base "$ref" --focus
    ;;
new)
    printf 'New branch (Escape or Ctrl+C cancels): ' >/dev/tty
    branch=''
    # Read characters so Escape cancels immediately, without requiring Enter.
    while IFS= read -rsn1 char </dev/tty; do
        case $char in
        $'\e' | $'\003')
            printf '\n' >/dev/tty
            exit 0
            ;;
        '') break ;;
        $'\177' | $'\b') [[ -z $branch ]] || {
            branch=${branch%?}
            printf '\b \b' >/dev/tty
        } ;;
        *)
            branch+=$char
            printf '%s' "$char" >/dev/tty
            ;;
        esac
    done
    printf '\n' >/dev/tty
    [[ -n $branch ]] || exit 0
    if [[ $branch == -* || $branch == '@{'* ]] || ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
        fail "Invalid branch name: $branch"
    fi
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
        open_branch "$branch"
    else
        run_herdr worktree create --cwd "$repo" --branch "$branch" --base HEAD --focus
    fi
    ;;
esac
