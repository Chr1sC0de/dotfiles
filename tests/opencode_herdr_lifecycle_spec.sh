#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

cat >"${test_dir}/opencode-real" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${OPENCODE_TEST_ARGS}"
ps -o args= -p "$PPID" >"${OPENCODE_TEST_PARENT}"
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
		PI_REAL_BIN="${test_dir}/opencode-real" \
		OPENCODE_HERDR_BIN="${test_dir}/herdr-fake" \
		OPENCODE_NVIM_STATE_FILE="${route_file}" \
		OPENCODE_TEST_ARGS="${args_file}" \
		OPENCODE_TEST_PARENT="${test_dir}/parent" \
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
	if [ "${wrapper##*/}" = pi ]; then
		# Herdr inspects the whole foreground process group. A long-lived shell
		# running a script named opencode makes a real Pi child look like OpenCode.
		if grep -Eq '/opencode([[:space:]]|$)' "${test_dir}/parent"; then
			printf 'Pi has an OpenCode-named foreground wrapper: %s\n' "$(cat "${test_dir}/parent")" >&2
			return 1
		fi
	fi
}

for wrapper in config/nvim/libexec/opencode-herdr/{opencode,pi}; do
	run_case 0
	run_case 23 23
	run_case 143 0 TERM
done

# Pi invoked from an OpenCode shell must bypass lifecycle cleanup entirely.
cp "${test_dir}/opencode-real" "${test_dir}/pi"
: >"${test_dir}/route"
: >"${test_dir}/calls"
env -u PI_REAL_BIN PATH="${PWD}/config/nvim/libexec/opencode-herdr:${test_dir}:${PATH}" \
	OPENCODE_TEST_ARGS="${test_dir}/args" OPENCODE_TEST_HERDR_CALLS="${test_dir}/calls" \
	OPENCODE_TEST_PARENT="${test_dir}/parent" \
	OPENCODE_NVIM_STATE_FILE="${test_dir}/route" HERDR_PANE_ID="w1:p9" \
	config/nvim/libexec/opencode-herdr/pi --version
[ -e "${test_dir}/route" ]
[ ! -s "${test_dir}/calls" ]
grep -Fx -- "--version" "${test_dir}/args" >/dev/null

printf '%s\n' "opencode_herdr_lifecycle_spec.sh: ok"
