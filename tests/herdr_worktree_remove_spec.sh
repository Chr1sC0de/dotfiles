#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf -- "$T"' EXIT
export REMOVE_TEST_ROOT=$T HERDR_ENV=1 HERDR_ACTIVE_WORKSPACE_ID=w-target HERDR_WORKSPACE_ID=w-wrong
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
picker="$ROOT/my-profile/scripts/herdr-sessionizer/picker.sh"

# Exported functions take precedence over installed commands without changing HOME.
# shellcheck disable=SC2329
herdr() {
	printf '%s\0' "$@" >>"$REMOVE_TEST_ROOT/actions"
	case "$1 $2" in
	'workspace get')
		[[ $3 == w-target ]] || return 1
		local count=0
		[[ ! -f $REMOVE_TEST_ROOT/get-count ]] || read -r count <"$REMOVE_TEST_ROOT/get-count"
		count=$((count + 1))
		printf '%s\n' "$count" >"$REMOVE_TEST_ROOT/get-count"
		if [[ ${GET_FAILURE:-0} == 1 ]]; then
			printf '{"error":{"code":"workspace_not_found"}}\n' >&2
			return 1
		elif [[ ${CHANGED_MEMBERSHIP:-0} == 1 && $count -gt 1 ]]; then
			jq '.result.workspace.worktree.checkout_path += "-changed"' "$REMOVE_TEST_ROOT/workspace"
		else
			cat "$REMOVE_TEST_ROOT/workspace"
		fi
		;;
	'api snapshot')
		[[ ${SNAPSHOT_FAILURE:-0} != 1 ]] || return 1
		cat "$REMOVE_TEST_ROOT/snapshot"
		;;
	'workspace create')
		[[ $# == 5 && $3 == --cwd && $4 == "$REMOVE_REPO" && $5 == --no-focus ]] || return 1
		[[ ${CREATE_FAILURE:-0} != 1 ]] || return 1
		: >"$REMOVE_TEST_ROOT/created"
		printf '{"result":{"workspace":{"workspace_id":"w-created"}}}\n'
		;;
	'workspace focus')
		local expected=w-root
		[[ ! -e $REMOVE_TEST_ROOT/created ]] || expected=w-created
		[[ $# == 3 && $3 == "$expected" && ! -e $REMOVE_CHECKOUT && ! -e $TMP ]] || return 1
		[[ ${FOCUS_FAILURE:-0} != 1 ]] || return 1
		if command git -C "$REMOVE_REPO" show-ref --verify --quiet refs/heads/feature/delete; then
			printf 'present\n' >"$REMOVE_TEST_ROOT/branch-at-focus"
		else
			printf 'absent\n' >"$REMOVE_TEST_ROOT/branch-at-focus"
		fi
		printf '%s\n' "$3" >"$REMOVE_TEST_ROOT/focused"
		printf '{"result":{}}\n'
		;;
	'workspace close')
		[[ $# == 3 && $3 == w-target ]] || return 1
		[[ ! -e $REMOVE_CHECKOUT && ! -e $TMP && -e $REMOVE_TEST_ROOT/focused ]] || {
			printf 'Workspace closed before checkout or temporary-file cleanup\n' >&2
			return 1
		}
		if command git -C "$REMOVE_REPO" show-ref --verify --quiet refs/heads/feature/delete; then
			printf 'present\n' >"$REMOVE_TEST_ROOT/branch-at-close"
		else
			printf 'absent\n' >"$REMOVE_TEST_ROOT/branch-at-close"
		fi
		if [[ ${CLOSE_FAILURE:-0} == 1 ]]; then
			printf '{"error":{"code":"workspace_close_failed"}}\n' >&2
			return 1
		fi
		: >"$REMOVE_TEST_ROOT/closed"
		[[ ${HANGUP_ON_CLOSE:-0} != 1 ]] || kill -HUP "$BASHPID"
		printf '{"result":{}}\n'
		;;
	*)
		printf 'Unexpected Herdr call: %s\n' "$*" >&2
		return 1
		;;
	esac
}
# Keep real Git operations, injecting only removal failures and concurrent changes.
# shellcheck disable=SC2329
git() {
	if [[ ${1:-} != --git-dir=* || ${2:-} != worktree || ${3:-} != remove ]]; then
		command git "$@"
		# An explicit status avoids inheriting the original failure inside EXIT traps.
		return $?
	fi
	printf '%s\0' "$@" >>"$REMOVE_TEST_ROOT/git-actions"
	printf '%s\n' "$PWD" >>"$REMOVE_TEST_ROOT/removal-cwds"
	if [[ ${REMOVE_FAILURE:-0} == 1 || (${FORCE_REMOVE_FAILURE:-0} == 1 && ${4:-} == --force) ]]; then
		printf 'fatal: test removal failure\n' >&2
		return 1
	fi
	[[ ${LEAVE_CHECKOUT:-0} != 1 ]] || return 0
	command git "$@" || return 1
	if [[ ${CHANGE_BRANCH_AFTER_REMOVE:-0} == 1 ]]; then
		command git -C "$REMOVE_REPO" update-ref refs/heads/feature/delete "$REMOVE_OTHER_COMMIT"
	elif [[ ${CHECKOUT_BRANCH_AFTER_REMOVE:-0} == 1 ]]; then
		command git -C "$REMOVE_REPO" checkout -q feature/delete
	fi
}
# shellcheck disable=SC2329
fzf() {
	cat >"$REMOVE_TEST_ROOT/menu"
	printf '%s\n' "$@" >"$REMOVE_TEST_ROOT/options"
	case ${MENU_MUTATION:-none} in
	detach) command git -C "$REMOVE_CHECKOUT" checkout -q --detach ;;
	commit) command git -C "$REMOVE_CHECKOUT" commit --allow-empty -qm changed ;;
	esac
	[[ ${FZF_STATUS:-0} == 0 ]] || return "$FZF_STATUS"
	printf '%s\n' "${MENU_CHOICE:-Cancel}"
}
# A removal must not run discovery or invoke its TOML runtime.
# shellcheck disable=SC2329
uv() {
	printf 'remove-current unexpectedly invoked uv\n' >&2
	return 99
}
export -f herdr git fzf uv

