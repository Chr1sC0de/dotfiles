# Agents, Tandem, and Neovim

## Agent backends

`:AgentBackend` (or `<leader>aB`) selects **OpenCode** or **Pi**. Use
`:AgentBackend opencode` / `:AgentBackend pi` to switch directly. Selection is
remembered per checkout; OpenCode is the default. Pi integration targets Pi
1.5+ (`agent_settled` and UI-prompt lifecycle events).

Existing `:OpenCode…` commands and `<leader>a…` mappings operate on the selected
backend. Every legacy command has an `Agent…` alias, including `:AgentChat`, `:AgentChatNew`, `:AgentSessions`,
`:AgentJobs`, `:AgentEphemeralModel`, and `:AgentHealth`. Session and job rows identify their backend.
Opening a session selects its backend; explicitly targeted sends use that
buffer's backend. Switching preserves both terminal processes and input drafts,
and restores each backend's last live conversation. Native session IDs are
remembered for restart/resume once the lifecycle bridge has reported them.
`:AgentChatNew` always starts a fresh conversation.

Background queries, edits, continuations, promotion, titles and commit-message
generation use the owning backend. Switching does not redirect pending prompts,
model choices, or running jobs. Follow-ups stay on their original backend.
Model preferences/catalogs and remembered Herdr attachments are separate.
The shared Lua namespace is `agents` (`selection.lua` owns project selection);
backend-specific plugins retain explicit names. Legacy state directories and
transport environment variables are intentionally unchanged to preserve existing
preferences, attachments, and native session IDs.

`<leader>am` / `:AgentEphemeralModel [query|edit|commit]` configures background
models for the selected backend, not the model of a running interactive chat.
Use the native CLI model picker for interactive chats. IDs are not translated
between catalogs. Stale model pickers are ignored after a backend/project switch.

Both CLIs retain their native configuration and credentials; no credentials
are copied between them.

Pi uses its native terminal UI, JSON print mode for jobs, and a repository-owned
status extension. Its `bash` tool invokes the same Tandem CLI with the same
editor/root environment and revision-aware editing contract. Query restrictions
remain instruction-only. Text generation disables tools, MCP and extension
discovery. Inside Herdr, Pi uses native `--kind pi` managed panes and the same
detach/reattach workflow. External agents do not acquire Tandem retroactively.

After updating these Lua modules, restart Neovim to load the new command and
adapters. Future backend switches require no restart. Use `:AgentHealth` and
`:TandemStatus` for launch/registration issues. An unavailable CLI fails the
switch rather than silently using the other backend.

## Development setup

Install OpenCode V2 (tested with 2.1.4), Neovim 0.12+, and Cargo.
Link `config/nvim` using the dotfiles installer, then:

```sh
bash utils/install-tandem.sh
# Override the pinned Git revision if needed:
TANDEM_REF=COMMIT_OR_TAG bash utils/install-tandem.sh
# Or install from a local development checkout:
TANDEM_SOURCE=/path/to/tandem bash utils/install-tandem.sh
```

