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
	'worktree remove')
		[[ $3 == --workspace && $4 == w-target ]] || return 1
		printf '%s\n' "$PWD" >>"$REMOVE_TEST_ROOT/removal-cwds"
		if [[ ${REMOVE_FAILURE:-0} == 1 ]]; then
			printf '{"error":{"code":"worktree_remove_failed","message":"test failure"}}\n' >&2
			return 1
		fi
		[[ ${LEAVE_CHECKOUT:-0} != 1 ]] || {
			printf '{"result":{}}\n'
			return
		}
		local output
		local -a force=()
		[[ ${5:-} != --force ]] || force=(--force)
		if ! output=$(command git -C "$REMOVE_REPO" worktree remove "${force[@]}" "$REMOVE_CHECKOUT" 2>&1); then
			local code=worktree_remove_failed
			[[ $output != *'modified or untracked files'* ]] || code=dirty_worktree_requires_force
			jq -cn --arg code "$code" --arg message "$output" '{error:{code:$code,message:$message}}' >&2
			return 1
		fi
		if [[ ${CHANGE_BRANCH_AFTER_REMOVE:-0} == 1 ]]; then
			command git -C "$REMOVE_REPO" update-ref refs/heads/feature/delete "$REMOVE_OTHER_COMMIT"
		elif [[ ${CHECKOUT_BRANCH_AFTER_REMOVE:-0} == 1 ]]; then
			command git -C "$REMOVE_REPO" checkout -q feature/delete
		fi
		printf '{"result":{}}\n'
		;;
	*)
		printf 'Unexpected Herdr call: %s\n' "$*" >&2
		return 1
		;;
	esac
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
export -f herdr fzf uv

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
	rm -f -- "$T/actions" "$T/get-count" "$T/removal-cwds" "$T/menu" "$T/options"
	export MENU_CHOICE='Delete checkout and local branch'
	unset GET_FAILURE CHANGED_MEMBERSHIP REMOVE_FAILURE LEAVE_CHECKOUT CHANGE_BRANCH_AFTER_REMOVE \
		CHECKOUT_BRANCH_AFTER_REMOVE MENU_MUTATION FZF_STATUS REMOVE_OTHER_COMMIT
}
run() {
	printf '%s' "${1:-}" | bash "$picker" remove-current >"$T/output" 2>"$T/error"
}
branch_exists() { git -C "$REMOVE_REPO" show-ref --verify --quiet refs/heads/feature/delete; }
no_removal() {
	[[ -d $REMOVE_CHECKOUT ]]
	branch_exists
	! tr '\0' '\n' <"$T/actions" | grep -Fxq remove
}
contains() { grep -Fq -- "$2" "$1" || {
	printf 'Missing %s in %s\n' "$2" "$1" >&2
	exit 1
}; }

fixture checkout-only
MENU_CHOICE='Delete checkout only' run
[[ ! -e $REMOVE_CHECKOUT ]]
branch_exists
contains "$T/options" "$REMOVE_CHECKOUT"
contains "$T/options" feature/delete
contains "$T/removal-cwds" "$REMOVE_REPO/.git"
[[ $(head -n 1 "$T/menu") == Cancel ]]
contains "$T/options" start:first

fixture merged
run
[[ ! -e $REMOVE_CHECKOUT ]]
if branch_exists; then exit 1; fi

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
if tr '\0' '\n' <"$T/actions" | grep -Fxq -- --force; then exit 1; fi

fixture false-success
if LEAVE_CHECKOUT=1 run; then exit 1; fi
branch_exists
contains "$T/error" 'Checkout still exists'

fixture dirty-cancel
printf 'modified\n' >"$REMOVE_CHECKOUT/tracked"
printf 'untracked\n' >"$REMOVE_CHECKOUT/new"
run $'wrong confirmation\n'
[[ -d $REMOVE_CHECKOUT && -e $REMOVE_CHECKOUT/new ]]
branch_exists
contains "$T/output" 'checkout and branch kept'
if tr '\0' '\n' <"$T/actions" | grep -Fxq -- --force; then exit 1; fi

fixture dirty-force
printf 'modified\n' >"$REMOVE_CHECKOUT/tracked"
printf 'untracked\n' >"$REMOVE_CHECKOUT/new"
run "$REMOVE_CHECKOUT"$'\n'
[[ ! -e $REMOVE_CHECKOUT ]]
if branch_exists; then exit 1; fi
tr '\0' '\n' <"$T/actions" | grep -Fxq -- --force

fixture unmerged-cancel
git -C "$REMOVE_CHECKOUT" commit --allow-empty -qm unmerged
run $'\e'
[[ ! -e $REMOVE_CHECKOUT ]]
branch_exists
contains "$T/output" 'kept'

fixture unmerged-force
git -C "$REMOVE_CHECKOUT" commit --allow-empty -qm unmerged
run $'feature/delete\n'
[[ ! -e $REMOVE_CHECKOUT ]]
if branch_exists; then exit 1; fi

fixture dirty-unmerged
git -C "$REMOVE_CHECKOUT" commit --allow-empty -qm unmerged
printf 'untracked\n' >"$REMOVE_CHECKOUT/new"
run "$REMOVE_CHECKOUT"$'\nfeature/delete\n'
[[ ! -e $REMOVE_CHECKOUT ]]
if branch_exists; then exit 1; fi

fixture branch-changed
REMOVE_OTHER_COMMIT=$(printf 'concurrent commit\n' | git -C "$REMOVE_REPO" commit-tree 'HEAD^{tree}' -p HEAD)
export REMOVE_OTHER_COMMIT
if CHANGE_BRANCH_AFTER_REMOVE=1 run; then exit 1; fi
[[ ! -e $REMOVE_CHECKOUT ]]
branch_exists
contains "$T/error" 'changed and was kept'

fixture branch-in-use
if CHECKOUT_BRANCH_AFTER_REMOVE=1 run; then exit 1; fi
[[ ! -e $REMOVE_CHECKOUT ]]
branch_exists
contains "$T/error" 'deletion failed'
if grep -Fq 'Force-delete' "$T/error"; then exit 1; fi

printf 'Herdr current worktree removal tests passed\n'