fixture() {
	local name=$1
	export REMOVE_REPO="$T/$name/repo space ' \$(literal)"
	export REMOVE_CHECKOUT="$T/$name/checkout space ' \$(literal)"
	mkdir -p "$REMOVE_REPO"
	git -C "$REMOVE_REPO" init -qb main
	printf 'original\n' >"$REMOVE_REPO/tracked"
	git -C "$REMOVE_REPO" add tracked
	git -C "$REMOVE_REPO" commit -qm initial
	git -C "$REMOVE_REPO" worktree add -qb feature/delete "$REMOVE_CHECKOUT"
	jq -cn --arg path "$REMOVE_CHECKOUT" --arg root "$REMOVE_REPO" \
		'{result:{workspace:{workspace_id:"w-target",label:"Delete me",worktree:{
        repo_key:"test",repo_root:$root,checkout_path:$path,is_linked_worktree:true}}}}' >"$T/workspace"
	# An unrelated project and a sibling worktree precede the root, with identical labels.
	jq -cn --arg root "$REMOVE_REPO" --arg path "$REMOVE_CHECKOUT" '
        {result:{snapshot:{workspaces:[
            {workspace_id:"w-other",label:"same",worktree:{checkout_path:"/unrelated/project"}},
            {workspace_id:"w-sibling",label:"same",worktree:{checkout_path:$path}},
            {workspace_id:"w-root",label:"same",worktree:{checkout_path:$root}}],
            layouts:[],panes:[]}}}' >"$T/snapshot"
	rm -f -- "$T/actions" "$T/get-count" "$T/removal-cwds" "$T/menu" "$T/options" \
		"$T/git-actions" "$T/closed" "$T/branch-at-close" "$T/branch-at-focus" "$T/focused" "$T/created"
	export MENU_CHOICE='Delete checkout and local branch'
	unset GET_FAILURE CHANGED_MEMBERSHIP REMOVE_FAILURE LEAVE_CHECKOUT CHANGE_BRANCH_AFTER_REMOVE \
		CHECKOUT_BRANCH_AFTER_REMOVE MENU_MUTATION FZF_STATUS REMOVE_OTHER_COMMIT HANGUP_ON_CLOSE CLOSE_FAILURE FORCE_REMOVE_FAILURE SNAPSHOT_FAILURE CREATE_FAILURE FOCUS_FAILURE
}
run() {
	printf '%s' "${1:-}" | bash "$picker" remove-current >"$T/output" 2>"$T/error"
}
branch_exists() { git -C "$REMOVE_REPO" show-ref --verify --quiet refs/heads/feature/delete; }
no_removal() {
	[[ -d $REMOVE_CHECKOUT ]]
	branch_exists
	[[ ! -e $T/closed && ! -e $T/branch-at-close && ! -e $T/focused && ! -e $T/created ]]
}
closed() {
	[[ -e $T/closed && $(cat "$T/branch-at-close") == "${1:-absent}" ]]
	[[ $(cat "$T/branch-at-focus") == "${1:-absent}" ]]
	[[ $(cat "$T/focused") == "${2:-w-root}" ]]
	[[ $(tr '\0' '\n' <"$T/actions" | tail -n 3) == $'workspace\nclose\nw-target' ]]
}
contains() { grep -Fq -- "$2" "$1" || {
	printf 'Missing %s in %s\n' "$2" "$1" >&2
	exit 1
}; }

