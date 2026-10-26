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
			printf 'Generate with OpenCode\n'
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
		BRANCH_DELETE_FAIL DEST_CHANGE_AFTER_REMOVE OPENCODE_REAL_BIN OPENCODE_FAKE_RESULT OPENCODE_FAKE_WAIT \
		OPENCODE_NVIM_STATE_FILE OPENCODE_THREAD_ID OPENCODE_CONFIG_CONTENT
	rm -f "$T/generated" "$T/draft" "$T/opencode-args" "$T/opencode-prompt"
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

cat >"$T/opencode" <<'OPENCODE'
#!/usr/bin/env bash
set -eu
[[ -z ${OPENCODE_NVIM_STATE_FILE:-} && -z ${OPENCODE_THREAD_ID:-} && -z ${HERDR_PANE_ID:-} ]]
[[ $PWD == "$REMOVE_REPO" ]]
printf '%s\n' "$@" >"$REMOVE_TEST_ROOT/opencode-args"
printf '%s\n' "$OPENCODE_CONFIG_CONTENT" >"$REMOVE_TEST_ROOT/opencode-config"
jq -e '.policies == [{action:"tool.use",resource:"*",effect:"deny"}] and (has("mcp") | not) and (has("plugins") | not)' \
	"$REMOVE_TEST_ROOT/opencode-config" >/dev/null
cat >"$REMOVE_TEST_ROOT/opencode-prompt"
[[ ${OPENCODE_FAKE_WAIT:-0} != 1 ]] || sleep 30
case ${OPENCODE_FAKE_RESULT:-success} in
failure) exit 1 ;;
invalid) printf '{"type":"text","part":{"text":"not a subject"}}\n' ;;
error) printf '{"type":"text","part":{"text":"feat: partial subject"}}\n{"type":"error","error":{"message":"failed"}}\n' ;;
malformed) printf 'not json\n' ;;
empty) printf '{"type":"step_finish"}\n' ;;
multiline) printf '{"type":"text","part":{"text":"feat: subject\\nextra line"}}\n' ;;
*) printf '{"type":"step_start"}\n{"type":"text","part":{"text":"feat: generated subject"}}\n{"type":"step_finish"}\n' ;;
esac
OPENCODE
chmod +x "$T/opencode"
for result in success failure invalid missing error malformed empty multiline; do
	merge_fixture "opencode-$result"
	export OPENCODE_REAL_BIN="$T/opencode" GENERATE=1 OPENCODE_NVIM_STATE_FILE="$T/route" OPENCODE_THREAD_ID=inherited HERDR_PANE_ID=w1:p1
	export OPENCODE_CONFIG_CONTENT='{"model":"test/model","plugins":[{"package":"inherited"}],"mcp":{"servers":{"tandem":{}}},"policies":[{"action":"tool.use","resource":"*","effect":"allow"}]}'
	: >"$T/route"
	if [[ $result == missing ]]; then export OPENCODE_REAL_BIN="$T/missing"; else export OPENCODE_FAKE_RESULT=$result; fi
	run
	merged
	[[ -e $T/route ]]
	if [[ $result == success ]]; then
		contains "$T/draft" 'feat: generated subject'
		[[ $(cat "$T/opencode-args") == $'run\n--standalone\n--format\njson' ]]
		jq -e '.model == "test/model"' "$T/opencode-config" >/dev/null
		contains "$T/opencode-prompt" 'feat: add feature'
		contains "$T/opencode-prompt" '+feature'
	else
		contains "$T/draft" 'Squash merge feature/delete into main'
	fi
done
merge_fixture cancel-generation
OPENCODE_REAL_BIN="$T/opencode" GENERATE=1 OPENCODE_FAKE_WAIT=1 run $'\e'
no_removal

# Generation and editing cancel before any Git mutation.
merge_fixture cancel-generation-control-c
OPENCODE_REAL_BIN="$T/opencode" GENERATE=1 OPENCODE_FAKE_WAIT=1 run $'\003'
no_removal
merge_fixture generated-edited
OPENCODE_REAL_BIN="$T/opencode" GENERATE=1 EDITED_MESSAGE='fix: revised generated subject' run
merged
[[ $(git -C "$REMOVE_REPO" log -1 --format=%s) == 'fix: revised generated subject' ]]
merge_fixture changed-after-generation
if OPENCODE_REAL_BIN="$T/opencode" GENERATE=1 MERGE_MUTATION=dest run; then exit 1; fi
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
cat >"$T/wrapper/opencode" <<'SH'
#!/bin/sh
# OPENCODE_REAL_BIN
# pane close
exit 99
SH
chmod +x "$T/wrapper/opencode"
cp "$T/opencode" "$T/real/opencode"
resolved=$(
	unset OPENCODE_REAL_BIN
	PATH="$T/wrapper:$T/real:/usr/bin:/bin"
	source "$ROOT/my-profile/scripts/herdr-sessionizer/merge.sh"
	merge_opencode_bin
)
[[ $resolved == "$T/real/opencode" ]]

merge_fixture popup-termination
status=0
HANGUP_ON_CLOSE=1 run || status=$?
[[ $status == 129 ]]
merged
printf 'Herdr worktree merge tests passed\n'
