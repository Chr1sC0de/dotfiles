#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat >"$test_dir/workmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MUX_HOOK_TEST_OUTPUT"
SH
chmod +x "$test_dir/workmux"

hook="config/nvim/bin/codex-mux-status-hook"
output="$test_dir/output"

env -u HERDR_ENV PATH="$test_dir:$PATH" MUX_HOOK_TEST_OUTPUT="$output" TMUX="tmux" "$hook" working
grep -Fx -- "set-window-status working" "$output" >/dev/null

: >"$output"
PATH="$test_dir:$PATH" MUX_HOOK_TEST_OUTPUT="$output" HERDR_ENV=1 TMUX="tmux" "$hook" "done"
test ! -s "$output"

env -u HERDR_ENV -u TMUX PATH="$test_dir:$PATH" MUX_HOOK_TEST_OUTPUT="$output" "$hook" waiting
env -u HERDR_ENV PATH="$test_dir:$PATH" MUX_HOOK_TEST_OUTPUT="$output" TMUX="tmux" "$hook" invalid
test ! -s "$output"

printf '%s\n' "codex_mux_status_hook_spec.sh: ok"
