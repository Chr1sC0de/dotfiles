#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
export HOME="$T/home" PATH="$T/bin:$PATH"
mkdir -p "$HOME/.local/bin" "$T/bin" "$T/source space/my-profile/scripts/herdr-sessionizer" "$HOME/projects" "$T/scratch"
cp "$ROOT"/my-profile/scripts/herdr-sessionizer/*.sh "$T/source space/my-profile/scripts/herdr-sessionizer/"
mkdir -p "$T/source space/utils"
cp "$ROOT"/utils/{common,symlink-create}.sh "$T/source space/utils/"
(cd "$T/source space" && bash utils/symlink-create.sh herdr-sessionizer && bash utils/symlink-create.sh herdr-sessionizer-preview)
# Chain a relative link through each installed command.
ln -s herdr-sessionizer "$HOME/.local/bin/picker-chain"
ln -s herdr-sessionizer-preview "$HOME/.local/bin/preview-chain"
export TEST_ROOT=$T
cat >"$T/bin/herdr" <<'FAKE'
#!/usr/bin/env bash
set -eu
if [[ $1 == api ]]; then
    [[ ${FAIL_SNAPSHOT:-0} == 0 ]] || { echo 'server unavailable' >&2; exit 1; }
    n=$(cat "$TEST_ROOT/snapshot-count" 2>/dev/null || echo 0)
    echo "$((n+1))" > "$TEST_ROOT/snapshot-count"
    if [[ $n -gt 0 && -f $TEST_ROOT/later.json ]]; then cat "$TEST_ROOT/later.json"; else cat "$TEST_ROOT/state.json"; fi
elif [[ $1 == pane ]]; then
    printf '%s\n' "$*" >> "$TEST_ROOT/preview-calls"
    [[ ${FAIL_PANE:-0} == 0 ]] || exit 1
    printf '\033[31mterminal preview\033[0m\n'
else
    printf '%s\0' "$@" >> "$TEST_ROOT/actions"
    [[ ${FAIL_ACTION:-0} == 0 ]] || { echo 'operation failed' >&2; exit 1; }
    echo '{"result":{}}'
fi
FAKE
cat >"$HOME/.local/bin/fzf" <<'FAKE'
#!/usr/bin/env bash
set -eu
n=$(cat "$TEST_ROOT/count" 2>/dev/null || echo 0)
n=$((n+1)); echo "$n" > "$TEST_ROOT/count"
cat > "$TEST_ROOT/menu$n"
printf '%s\n' "$@" > "$TEST_ROOT/options$n"
for option in "$@"; do
    if [[ $option == --preview=* && -s $TEST_ROOT/menu$n ]]; then
        preview=${option#--preview=}
        row=$(head -n 1 "$TEST_ROOT/menu$n")
        row=${row%%$'\t'*}
        bash -c "${preview//\{1\}/$row}" > "$TEST_ROOT/fzf-preview$n"
    fi
done
[[ ${FZF_STATUS:-0} == 0 ]] || exit "$FZF_STATUS"
choice=$(sed -n "${n}p" "$TEST_ROOT/choices")
[[ $choice != ctrl-n ]] || { printf 'ctrl-n\n'; exit; }
grep -F -- "$choice" "$TEST_ROOT/menu$n" | head -n 1
FAKE
chmod +x "$T/bin/herdr" "$HOME/.local/bin/fzf"
init() {
    mkdir -p "$1"
    git -C "$1" init -q -b main
    git -C "$1" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm initial
}
repo="$HOME/projects/repo space ' \$(literal)"
init "$repo"
init "$HOME/projects/group/too-deep"
init "$T/scratch/a/b/deep"
printf '# Read me\n' >"$repo/README.md"
config_file="$HOME/.config/herdr-sessionizer/config.toml"
mkdir -p "$(dirname "$config_file")"
cat >"$config_file" <<EOF
[[search_roots]]
path = "~/projects"
depth = 1
[[search_roots]]
path = "$T/scratch"
depth = "recursive"
[[search_roots]]
path = "~/missing"
depth = 0
EOF
empty='{"result":{"snapshot":{"workspaces":[],"layouts":[],"panes":[]}}}'
reset() {
    echo "$empty" >"$T/state.json"
    rm -f "$T/count" "$T/snapshot-count" "$T/later.json" "$T/actions"
}
run() { "$HOME/.local/bin/picker-chain" "$1"; }
contains() { grep -Fq -- "$2" "$1" || {
    echo "Missing $2 in $1" >&2
    exit 1
}; }
reset
printf '[project] %s\n' "$repo" >"$T/choices"
run projects
contains "$T/menu1" "$repo"
contains "$T/menu1" '/a/b/deep'
if grep -q too-deep "$T/menu1"; then exit 1; fi
contains "$T/options1" 'right:50%'
contains "$T/fzf-preview1" 'Read me'
tr '\0' '\n' <"$T/actions" >"$T/args"
contains "$T/args" "$repo"
contains "$T/args" create
# Unrelated project metadata must not affect parsing or create project artifacts.
mkdir "$T/unrelated"
printf '[project]\nname = "unrelated"\nversion = "0.0.0"\nrequires-python = ">=999"\n' >"$T/unrelated/pyproject.toml"
printf '[invalid\n' >"$T/unrelated/uv.toml"
printf '0.0\n' >"$T/unrelated/.python-version"
reset
(cd "$T/unrelated" && run projects)
contains "$T/menu1" "$repo"
[[ ! -e $T/unrelated/.venv && ! -e $T/unrelated/uv.lock ]]
# Missing uv and runtime failures stop before Herdr or fzf runs.
reset
if (
    # Invoked in the picker subprocess.
    # shellcheck disable=SC2329
    command() {
        if [[ $1 == -v && $2 == uv ]]; then return 1; fi
        builtin command "$@"
    }
    export -f command
    run projects
) 2>"$T/error"; then exit 1; fi
contains "$T/error" 'Missing uv'
[[ ! -e $T/snapshot-count && ! -e $T/count && ! -e $T/actions ]]
if (
    # Invoked in the picker subprocess.
    # shellcheck disable=SC2329
    uv() {
        printf 'uv: runtime download failed\n' >&2
        return 1
    }
    export -f uv
    run projects
) 2>"$T/error"; then exit 1; fi
contains "$T/error" 'runtime download failed'
[[ ! -e $T/snapshot-count && ! -e $T/count && ! -e $T/actions ]]
# Duplicate labels survive; canonical pane cwd suppresses redundant project rows.
mkdir "$repo/sub"
ln -s "$repo" "$T/alias"
jq -n --arg path "$T/alias/sub" '{result:{snapshot:{workspaces:[{workspace_id:"w1",label:"same",active_tab_id:"t1"},{workspace_id:"w2",label:"same",active_tab_id:"t2"}],layouts:[{tab_id:"t1",focused_pane_id:"p1"},{tab_id:"t2",focused_pane_id:"p2"}],panes:[{workspace_id:"w1",pane_id:"p1",cwd:$path},{workspace_id:"w2",pane_id:"p2",cwd:$path}]}}}' >"$T/open.json"
reset
cp "$T/open.json" "$T/state.json"
printf 'w2\n' >"$T/choices"
run projects
[[ $(grep -c '\[workspace\] same' "$T/menu1") == 2 ]]
if grep -F '[project]' "$T/menu1" | grep -Fq "$repo"; then exit 1; fi
tr '\0' '\n' <"$T/actions" >"$T/args"
contains "$T/args" w2
# Recheck catches a workspace opened while the picker was visible.
reset
cp "$T/open.json" "$T/later.json"
printf '[project] %s\n' "$repo" >"$T/choices"
run projects
tr '\0' '\n' <"$T/actions" >"$T/args"
contains "$T/args" focus
if grep -q create "$T/args"; then exit 1; fi
# Missing and empty config preserve open workspaces only.
mv "$config_file" "$T/config.saved"
for config in missing empty; do
    [[ $config != empty ]] || : >"$config_file"
    reset
    cp "$T/open.json" "$T/state.json"
    printf 'w1\n' >"$T/choices"
    run projects
    [[ $(wc -l <"$T/menu1") == 2 ]]
done
mv "$T/config.saved" "$config_file"
# Invalid configuration fails before querying Herdr or opening fzf.
cp "$config_file" "$T/config.valid"
for invalid in \
    'search_roots = [' \
    'search_roots = "wrong"' \
    'search_roots = [1]' \
    'search_roots = [{path = "~/projects"}]' \
    'search_roots = [{path = 1, depth = 1}]' \
    'search_roots = [{path = "relative", depth = 1}]' \
    'search_roots = [{path = "~/projects", depth = -1}]' \
    'search_roots = [{path = "~/projects", depth = true}]' \
    'search_roots = [{path = "~/projects", depth = 1.5}]' \
    'search_roots = [{path = "~/projects", depth = "1"}]'; do
    printf '%s\n' "$invalid" >"$config_file"
    reset
    if run projects 2>"$T/error"; then exit 1; fi
    contains "$T/error" "$config_file"
    [[ ! -e $T/snapshot-count && ! -e $T/count && ! -e $T/actions ]]
done
# An empty list explicitly disables discovery too.
printf 'search_roots = []\n' >"$config_file"
reset
cp "$T/open.json" "$T/state.json"
printf 'w1\n' >"$T/choices"
run projects
[[ $(wc -l <"$T/menu1") == 2 ]]
# Depth zero includes a root checkout; shell metacharacters remain literal.
uv run --no-project --no-config --isolated --python '>=3.11' python - "$repo" >"$config_file" <<'PY'
import json
import sys
print("search_roots = [{path = " + json.dumps(sys.argv[1]) + ", depth = 0}]")
PY
reset
printf '[project] %s\n' "$repo" >"$T/choices"
run projects
[[ $(wc -l <"$T/menu1") == 1 ]]
contains "$T/menu1" "$repo"
mv "$T/config.valid" "$config_file"
# Preview resolves selected pane in active tab and preserves raw ANSI.
mkdir "$T/rows"
printf '{"kind":"workspace","workspace":"w2"}\n' >"$T/rows/1.json"
"$HOME/.local/bin/preview-chain" "$T/rows" 1 >"$T/preview"
contains "$T/preview-calls" 'pane read p2 --source visible --format ansi'
contains "$T/preview" $'\033[31m'
FAIL_PANE=1 "$HOME/.local/bin/preview-chain" "$T/rows" 1 >"$T/preview"
contains "$T/preview" 'no longer available'
jq -n --arg path "$repo" '{kind:"project",label:"readme",path:$path}' >"$T/rows/1.json"
"$HOME/.local/bin/preview-chain" "$T/rows" 1 >"$T/preview"
contains "$T/preview" 'Read me'
# Local branches without checkouts use create (which reuses the branch).
git -C "$repo" branch local-branch
git -C "$repo" update-ref refs/remotes/upstream/remote-branch HEAD
reset
printf '[project]\n[local] local-branch\n' >"$T/choices"
run worktrees
tr '\0' '\n' <"$T/actions" >"$T/args"
contains "$T/args" create
contains "$T/args" local-branch
contains "$T/menu2" 'New branch'
contains "$T/options2" ctrl-n
reset
printf '[project]\n[remote] upstream/remote-branch\n' >"$T/choices"
run worktrees
tr '\0' '\n' <"$T/actions" >"$T/args"
contains "$T/args" refs/remotes/upstream/remote-branch
# Existing checkout and checked-out local branch reopen via Herdr.
git -C "$repo" worktree add -q "$T/checkout" local-branch
for selection in '[checkout]' '[local] local-branch'; do
    reset
    printf '[project]\n%s\n' "$selection" >"$T/choices"
    run worktrees
    tr '\0' '\n' <"$T/actions" >"$T/args"
    contains "$T/args" open
done
# Cancellation and failures never mutate workspace state.
for status in 1 130; do
    reset
    FZF_STATUS=$status run projects
    [[ ! -f $T/actions ]]
done
reset
if FZF_STATUS=2 run projects 2>"$T/error"; then exit 1; fi
contains "$T/error" 'fzf failed'
reset
if FAIL_SNAPSHOT=1 run projects 2>"$T/error"; then exit 1; fi
contains "$T/error" 'Cannot read Herdr'
reset
printf '[project]\n' >"$T/choices"
if FAIL_ACTION=1 run projects 2>"$T/error"; then exit 1; fi
contains "$T/error" 'Herdr workspace create failed'
# Exercise the branch prompt through a real controlling terminal.
if command -v script >/dev/null; then
    for selection in '[new]' ctrl-n; do
        reset
        printf '[project]\n%s\n' "$selection" >"$T/choices"
        printf 'fresh-branch\n' | script -qec "'$HOME/.local/bin/picker-chain' worktrees" /dev/null >"$T/prompt"
        tr '\0' '\n' <"$T/actions" >"$T/args"
        contains "$T/args" fresh-branch
        contains "$T/args" HEAD
    done
    reset
    printf '[project]\n[new]\n' >"$T/choices"
    printf 'bad branch\nx' | script -qec "'$HOME/.local/bin/picker-chain' worktrees" /dev/null >"$T/prompt" && exit 1
    contains "$T/prompt" 'Invalid branch name'
    reset
    printf '[project]\n[new]\n' >"$T/choices"
    printf '\033' | script -qec "'$HOME/.local/bin/picker-chain' worktrees" /dev/null >"$T/prompt"
    [[ ! -f $T/actions ]]
fi
printf 'herdr sessionizer integration tests passed\n'
