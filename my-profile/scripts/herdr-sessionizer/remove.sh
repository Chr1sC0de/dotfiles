#!/usr/bin/env bash
# Loaded by picker.sh; uses its temporary directory and error cleanup.

remove_confirm() {
	local expected=$1 message=$2 answer='' char
	printf '\n%s\nType exactly: %s\n> ' "$message" "$expected" >&2
	while IFS= read -rsn1 char; do
		case $char in
		$'\e' | $'\003')
			printf '\n' >&2
			return 1
			;;
		'')
			printf '\n' >&2
			[[ $answer == "$expected" ]]
			return
			;;
		$'\177' | $'\b')
			if [[ -n $answer ]]; then
				answer=${answer%?}
				printf '\b \b' >&2
			fi
			;;
		*)
			answer+=$char
			printf '%s' "$char" >&2
			;;
		esac
	done
	printf '\n' >&2
	return 1
}

remove_workspace() {
	herdr workspace get "$remove_workspace_id" >"$TMP/workspace" ||
		fail 'Cannot read the current Herdr workspace.'
	jq -ce --arg id "$remove_workspace_id" '
        .result.workspace | select(.workspace_id == $id) |
        select(.worktree.is_linked_worktree == true) |
        select((.worktree.checkout_path | type) == "string")' "$TMP/workspace" ||
		fail 'The current workspace is not a linked Herdr worktree.'
}

remove_revalidate() {
	local latest current_ref current_commit
	latest=$(remove_workspace) || exit 1
	[[ $(jq -Sc '.worktree' <<<"$latest") == "$remove_membership" ]] ||
		fail 'Workspace checkout changed; reopen the deletion menu.'
	current_ref=$(git -C "$remove_path" symbolic-ref -q HEAD) || current_ref=''
	current_commit=$(git -C "$remove_path" rev-parse --verify HEAD) ||
		fail 'Cannot recheck the checkout commit.'
	[[ $current_ref == "$remove_ref" && $current_commit == "$remove_commit" ]] ||
		fail 'Checkout branch or commit changed; reopen the deletion menu.'
}

remove_branch_unchanged() {
	local commit
	commit=$(git --git-dir="$remove_common" rev-parse --verify "$remove_ref") ||
		fail "Checkout removed; cannot read local branch '$remove_branch'."
	[[ $commit == "$remove_commit" ]] ||
		fail "Checkout removed; branch '$remove_branch' changed and was kept."
}

