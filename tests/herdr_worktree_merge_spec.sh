#!/usr/bin/env bash
set -euo pipefail
# Reuse real repositories and the existing workspace lifecycle fixture.
# shellcheck source=tests/herdr_worktree_remove_spec.sh
source "$(dirname -- "$0")/herdr_worktree_remove_spec.sh"
eval "$(declare -f herdr | sed '1s/herdr/original_herdr/')"
eval "$(declare -f git | sed '1s/git/original_git/')"
# shellcheck disable=SC2329
herdr() {
	if [[ $1 == workspace && $2 == focus && ${EXPECT_RESOLUTION:-0} == 1 ]]; then
		[[ $3 == w-root && -d $REMOVE_CHECKOUT && ! -e $TMP ]] || return 1
		: >"$REMOVE_TEST_ROOT/focused"
		return 0
	fi
	original_herdr "$@"
}
# shellcheck disable=SC2329
git() {
	if [[ ${BRANCH_DELETE_FAIL:-0} == 1 && ${2:-} == update-ref && ${3:-} == --no-deref ]]; then return 1; fi
	if [[ ${DEST_CHANGE_AFTER_REMOVE:-0} == 1 && ${2:-} == worktree && ${3:-} == remove ]]; then
		original_git "$@" || return
		command git -C "$REMOVE_REPO" commit --allow-empty -qm concurrent
		return
	fi
	original_git "$@"
}
# shellcheck disable=SC2329
fzf() {
	local prompt='' arg query=''
	for arg in "$@"; do
		case $arg in --prompt=*) prompt=${arg#--prompt=} ;; --query=*) query=${arg#--query=} ;; esac
	done
	cat >"$REMOVE_TEST_ROOT/menu-$prompt"
	printf '%s\n' "$@" >"$REMOVE_TEST_ROOT/options-$prompt"
	case $prompt in
	'Current worktree > ')
		printf '%s\n' 'Merge, then delete checkout and local branch'
		;;
	'Merge type > ')
		[[ ${CANCEL_STAGE:-} != mode ]] || return 130
		printf '%s\n' "${MERGE_MODE:-Squash}"
		;;
	'Squash message > ')
		[[ ${CANCEL_STAGE:-} != chooser ]] || return 130
		if [[ ${GENERATE:-0} == 1 && ! -e $REMOVE_TEST_ROOT/generated ]]; then
			: >"$REMOVE_TEST_ROOT/generated"
			printf 'Generate with Codex\n'
		else
			printf 'Edit default message\n'
		fi
		;;
	'Squash commit message > ')
		printf '%s\n' "$query" >"$REMOVE_TEST_ROOT/draft"
		[[ ${CANCEL_STAGE:-} != edit ]] || return 130
		case ${MERGE_MUTATION:-} in
		source) command git -C "$REMOVE_CHECKOUT" commit --allow-empty -qm concurrent ;;
		dest) command git -C "$REMOVE_REPO" commit --allow-empty -qm concurrent ;;
		dirty) printf changed >"$REMOVE_REPO/dirty" ;;
		esac
		printf '%s\n' "${EDITED_MESSAGE:-$query}"
		;;
	*) return 2 ;;
	esac
}
export -f herdr original_herdr git original_git fzf

merge_fixture() {
	fixture "$1"
	unset MERGE_MODE CANCEL_STAGE GENERATE EDITED_MESSAGE MERGE_MUTATION EXPECT_RESOLUTION \
		BRANCH_DELETE_FAIL DEST_CHANGE_AFTER_REMOVE CODEX_REAL_BIN CODEX_FAKE_FAIL CODEX_FAKE_INVALID CODEX_FAKE_WAIT
	rm -f "$T/generated" "$T/draft" "$T/codex-args" "$T/codex-prompt"
	printf 'feature\n' >"$REMOVE_CHECKOUT/feature"
	git -C "$REMOVE_CHECKOUT" add feature
	git -C "$REMOVE_CHECKOUT" commit -qm 'feat: add feature'
	before=$(git -C "$REMOVE_REPO" rev-parse HEAD)
	source_commit=$(git -C "$REMOVE_CHECKOUT" rev-parse HEAD)
}
merged() {
	[[ ! -e $REMOVE_CHECKOUT && -f $REMOVE_REPO/feature ]]
	if branch_exists; then exit 1; fi
	closed
}
for mode in Squash Normal 'Merge commit' 'Fast-forward only'; do
	merge_fixture "$mode"
	# Hostile defaults must not override the chosen mode.
	git -C "$REMOVE_REPO" config merge.ff false
	git -C "$REMOVE_REPO" config branch.main.mergeOptions '--squash --no-commit'
	MERGE_MODE=$mode run
	merged
	case $mode in
	Squash)
		[[ $(git -C "$REMOVE_REPO" log -1 --format=%s) == 'Squash merge feature/delete into main' ]]
		[[ $(git -C "$REMOVE_REPO" rev-parse HEAD^) == "$before" ]]
		[[ $(head -n1 "$T/menu-Merge type > ") == Squash ]]
		contains "$T/options-Merge type > " start:first
		;;
	Normal | 'Fast-forward only') [[ $(git -C "$REMOVE_REPO" rev-parse HEAD) == "$source_commit" ]] ;;
	'Merge commit') [[ $(git -C "$REMOVE_REPO" rev-parse HEAD^2) == "$source_commit" ]] ;;
	esac
