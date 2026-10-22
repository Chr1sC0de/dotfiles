#!/usr/bin/env bash
set -uo pipefail
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
[[ ${2:-} =~ ^[0-9]+$ && -f $1/$2.json ]] || exit 0
item=$(cat -- "$1/$2.json")
kind=$(jq -r '.kind' <<<"$item")
if [[ $kind == workspace ]]; then
    # Re-resolve the active tab on every refresh, without moving focus.
    if state=$(herdr api snapshot 2>/dev/null); then
        pane=$(jq -r --arg id "$(jq -r '.workspace' <<<"$item")" '
          .result.snapshot as $s | ([$s.workspaces[] | select(.workspace_id==$id)][0].active_tab_id) as $tab |
          [$s.layouts[] | select(.tab_id==$tab)][0].focused_pane_id // empty' <<<"$state")
        if [[ -n $pane ]] && output=$(herdr pane read "$pane" --source visible --format ansi 2>/dev/null); then
            printf '%s\n' "$output"
            exit 0
        fi
    fi
    printf 'Pane is no longer available. Select another row or press Ctrl+R.\n'
    exit 0
fi
path=$(jq -r '.path' <<<"$item")
printf '%s\n%s\n\n' "$(jq -r '.label' <<<"$item")" "$path"
if [[ $kind != project ]]; then
    ref=$(jq -r '.ref // "HEAD"' <<<"$item")
    git -C "$path" log -1 --color=always --format='%h %d %s%n%an · %ar' "$ref" -- 2>/dev/null || true
    printf '\n'
fi
readme=''
while IFS= read -r -d '' file; do
    readme=$file
    break
done < <(find "$path" -maxdepth 1 -type f -iname 'readme*' -print0 2>/dev/null)
if [[ -n $readme ]]; then
    if command -v bat >/dev/null; then
        bat --color=always --paging=never -- "$readme"
    elif command -v batcat >/dev/null; then
        batcat --color=always --paging=never -- "$readme"
    else cat -- "$readme"; fi
else
    ls -la -- "$path" 2>/dev/null
fi