# Called by picker.sh's EXIT cleanup after branch handling and temporary-file cleanup.
remove_focus_root() {
	local state rows id created common git_dir
	# The root must still be the primary checkout of the repository we removed from.
	common=$(repo_key "$REMOVE_PROJECT_ROOT") || return 1
	git_dir=$(git -C "$REMOVE_PROJECT_ROOT" rev-parse --absolute-git-dir) || return 1
	[[ $common == "$REMOVE_PROJECT_COMMON" && $git_dir == "$common" ]] || return 1
	state=$(herdr api snapshot) || return 1
	jq -e '.result.snapshot | [.workspaces, .layouts, .panes] | all(type == "array")' \
		<<<"$state" >/dev/null || return 1
	rows=$(workspaces <(printf '%s\n' "$state")) || return 1
	id=$(jq -rs --arg path "$REMOVE_PROJECT_ROOT" --arg removed "$REMOVE_WORKSPACE_TO_CLOSE" '
        [.[] | select(.path == $path and .workspace != $removed)][0].workspace // empty' \
		<<<"$rows") || return 1
	if [[ -z $id ]]; then
		created=$(herdr workspace create --cwd "$REMOVE_PROJECT_ROOT" --no-focus) || return 1
		id=$(jq -er '.result.workspace.workspace_id |
            select(type == "string" and length > 0)' <<<"$created") || return 1
	fi
	[[ $id != "$REMOVE_WORKSPACE_TO_CLOSE" ]] || return 1
	herdr workspace focus "$id" >/dev/null
}

remove_current() {
	local workspace label git_dir selection status remove_root
	local remove_workspace_id=${HERDR_ACTIVE_WORKSPACE_ID:-}
	local remove_membership remove_path remove_common remove_ref remove_commit remove_branch
	[[ ${HERDR_ENV:-} == 1 && -n $remove_workspace_id ]] ||
		fail 'Run remove-current from a Herdr popup with active workspace context.'
	workspace=$(remove_workspace) || exit 1
	remove_membership=$(jq -Sc '.worktree' <<<"$workspace")
	remove_path=$(jq -r '.worktree.checkout_path' <<<"$workspace")
	remove_path=$(git -C "$remove_path" rev-parse --show-toplevel) ||
		fail 'Cannot resolve the worktree checkout.'
	remove_common=$(git -C "$remove_path" rev-parse --path-format=absolute --git-common-dir) ||
		fail 'Cannot resolve the shared Git directory.'
	git_dir=$(git -C "$remove_path" rev-parse --absolute-git-dir) ||
		fail 'Cannot resolve the checkout Git directory.'
	[[ $git_dir != "$remove_common" ]] || fail 'The primary checkout cannot be removed.'
	remove_root=$(jq -er '.worktree.repo_root | select(type == "string" and length > 0)' <<<"$workspace") ||
		fail 'Cannot resolve the project root.'
	remove_root=$(git -C "$remove_root" rev-parse --show-toplevel) ||
		fail 'Cannot resolve the project root.'
	[[ $(repo_key "$remove_root") == "$remove_common" &&
	$(git -C "$remove_root" rev-parse --absolute-git-dir) == "$remove_common" ]] ||
		fail 'Project root is not the primary checkout of this repository.'
	remove_ref=$(git -C "$remove_path" symbolic-ref -q HEAD) || remove_ref=''
	remove_commit=$(git -C "$remove_path" rev-parse --verify HEAD) ||
		fail 'Cannot read the checkout commit.'
	remove_branch=${remove_ref#refs/heads/}
	[[ -z $remove_ref || $remove_ref == refs/heads/* ]] ||
		fail 'Checkout HEAD does not name a local branch.'
	label=$(jq -r '.label' <<<"$workspace")
	printf 'Workspace: %s\nCheckout: %s\nLocal branch: %s\n\nThis closes all panes in this worktree workspace.\n' \
		"$label" "$remove_path" "${remove_branch:-detached HEAD}" >"$TMP/remove-header"
	printf 'Cancel\nDelete checkout only\n' >"$TMP/remove-menu"
	[[ -z $remove_branch ]] || printf 'Delete checkout and local branch\n' >>"$TMP/remove-menu"
	status=0
	FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' SHELL=/bin/bash fzf \
		--layout=reverse --no-sort --no-multi --disabled \
		--prompt='Delete current worktree > ' --header="$(cat "$TMP/remove-header")" \
		--bind='esc:abort,ctrl-c:abort,start:first' \
		<"$TMP/remove-menu" >"$TMP/remove-selection" || status=$?
	case $status in 0) ;; 1 | 130) return 0 ;; *) fail "fzf failed (exit $status)." ;; esac
	selection=$(cat "$TMP/remove-selection")
	case $selection in
	'Delete checkout only') ;;
	'Delete checkout and local branch') [[ -n $remove_branch ]] || return 0 ;;
	*) return 0 ;;
	esac

	# Keep the popup alive until Git cleanup finishes, with its cwd outside the checkout.
	cd -- "$remove_common" || fail 'Cannot enter the shared Git directory.'
	remove_revalidate
	if ! git --git-dir="$remove_common" worktree remove -- "$remove_path" >"$TMP/remove-result" 2>"$TMP/remove-error"; then
		cat "$TMP/remove-error" >&2
		grep -Fq 'modified or untracked files' "$TMP/remove-error" ||
			fail 'Worktree removal failed; branch deletion was skipped.'
		git -C "$remove_path" status --short >&2 || true
		if ! remove_confirm "$remove_path" 'Discard modified and untracked files and force-remove this checkout?'; then
			printf 'Removal cancelled; checkout and branch kept.\n'
			return 0
		fi
		remove_revalidate
		git --git-dir="$remove_common" worktree remove --force -- "$remove_path" >"$TMP/remove-result" ||
			fail 'Forced worktree removal failed; branch deletion was skipped.'
	fi
	# Do not delete a branch or close the workspace if the checkout remains.
	[[ ! -e $remove_path ]] ||
		fail 'Checkout still exists after removal; branch deletion was skipped.'
	# picker.sh closes this workspace in its EXIT cleanup, after branch handling.
	# shellcheck disable=SC2034
	REMOVE_WORKSPACE_TO_CLOSE=$remove_workspace_id
	# shellcheck disable=SC2034
	REMOVE_PROJECT_ROOT=$remove_root
	# shellcheck disable=SC2034
	REMOVE_PROJECT_COMMON=$remove_common
	printf 'Removed checkout: %s\n' "$remove_path"
	[[ $selection == 'Delete checkout and local branch' ]] || return 0
	remove_branch_unchanged
	if git --git-dir="$remove_common" branch -d -- "$remove_branch" >"$TMP/branch-result" 2>"$TMP/branch-error"; then
		cat "$TMP/branch-result"
		return 0
	fi
	cat "$TMP/branch-error" >&2
	if ! grep -Fq 'not fully merged' "$TMP/branch-error"; then
		fail "Checkout removed; branch '$remove_branch' was kept because deletion failed."
	fi
	if ! remove_confirm "$remove_branch" 'Checkout removed. Force-delete this unmerged local branch?'; then
		printf "Checkout removed; local branch '%s' kept.\n" "$remove_branch"
		if [[ -t 0 && -t 2 ]]; then
			printf 'Press any key to close.' >&2
			read -rsn1 _ || true
		fi
		return 0
	fi
	remove_branch_unchanged
	git --git-dir="$remove_common" branch -D -- "$remove_branch" ||
		fail "Checkout removed; local branch '$remove_branch' could not be deleted."
}