if [[ ${BASH_SOURCE[0]} != "$0" ]]; then return 0; fi

# Workspace closure kills its popup. Git cleanup must already be complete.
fixture popup-hangup
status=0
HANGUP_ON_CLOSE=1 run || status=$?
[[ $status == 129 ]]
[[ ! -e $REMOVE_CHECKOUT ]]
if branch_exists; then
	printf 'Popup died before the selected local branch was deleted\n' >&2
	exit 1
fi
closed

fixture root-not-open
jq '.result.snapshot.workspaces |= map(select(.workspace_id != "w-root"))' "$T/snapshot" >"$T/next"
mv "$T/next" "$T/snapshot"
run
[[ ! -e $REMOVE_CHECKOUT && -e $T/created ]]
if branch_exists; then exit 1; fi
closed absent w-created

# Ordinary project workspaces without worktree metadata are matched by pane cwd.
fixture root-pane-cwd
mkdir -p "$REMOVE_REPO/sub"
jq --arg cwd "$REMOVE_REPO/sub" '
    .result.snapshot.workspaces[2] |= (del(.worktree) + {active_tab_id:"root-tab"}) |
    .result.snapshot.layouts=[{tab_id:"root-tab",focused_pane_id:"root-pane"}] |
    .result.snapshot.panes=[{pane_id:"root-pane",workspace_id:"w-root",cwd:$cwd}]' "$T/snapshot" >"$T/next"
mv "$T/next" "$T/snapshot"
run
closed
[[ ! -e $T/created ]]

fixture invalid-root
jq --arg path "$REMOVE_CHECKOUT" '.result.workspace.worktree.repo_root=$path' "$T/workspace" >"$T/next"
mv "$T/next" "$T/workspace"
if run; then exit 1; fi
no_removal
contains "$T/error" 'primary checkout'

for failure in snapshot create focus; do
	fixture "return-$failure-failed"
	case $failure in
	snapshot) export SNAPSHOT_FAILURE=1 ;;
	create)
		jq '.result.snapshot.workspaces=[]' "$T/snapshot" >"$T/next"
		mv "$T/next" "$T/snapshot"
		export CREATE_FAILURE=1
		;;
	focus) export FOCUS_FAILURE=1 ;;
	esac
	if run; then exit 1; fi
	[[ ! -e $REMOVE_CHECKOUT && ! -e $T/closed && ! -e $T/focused ]]
	if branch_exists; then exit 1; fi
	contains "$T/error" 'cannot return to project root'
done

fixture checkout-only
MENU_CHOICE='Delete checkout only' run
[[ ! -e $REMOVE_CHECKOUT ]]
branch_exists
closed present
contains "$T/options" "$REMOVE_CHECKOUT"
contains "$T/options" feature/delete
contains "$T/removal-cwds" "$REMOVE_REPO/.git"
[[ $(head -n 1 "$T/menu") == Cancel ]]
contains "$T/options" start:first

fixture merged
git -C "$REMOVE_REPO" update-ref refs/remotes/origin/feature/delete HEAD
run
[[ ! -e $REMOVE_CHECKOUT ]]
if branch_exists; then exit 1; fi
closed
git -C "$REMOVE_REPO" show-ref --verify --quiet refs/remotes/origin/feature/delete

fixture cancel
MENU_CHOICE=Cancel run
no_removal
for status in 1 130; do
	FZF_STATUS=$status run
	no_removal
done
if FZF_STATUS=2 run; then exit 1; fi
no_removal
contains "$T/error" 'fzf failed'

fixture missing-context
if HERDR_ACTIVE_WORKSPACE_ID='' run; then exit 1; fi
[[ ! -e $T/actions ]]
if HERDR_ENV=0 run; then exit 1; fi
[[ ! -e $T/actions ]]

fixture primary
jq --arg path "$REMOVE_REPO" '.result.workspace.worktree.checkout_path=$path |
    .result.workspace.worktree.is_linked_worktree=false' "$T/workspace" >"$T/next"
mv "$T/next" "$T/workspace"
if run; then exit 1; fi
no_removal
contains "$T/error" 'not a linked Herdr worktree'
# Even erroneous server metadata cannot make a primary checkout removable.
jq '.result.workspace.worktree.is_linked_worktree=true' "$T/workspace" >"$T/next"
mv "$T/next" "$T/workspace"
if run; then exit 1; fi
no_removal
contains "$T/error" 'primary checkout'

fixture detached
git -C "$REMOVE_CHECKOUT" checkout -q --detach
MENU_CHOICE='Delete checkout only' run
[[ ! -e $REMOVE_CHECKOUT ]]
branch_exists
closed present
if grep -Fq 'Delete checkout and local branch' "$T/menu"; then exit 1; fi
contains "$T/options" 'detached HEAD'

