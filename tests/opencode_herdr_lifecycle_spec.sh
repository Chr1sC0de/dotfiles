#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

cat >"${test_dir}/opencode-real" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${OPENCODE_TEST_ARGS}"
if [ "${OPENCODE_TEST_SIGNAL:-}" = "TERM" ]; then
	kill -TERM "$$"
fi
exit "${OPENCODE_TEST_EXIT:-0}"
SH

cat >"${test_dir}/herdr-fake" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${OPENCODE_TEST_HERDR_CALLS}"
SH

chmod +x "${test_dir}/opencode-real" "${test_dir}/herdr-fake"

wrapper="config/nvim/libexec/opencode-herdr/opencode"

run_case() {
	local expected_status="$1"
	local opencode_status="${2:-0}"
	local signal="${3:-}"
	local route_file="${test_dir}/route"
	local args_file="${test_dir}/args"
	local calls_file="${test_dir}/calls"
	: >"${route_file}"
	: >"${route_file}.launch.json"
	: >"${calls_file}"

	set +e
	OPENCODE_REAL_BIN="${test_dir}/opencode-real" \
		OPENCODE_HERDR_BIN="${test_dir}/herdr-fake" \
		OPENCODE_NVIM_STATE_FILE="${route_file}" \
		OPENCODE_TEST_ARGS="${args_file}" \
		OPENCODE_TEST_EXIT="${opencode_status}" \
		OPENCODE_TEST_HERDR_CALLS="${calls_file}" \
		OPENCODE_TEST_SIGNAL="${signal}" \
		HERDR_PANE_ID="w1:p9" \
		"${wrapper}" --cd "/tmp/project with spaces"
	local actual_status=$?
	set -e

	[ "${actual_status}" -eq "${expected_status}" ]
	[ ! -e "${route_file}" ]
	[ ! -e "${route_file}.launch.json" ]
	[ "$(wc -l <"${calls_file}")" -eq 1 ]
	grep -Fx -- "pane close w1:p9" "${calls_file}" >/dev/null
	grep -Fx -- "--cd" "${args_file}" >/dev/null
	grep -Fx -- "/tmp/project with spaces" "${args_file}" >/dev/null
}

run_case 0
run_case 23 23
run_case 143 0 TERM

printf '%s\n' "opencode_herdr_lifecycle_spec.sh: ok"
