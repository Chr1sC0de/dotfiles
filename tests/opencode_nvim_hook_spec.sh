#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat >"$test_dir/nvim" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$OPENCODE_HOOK_TEST_OUTPUT"
SH
chmod +x "$test_dir/nvim"

route_file="$test_dir/chat.route"
printf '%s\n' "/tmp/opencode-state.sock" "77" "state-token" >"$route_file"
chmod 600 "$route_file"

payload='{"hook_event_name":"Stop"}'
expected="$(printf '%s\n%s\n%s' "77" "state-token" "$payload" | base64 -w 0)"

PATH="$test_dir:$PATH" \
	OPENCODE_HOOK_TEST_OUTPUT="$test_dir/output" \
	OPENCODE_NVIM_STATE_FILE="$route_file" \
	OPENCODE_NVIM_SERVER="/tmp/wrong.sock" \
	OPENCODE_NVIM_SESSION_ID="1" \
	OPENCODE_NVIM_HOOK_TOKEN="wrong-token" \
	config/nvim/bin/opencode-nvim-hook <<<"$payload"

grep -F -- "--server /tmp/opencode-state.sock" "$test_dir/output" >/dev/null
grep -F -- "$expected" "$test_dir/output" >/dev/null

printf '%s\n' "opencode_nvim_hook_spec.sh: ok"
