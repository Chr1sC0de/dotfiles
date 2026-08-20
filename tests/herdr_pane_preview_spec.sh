#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

cat >"${test_dir}/herdr" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"${HERDR_PREVIEW_CALLS}"
printf 'first row extends\r\n🙂abcdef\r\n'
exit "${HERDR_PREVIEW_EXIT:-0}"
SH

cat >"${test_dir}/bat" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"${HERDR_PREVIEW_BAT_ARGS}"
printf '\033[31m'
/bin/cat
printf '\033[0m'
SH

cat >"${test_dir}/cat" <<'SH'
#!/bin/sh
printf '%s\n' called >"${HERDR_PREVIEW_CAT_CALLS}"
/bin/cat
SH

cat >"${test_dir}/colrm" <<'SH'
#!/bin/sh
exec /usr/bin/colrm "$@"
SH

chmod +x "${test_dir}/herdr" "${test_dir}/bat" "${test_dir}/cat" "${test_dir}/colrm"

helper="config/nvim/bin/herdr-pane-preview"
expected="${test_dir}/expected"
printf 'first\n🙂abc\n' >"${expected}"
expected_bat="${test_dir}/expected-bat"
printf '\033[31mfirst\n🙂abc\n\033[0m' >"${expected_bat}"

HERDR_PREVIEW_CALLS="${test_dir}/herdr-calls" \
HERDR_PREVIEW_BAT_ARGS="${test_dir}/bat-args" \
PATH="${test_dir}" \
/bin/bash "${helper}" "w1:p9" 6 >"${test_dir}/bat-output"

/usr/bin/cmp "${expected_bat}" "${test_dir}/bat-output"
/bin/grep -Fx -- "pane read w1:p9 --source visible --format text --raw" "${test_dir}/herdr-calls" >/dev/null
/bin/grep -Fx -- "--style=plain --paging=never --color=always --wrap=never --language=txt" "${test_dir}/bat-args" >/dev/null

/bin/mv "${test_dir}/bat" "${test_dir}/bat.disabled"
HERDR_PREVIEW_CALLS="${test_dir}/herdr-calls" \
HERDR_PREVIEW_CAT_CALLS="${test_dir}/cat-calls" \
PATH="${test_dir}" \
/bin/bash "${helper}" "w1:p9" 6 >"${test_dir}/cat-output"

/usr/bin/cmp "${expected}" "${test_dir}/cat-output"
/bin/grep -Fx -- called "${test_dir}/cat-calls" >/dev/null

set +e
HERDR_PREVIEW_CALLS="${test_dir}/herdr-calls" \
HERDR_PREVIEW_CAT_CALLS="${test_dir}/cat-calls" \
HERDR_PREVIEW_EXIT=23 \
PATH="${test_dir}" \
/bin/bash "${helper}" "w1:p9" 6 >/dev/null
status=$?
set -e
[ "${status}" -eq 23 ]

printf '%s\n' "herdr_pane_preview_spec.sh: ok"