done

for mode in Squash Normal 'Merge commit' 'Fast-forward only'; do
	merge_fixture "diverged-$mode"
	printf 'destination\n' >"$REMOVE_REPO/destination"
	git -C "$REMOVE_REPO" add destination
	git -C "$REMOVE_REPO" commit -qm destination
	if [[ $mode == 'Fast-forward only' ]]; then
		if EXPECT_RESOLUTION=1 MERGE_MODE=$mode run; then exit 1; fi
		[[ -d $REMOVE_CHECKOUT && -e $T/focused && ! -e $T/closed ]]
		branch_exists
	else
		MERGE_MODE=$mode run
		merged
	fi
done

merge_fixture edited
EDITED_MESSAGE='feat(scope): custom subject' run
merged
[[ $(git -C "$REMOVE_REPO" log -1 --format=%s) == 'feat(scope): custom subject' ]]

for stage in mode chooser edit; do
	merge_fixture "cancel-$stage"
	CANCEL_STAGE=$stage run
	no_removal
	[[ $(git -C "$REMOVE_REPO" rev-parse HEAD) == "$before" ]]
done

for mutation in source dest dirty; do
	merge_fixture "changed-$mutation"
	if MERGE_MUTATION=$mutation run; then exit 1; fi
	no_removal
done
for location in source dest; do
	for state in dirty MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD sequencer; do
		merge_fixture "$location-$state"
		path=$REMOVE_CHECKOUT
		[[ $location != dest ]] || path=$REMOVE_REPO
		case $state in
		dirty) printf dirty >"$path/untracked" ;;
		rebase-* | sequencer) mkdir "$(git -C "$path" rev-parse --path-format=absolute --git-path "$state")" ;;
		*) printf '%s\n' "$before" >"$(git -C "$path" rev-parse --path-format=absolute --git-path "$state")" ;;
		esac
		if run; then exit 1; fi
		no_removal
	done
done
merge_fixture locked
git -C "$REMOVE_REPO" worktree lock "$REMOVE_CHECKOUT"
if run; then exit 1; fi
no_removal

for mode in Squash Normal; do
	merge_fixture "conflict-$mode"
	printf source >"$REMOVE_CHECKOUT/tracked"
	git -C "$REMOVE_CHECKOUT" commit -qam source
	printf destination >"$REMOVE_REPO/tracked"
	git -C "$REMOVE_REPO" commit -qam destination
	if EXPECT_RESOLUTION=1 MERGE_MODE=$mode run; then exit 1; fi
	[[ -d $REMOVE_CHECKOUT && -e $T/focused && ! -e $T/closed ]]
	branch_exists
	[[ -n $(git -C "$REMOVE_REPO" ls-files -u) ]]
done
merge_fixture hook
printf '#!/bin/sh\nexit 1\n' >"$REMOVE_REPO/.git/hooks/pre-commit"
chmod +x "$REMOVE_REPO/.git/hooks/pre-commit"
if EXPECT_RESOLUTION=1 run; then exit 1; fi
[[ -d $REMOVE_CHECKOUT && -e $T/focused && ! -e $T/closed ]]
branch_exists
[[ $(git -C "$REMOVE_REPO" rev-parse HEAD) == "$before" ]]
[[ -n $(git -C "$REMOVE_REPO" diff --cached --name-only) ]]

merge_fixture already
git -C "$REMOVE_REPO" merge --ff-only feature/delete >/dev/null
run
merged
[[ $(git -C "$REMOVE_REPO" rev-parse HEAD) == "$source_commit" ]]

merge_fixture empty
git -C "$REMOVE_REPO" cherry-pick feature/delete >/dev/null
# Ensure cherry-pick differs from source even when timestamps coincide.
git -C "$REMOVE_REPO" commit --amend -qm 'different commit, same tree'
if EXPECT_RESOLUTION=1 run; then exit 1; fi
[[ -d $REMOVE_CHECKOUT && -e $T/focused ]]
branch_exists
contains "$T/error" 'Empty squash'

for failure in remove branch changed-dest changed-source; do
	merge_fixture "cleanup-$failure"
	case $failure in
	remove) export REMOVE_FAILURE=1 ;;
	branch) export BRANCH_DELETE_FAIL=1 ;;
	changed-dest) export DEST_CHANGE_AFTER_REMOVE=1 ;;
	changed-source)
		REMOVE_OTHER_COMMIT=$before
		export REMOVE_OTHER_COMMIT CHANGE_BRANCH_AFTER_REMOVE=1
		;;
	esac
	if run; then exit 1; fi
	[[ -f $REMOVE_REPO/feature && ! -e $T/closed ]]
	branch_exists
