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
# Encode NUL-delimited paths in one process, preserving whitespace and quoting.
path_rows() {
    jq -Rsc --arg kind "$1" 'split("\u0000")[] | select(length > 0) |
        {kind:$kind, path:., label:.}'
}
# Resolve each workspace independently; labels are never used as identifiers.
workspaces() {
    local item path canonical
    jq -j '.result.snapshot as $s | $s.workspaces[] as $w |
        ([$s.layouts[] | select(.tab_id==$w.active_tab_id)][0].focused_pane_id // "") as $pane |
        {kind:"workspace", workspace:$w.workspace_id, label:$w.label, pane:$pane,
         path:($w.worktree.checkout_path // ([$s.panes[] | select(.pane_id==$pane)][0].cwd) //
           ([$s.panes[] | select(.workspace_id==$w.workspace_id)][0].cwd) // "")} |
        (tojson), "\u0000", .path, "\u0000"' "$1" |
        while IFS= read -r -d '' item && IFS= read -r -d '' path; do
            canonical=$(checkout "$path") || canonical=$path
            printf '%s\0%s\0' "$item" "$canonical"
        done |
        jq -Rsc 'split("\u0000") | . as $fields |
            range(0; length - 1; 2) as $i |
            ($fields[$i] | fromjson) | .path=$fields[$i + 1]'
}
