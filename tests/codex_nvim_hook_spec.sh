#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat >"$test_dir/nvim" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$CODEX_HOOK_TEST_OUTPUT"
SH
chmod +x "$test_dir/nvim"

route_file="$test_dir/chat.route"
printf '%s\n' "/tmp/codex-state.sock" "77" "state-token" >"$route_file"
chmod 600 "$route_file"

payload='{"hook_event_name":"Stop"}'
expected="$(printf '%s\n%s\n%s' "77" "state-token" "$payload" | base64 -w 0)"

PATH="$test_dir:$PATH" \
	CODEX_HOOK_TEST_OUTPUT="$test_dir/output" \
	CODEX_NVIM_STATE_FILE="$route_file" \
	CODEX_NVIM_SERVER="/tmp/wrong.sock" \
	CODEX_NVIM_SESSION_ID="1" \
	CODEX_NVIM_HOOK_TOKEN="wrong-token" \
	config/nvim/bin/codex-nvim-hook <<<"$payload"

grep -F -- "--server /tmp/codex-state.sock" "$test_dir/output" >/dev/null
grep -F -- "$expected" "$test_dir/output" >/dev/null

printf '%s\n' "codex_nvim_hook_spec.sh: ok"