done

cat >"$T/codex" <<'CODEX'
#!/usr/bin/env bash
set -eu
[[ -z ${CODEX_NVIM_STATE_FILE:-} && -z ${CODEX_THREAD_ID:-} && -z ${HERDR_PANE_ID:-} ]]
printf '%s\n' "$@" >"$REMOVE_TEST_ROOT/codex-args"
cat >"$REMOVE_TEST_ROOT/codex-prompt"
while [[ $# -gt 0 ]]; do
	if [[ $1 == --output-last-message ]]; then output=$2; shift; fi
	shift
done
[[ ${CODEX_FAKE_WAIT:-0} != 1 ]] || sleep 30
[[ ${CODEX_FAKE_FAIL:-0} != 1 ]] || exit 1
if [[ ${CODEX_FAKE_INVALID:-0} == 1 ]]; then
	printf 'not a subject\n' >"$output"
else
	printf 'feat: generated subject\n' >"$output"
fi
CODEX
chmod +x "$T/codex"
for result in success failure invalid missing; do
	merge_fixture "codex-$result"
	export CODEX_REAL_BIN="$T/codex" GENERATE=1 CODEX_NVIM_STATE_FILE="$T/route" CODEX_THREAD_ID=inherited HERDR_PANE_ID=w1:p1
	: >"$T/route"
	case $result in failure) export CODEX_FAKE_FAIL=1 ;; invalid) export CODEX_FAKE_INVALID=1 ;; missing) export CODEX_REAL_BIN="$T/missing" ;; esac
	run
	merged
	[[ -e $T/route ]]
	if [[ $result == success ]]; then
		contains "$T/draft" 'feat: generated subject'
		contains "$T/codex-args" --ephemeral
		contains "$T/codex-args" read-only
		contains "$T/codex-args" 'approval_policy="never"'
		contains "$T/codex-prompt" 'feat: add feature'
		contains "$T/codex-prompt" '+feature'
	else
		contains "$T/draft" 'Squash merge feature/delete into main'
	fi
done
merge_fixture cancel-generation
CODEX_REAL_BIN="$T/codex" GENERATE=1 CODEX_FAKE_WAIT=1 run $'\e'
no_removal

# Generation and editing cancel before any Git mutation.
merge_fixture cancel-generation-control-c
CODEX_REAL_BIN="$T/codex" GENERATE=1 CODEX_FAKE_WAIT=1 run $'\003'
no_removal
merge_fixture generated-edited
CODEX_REAL_BIN="$T/codex" GENERATE=1 EDITED_MESSAGE='fix: revised generated subject' run
merged
[[ $(git -C "$REMOVE_REPO" log -1 --format=%s) == 'fix: revised generated subject' ]]
merge_fixture changed-after-generation
if CODEX_REAL_BIN="$T/codex" GENERATE=1 MERGE_MUTATION=dest run; then exit 1; fi
no_removal

merge_fixture detached-destination
git -C "$REMOVE_REPO" checkout -q --detach
if run; then exit 1; fi
no_removal
if grep -q '^Merge,' "$T/menu-Current worktree > "; then exit 1; fi

merge_fixture changed-before-cleanup
# The hook reads fixture variables at runtime.
# shellcheck disable=SC2016
printf '#!/bin/sh\ngit -C "$REMOVE_CHECKOUT" update-ref HEAD "$REMOVE_OTHER_COMMIT"\n' >"$REMOVE_REPO/.git/hooks/post-commit"
chmod +x "$REMOVE_REPO/.git/hooks/post-commit"
if REMOVE_OTHER_COMMIT=$before run; then exit 1; fi
[[ -d $REMOVE_CHECKOUT && ! -e $T/closed && -f $REMOVE_REPO/feature ]]
branch_exists
contains "$T/output" 'Merge completed'

# Resolve past the pane-closing wrapper without executing it.
mkdir -p "$T/wrapper" "$T/real"
cp "$ROOT/config/nvim/libexec/codex-herdr/codex" "$T/wrapper/codex"
cp "$T/codex" "$T/real/codex"
resolved=$(
    unset CODEX_REAL_BIN
    PATH="$T/wrapper:$T/real:/usr/bin:/bin"
    source "$ROOT/my-profile/scripts/herdr-sessionizer/merge.sh"
    merge_codex_bin
)
[[ $resolved == "$T/real/codex" ]]

merge_fixture popup-termination
status=0
HANGUP_ON_CLOSE=1 run || status=$?
[[ $status == 129 ]]
merged
printf 'Herdr worktree merge tests passed\n'
