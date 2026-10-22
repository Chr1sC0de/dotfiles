#!/usr/bin/env bash
# Shared by the picker and its independently executed preview.
export PATH="$HOME/.local/bin:$HOME/.fzf/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
fail() {
    printf 'herdr picker: %s\n' "$*" >&2
    exit 1
}
checkout() { git -C "$1" rev-parse --show-toplevel 2>/dev/null || (cd -- "$1" 2>/dev/null && pwd -P); }
repo_key() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }
snapshot() {
    herdr api snapshot >"$1" || fail 'Cannot read Herdr state; check that the session is running.'
    jq -e '.result.snapshot.workspaces | type == "array"' "$1" >/dev/null || fail 'Invalid Herdr snapshot response.'
}
# Resolve each workspace independently; labels are never used as identifiers.
workspaces() {
    local item path canonical
    while IFS= read -r item; do
        path=$(jq -r '.path' <<<"$item")
        canonical=$(checkout "$path") || canonical=$path
        jq -c --arg path "$canonical" '.path=$path' <<<"$item"
    done < <(jq -c '.result.snapshot as $s | $s.workspaces[] as $w |
        ([$s.layouts[] | select(.tab_id==$w.active_tab_id)][0].focused_pane_id // "") as $pane |
        {kind:"workspace", workspace:$w.workspace_id, label:$w.label, pane:$pane,
         path:($w.worktree.checkout_path // ([$s.panes[] | select(.pane_id==$pane)][0].cwd) //
           ([$s.panes[] | select(.workspace_id==$w.workspace_id)][0].cwd) // "")}' "$1")
}
