#!/usr/bin/env bash
set -euo pipefail

# Mock only the executable boundary, so this regression needs no temp files
# or running Herdr server. Any ANSI-stripping filter fails the test.
# shellcheck disable=SC2329
herdr() {
	[[ "$*" == 'pane read w1:p9 --source visible --format ansi --raw' ]] || return 99
	printf '\033[48;2;20;30;40mfirst row extends\033[0m\r\n🙂abcdef\r\n'
	return "${HERDR_PREVIEW_EXIT:-0}"
}
# shellcheck disable=SC2329
exec() { "$@"; }
# shellcheck disable=SC2329
bat() { return 99; }
# shellcheck disable=SC2329
colrm() { return 99; }
export -f herdr exec bat colrm
helper="config/nvim/bin/herdr-pane-preview"
expected=$'\033[48;2;20;30;40mfirst row extends\033[0m\r\n🙂abcdef\r'
actual=$(bash "$helper" w1:p9 6)
[[ $actual == "$expected" ]]

status=0
HERDR_PREVIEW_EXIT=23 bash "$helper" w1:p9 6 >/dev/null || status=$?
[[ $status == 23 ]]
for width in 0 1 bad; do
	status=0
	bash "$helper" w1:p9 "$width" >/dev/null 2>&1 || status=$?
	[[ $status == 2 ]]
done
printf '%s\n' 'herdr_pane_preview_spec.sh: ok'
