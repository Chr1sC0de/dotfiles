#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

cat >"${test_dir}/codex-real" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${CODEX_TEST_ARGS}"
cat >"${CODEX_TEST_STDIN}"
if [ "${CODEX_TEST_SIGNAL:-}" = "TERM" ]; then
	kill -TERM "$$"
fi
printf 'captured stdout\n'
printf 'captured stderr\n' >&2
exit "${CODEX_TEST_EXIT:-0}"
SH

cat >"${test_dir}/herdr-fake" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${CODEX_TEST_HERDR_CALLS}"
SH

chmod +x "${test_dir}/codex-real" "${test_dir}/herdr-fake"

runner="config/nvim/libexec/codex-herdr/ephemeral"

run_case() {
	local expected_status="$1"
	local codex_status="${2:-0}"
	local signal="${3:-}"
	local prompt_file="${test_dir}/prompt"
	local stdout_file="${test_dir}/stdout"
	local stderr_file="${test_dir}/stderr"
	local status_file="${test_dir}/status"
	local args_file="${test_dir}/args"
	local stdin_file="${test_dir}/stdin"
	local calls_file="${test_dir}/calls"
	printf 'Please inspect this file.\n' >"${prompt_file}"
	: >"${calls_file}"
	rm -f -- "${stdout_file}" "${stderr_file}" "${status_file}"

	set +e
	CODEX_REAL_BIN="${test_dir}/codex-real" \
		CODEX_HERDR_BIN="${test_dir}/herdr-fake" \
		CODEX_EPHEMERAL_PROMPT_PATH="${prompt_file}" \
		CODEX_EPHEMERAL_STDOUT_PATH="${stdout_file}" \
		CODEX_EPHEMERAL_STDERR_PATH="${stderr_file}" \
		CODEX_EPHEMERAL_STATUS_PATH="${status_file}" \
		CODEX_EPHEMERAL_SANDBOX="read-only" \
		CODEX_EPHEMERAL_MODEL="gpt-test" \
		CODEX_EPHEMERAL_REASONING_EFFORT="low" \
		CODEX_TEST_ARGS="${args_file}" \
		CODEX_TEST_STDIN="${stdin_file}" \
		CODEX_TEST_EXIT="${codex_status}" \
		CODEX_TEST_HERDR_CALLS="${calls_file}" \
		CODEX_TEST_SIGNAL="${signal}" \
		HERDR_TAB_ID="w1:t9" \
		"${runner}"
	local actual_status=$?
	set -e

	[ "${actual_status}" -eq "${expected_status}" ]
	[ "$(cat "${status_file}")" -eq "${expected_status}" ]
	cmp -s "${prompt_file}" "${stdin_file}"
	[ "$(wc -l <"${calls_file}")" -eq 1 ]
	grep -Fx -- "tab close w1:t9" "${calls_file}" >/dev/null
	grep -Fx -- "exec" "${args_file}" >/dev/null
	grep -Fx -- "--ephemeral" "${args_file}" >/dev/null
	grep -Fx -- "--sandbox" "${args_file}" >/dev/null
	grep -Fx -- "read-only" "${args_file}" >/dev/null
	grep -Fx -- "--model" "${args_file}" >/dev/null
	grep -Fx -- "gpt-test" "${args_file}" >/dev/null
	grep -Fx -- 'model_reasoning_effort="low"' "${args_file}" >/dev/null

	if [ -z "${signal}" ]; then
		grep -Fx -- "captured stdout" "${stdout_file}" >/dev/null
		grep -Fx -- "captured stderr" "${stderr_file}" >/dev/null
	fi
}

run_case 0
run_case 23 23
run_case 143 0 TERM

printf '%s\n' "codex_herdr_ephemeral_spec.sh: ok"