for mutation in detach commit; do
	fixture "changed-$mutation"
	if MENU_MUTATION=$mutation run; then exit 1; fi
	no_removal
	contains "$T/error" 'Checkout branch or commit changed'
done
fixture changed-membership
if CHANGED_MEMBERSHIP=1 run; then exit 1; fi
no_removal
contains "$T/error" 'Workspace checkout changed'

fixture missing-workspace
if GET_FAILURE=1 run; then exit 1; fi
no_removal

fixture remove-failed
if REMOVE_FAILURE=1 run; then exit 1; fi
no_removal
contains "$T/error" 'branch deletion was skipped'
if tr '\0' '\n' <"$T/git-actions" | grep -Fxq -- --force; then exit 1; fi

fixture false-success
if LEAVE_CHECKOUT=1 run; then exit 1; fi
branch_exists
contains "$T/error" 'Checkout still exists'
no_removal

fixture dirty-cancel
printf 'modified\n' >"$REMOVE_CHECKOUT/tracked"
printf 'untracked\n' >"$REMOVE_CHECKOUT/new"
run $'wrong confirmation\n'
[[ -d $REMOVE_CHECKOUT && -e $REMOVE_CHECKOUT/new ]]
branch_exists
no_removal
contains "$T/output" 'checkout and branch kept'
if tr '\0' '\n' <"$T/git-actions" | grep -Fxq -- --force; then exit 1; fi

fixture dirty-force
printf 'modified\n' >"$REMOVE_CHECKOUT/tracked"
printf 'untracked\n' >"$REMOVE_CHECKOUT/new"
run "$REMOVE_CHECKOUT"$'\n'
[[ ! -e $REMOVE_CHECKOUT ]]
if branch_exists; then exit 1; fi
closed
tr '\0' '\n' <"$T/git-actions" | grep -Fxq -- --force

fixture unmerged-cancel
git -C "$REMOVE_CHECKOUT" commit --allow-empty -qm unmerged
run $'\e'
[[ ! -e $REMOVE_CHECKOUT ]]
branch_exists
closed present
contains "$T/output" 'kept'

fixture unmerged-force
git -C "$REMOVE_CHECKOUT" commit --allow-empty -qm unmerged
status=0
HANGUP_ON_CLOSE=1 run $'feature/delete\n' || status=$?
[[ $status == 129 ]]
[[ ! -e $REMOVE_CHECKOUT ]]
if branch_exists; then exit 1; fi
closed

fixture dirty-unmerged
git -C "$REMOVE_CHECKOUT" commit --allow-empty -qm unmerged
printf 'untracked\n' >"$REMOVE_CHECKOUT/new"
run "$REMOVE_CHECKOUT"$'\nfeature/delete\n'
[[ ! -e $REMOVE_CHECKOUT ]]
if branch_exists; then exit 1; fi
closed

fixture branch-changed
REMOVE_OTHER_COMMIT=$(printf 'concurrent commit\n' | git -C "$REMOVE_REPO" commit-tree 'HEAD^{tree}' -p HEAD)
export REMOVE_OTHER_COMMIT
if CHANGE_BRANCH_AFTER_REMOVE=1 run; then exit 1; fi
[[ ! -e $REMOVE_CHECKOUT ]]
branch_exists
closed present
contains "$T/error" 'changed and was kept'

fixture branch-in-use
if CHECKOUT_BRANCH_AFTER_REMOVE=1 run; then exit 1; fi
[[ ! -e $REMOVE_CHECKOUT ]]
branch_exists
closed present
contains "$T/error" 'deletion failed'
if grep -Fq 'Force-delete' "$T/error"; then exit 1; fi

fixture locked
git -C "$REMOVE_REPO" worktree lock "$REMOVE_CHECKOUT"
if run; then exit 1; fi
no_removal
contains "$T/error" 'branch deletion was skipped'
if tr '\0' '\n' <"$T/git-actions" | grep -Fxq -- --force; then exit 1; fi

fixture forced-remove-failed
printf 'untracked\n' >"$REMOVE_CHECKOUT/new"
if FORCE_REMOVE_FAILURE=1 run "$REMOVE_CHECKOUT"$'\n'; then exit 1; fi
no_removal
contains "$T/error" 'Forced worktree removal failed'

fixture close-failed
if CLOSE_FAILURE=1 run; then exit 1; fi
[[ ! -e $REMOVE_CHECKOUT && ! -e $T/closed ]]
if branch_exists; then exit 1; fi
contains "$T/branch-at-close" absent
contains "$T/error" 'cannot close Herdr workspace w-target'

printf 'Herdr current worktree removal tests passed\n'