The installer defaults to [Chr1sC0de/tandem](https://github.com/Chr1sC0de/tandem),
pinned to the commit in `utils/install-tandem.sh`. `TANDEM_SOURCE` takes precedence
over `TANDEM_REF` when set. Cargo installs into its normal
binary directory (`$HOME/.cargo/bin` by default). Put that directory on PATH,
or set `TANDEM_BIN` to the absolute installed executable before starting Neovim.

Neovim startup registers its built-in RPC socket with Tandem asynchronously.
No companion editor plugin or MCP server is needed. Registration retries with
backoff after failures or daemon restarts. Run `:TandemStatus` and
`:OpenCodeHealth` to inspect readiness. Launches fail closed until registration
succeeds, or if their cwd/target is outside the registered workspace.

For custom startup options, configure `require("agents.tandem").setup({...})`
in `init.lua`: `root`, `command`, `state_home`, `interval_ms`, and
`backoff_cap_ms` are supported. The root defaults to Neovim's startup cwd and
stays fixed; open another Neovim process for another workspace.

## Editing contract

Managed OpenCode chats and background jobs use `--standalone` with launch-local
configuration. Host instructions, provider credentials, and model settings
still load normally. The OpenCode plugin only forwards lifecycle notifications
to Neovim; it does not supply tools or modify the tool registry.

Agents invoke the CLI directly through OpenCode's built-in shell, using `TANDEM_BIN`,
`TANDEM_ROOT`, and an explicit `TANDEM_EDITOR` for the originating Neovim.
The launcher supplies those environment variables to the private OpenCode
process, including `XDG_STATE_HOME` when a custom state directory is configured.
Guidance in `config/nvim/opencode-instructions/` explains Tandem's editing
contract and the session's analysis or text-generation mode.

```sh
"$TANDEM_BIN" buffers
"$TANDEM_BIN" read src/main.rs
"$TANDEM_BIN" write src/main.rs --expect REVISION --content-file - <<'CONTENT'
full replacement text
CONTENT
"$TANDEM_BIN" read --buffer 12
"$TANDEM_BIN" outcome ATTEMPT_ID
"$TANDEM_BIN" status
```

Reads see live, unsaved text. Writes use the returned opaque revision token;
compatible concurrent changes merge, while overlapping changes return
`merge_conflict` without modifying the buffer. On conflicts or expired
snapshots, reread and reconsider the edit. For `outcome_unknown`, query the
attempt and inspect the buffer; never blindly replay the write.

With conditional autosave, writes save named buffers only when they were clean
at read time and remain unchanged before application. Normal formatting and save
hooks run, including Conform. Existing or concurrent drafts remain unsaved;
agents must not separately save these without authorization. Check `saved` and
`save_error` in the result. Filesystem tools and Git see saved content only.
Reading a path loads its Neovim buffer if needed.

The pinned GitHub revision includes conditional autosave. After upgrading,
restart the workspace's Tandem daemon to load the updated bridge.

Coding and analysis sessions use OpenCode's native tools with normal filesystem
and network access, including builds, Git, package installs, and Docker.
Managed launches allow tool permissions without approval prompts, subject to
inherited policies and agent-specific restrictions. Prefer Tandem for source
reads and edits to coordinate with live Neovim buffers.

Query sessions receive analysis-only instructions: do not modify files **or
buffers**. This restriction is instruction-only, not a security boundary;
tools retain normal filesystem and network access. Text-generation jobs
remain tool-free through a tool-deny policy.

Tandem currently supports UTF-8 Unix text buffers up to 1 MiB and rejects final
newline changes. Its snapshots expire on daemon restart. There is no automatic
cross-editor synchronization or filesystem interception. After registration
recovery, launch a fresh managed session if its editor ID is no longer valid;
never automatically select a different editor.
The rewrite's resource and recovery guarantees are still incomplete; consult
its README for current limitations rather than assuming full specification compliance.

## Jobs and Herdr

Existing `:OpenCodeChat`, query/edit commands, jobs panel, model selection, and
`<leader>a…` mappings retain their actions. Non-file buffers remain reference
context rather than editable file targets. Result follow-ups resume the native
OpenCode session; query-to-edit promotion creates a fresh editable session with
historical discussion. Text generation remains tool-free.

Inside Herdr, managed chats use sibling agent panes and Neovim terminal
attachment. Hiding/detaching leaves the backing agent alive; explicit deletion
closes its pane. Route files support notification reattachment.
`:OpenCodeChatResync` repairs routing. Outside Herdr, chats use direct terminals.
External attachments do not acquire Tandem configuration. Worktree-only agent
launches remain independent; launch from that worktree's Neovim for buffer access.

## Verification

```sh
export XDG_STATE_HOME="$(mktemp -d /tmp/opencode/nvim-test-state.XXXXXX)"
for test_file in tests/*_spec.lua; do
  nvim --headless -u NONE -i NONE -l "$test_file" || exit
done
nvim --headless -u NONE -i NONE -l config/nvim/tests/opencode_commit_test.lua
for test_file in tests/opencode*_spec.sh; do bash "$test_file" || exit; done
python3 -B tests/tandem_integration.py
AGENT_TEST_BACKEND=pi python3 -B tests/tandem_integration.py
```

The integration test uses real OpenCode, CLI, daemon, Neovim RPC, and Conform.
Only model responses come from a deterministic local HTTP fixture. It checks
CLI-backed edits, live draft merging, unchanged disk content, formatting on
explicit save, query instructions, promotion, continuation, and text generation.
Evidence is written to `artifacts/tandem/`.

Override `TANDEM_BIN`, `TANDEM_CONFORM`, or `TANDEM_EVIDENCE_DIR` as needed.
`TANDEM_TEST_TMPDIR` defaults to `/tmp/opencode`. Inside Herdr, the opt-in
`python3 -B tests/opencode_herdr_smoke.py` exercises owned live terminal panes.
`python3 -B tests/pi_herdr_smoke.py` checks real managed Pi startup and detection
without sending a model request. Lifecycle cleanup uses a backend-neutral
parent script because Herdr inspects the entire foreground process group.

CI runs regression suites and real Tandem integration tests on Ubuntu 22.04
and 24.04 using the installer's pinned GitHub revision. The manual workflow's
`tandem_ref` input can override that revision.

After upgrading an existing installation, Lazy's clean operation can remove
the retired companion checkout. The old CLI under Neovim's data directory is
no longer used; remove it manually only after checking it contains no wanted work.
