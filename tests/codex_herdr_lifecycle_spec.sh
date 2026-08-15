#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

cat >"${test_dir}/codex-real" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${CODEX_TEST_ARGS}"
if [ "${CODEX_TEST_SIGNAL:-}" = "TERM" ]; then
	kill -TERM "$$"
fi
exit "${CODEX_TEST_EXIT:-0}"
SH

cat >"${test_dir}/herdr-fake" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CODEX_TEST_HERDR_CALLS}"
SH

chmod +x "${test_dir}/codex-real" "${test_dir}/herdr-fake"

wrapper="config/nvim/libexec/codex-herdr/codex"

run_case() {
	local expected_status="$1"
	local codex_status="${2:-0}"
	local signal="${3:-}"
	local route_file="${test_dir}/route"
	local args_file="${test_dir}/args"
	local calls_file="${test_dir}/calls"
	: >"${route_file}"
	: >"${calls_file}"

	set +e
	CODEX_REAL_BIN="${test_dir}/codex-real" \
		CODEX_HERDR_BIN="${test_dir}/herdr-fake" \
		CODEX_NVIM_STATE_FILE="${route_file}" \
		CODEX_TEST_ARGS="${args_file}" \
		CODEX_TEST_EXIT="${codex_status}" \
		CODEX_TEST_HERDR_CALLS="${calls_file}" \
		CODEX_TEST_SIGNAL="${signal}" \
		HERDR_PANE_ID="w1:p9" \
		"${wrapper}" --cd "/tmp/project with spaces"
	local actual_status=$?
	set -e

	[ "${actual_status}" -eq "${expected_status}" ]
	[ ! -e "${route_file}" ]
	[ "$(wc -l <"${calls_file}")" -eq 1 ]
	grep -Fx -- "pane close w1:p9" "${calls_file}" >/dev/null
	grep -Fx -- "--cd" "${args_file}" >/dev/null
	grep -Fx -- "/tmp/project with spaces" "${args_file}" >/dev/null
}

run_case 0
run_case 23 23
run_case 143 0 TERM

printf '%s\n' "codex_herdr_lifecycle_spec.sh: ok"
