# OpenCode, Tandem, and Neovim

## Setup

The dotfiles installer links `config/nvim`. Install OpenCode **V2** (tested with
2.1.4), Neovim 0.12+, Cargo, and Linux Bubblewrap (`bwrap`). Lazy installs
`tandem.nvim` and builds the pinned Tandem CLI. Connect your model provider in
OpenCode normally. Run `:TandemStatus` and `:OpenCodeHealth` from the project.

The public commands now use `OpenCode`, for example `:OpenCodeChat`,
`:OpenCodeQueryFile`, `:OpenCodeEditSelection`, and `:OpenCodeJobs`.
Existing `<leader>a…` mappings retain their actions. Model selections use
`provider/model` or `provider/model#variant`; `<leader>am` opens the picker.

## Editing contract

Managed chats and background jobs use `--standalone` with launch-local
configuration. This keeps their Tandem connection and restrictions isolated
from other OpenCode clients. Global/project instructions, provider credentials,
and model configuration still load normally. The bridge adds Tandem guidance
without replacing host instructions.

The bundled V2 plugin waits for Tandem's MCP catalog before admitting prompts.
It exposes native reading/search tools, questions, and the Tandem tools.
Native edit/write/patch, unrestricted shells, subagents, and unrelated MCP
writers are excluded. A deny-by-default tool policy also blocks those actions
if the bridge fails to load.

`nvim_shell` preserves read-only shell inspection through Bubblewrap: host
mounts are read-only, network access is disabled, and no unsandboxed fallback
exists. Install your distribution's Bubblewrap/AppArmor prerequisites when
user namespaces are restricted. This is a shell sandbox, not a sandbox around
the whole OpenCode process; Tandem's authorized MCP writer runs separately.

Queries connect to `tandem mcp --read-only` and cannot access its writer.
Edits call `tandem_read_file`, then `tandem_write_file` with full updated content
and the returned revision. Unsaved human buffers block writes. Stale revisions
require a fresh read and regenerated edit. Writes pass through the editor's
normal synchronous formatting and save hooks, including Conform.

Launches fail when Tandem is disconnected or the cwd/target belongs to another
project. Open another Neovim process for another project. Non-file buffers
(terminal, help, results, Oil, scratch) are reference context: they support
queries and context sending, but are not file-edit targets.

## Jobs and commits

Queries and edits run independently in background `opencode run` processes.
The jobs panel retains progress, cancellation, source navigation, result tabs,
and follow-ups. `f` continues the same native OpenCode session with its original
model. The edit-follow-up action creates a fresh editable session containing
the selected discussion and historical context. Native session IDs persist in
OpenCode; Neovim's jobs/results remain local to the editor process.

Commit preparation, review, revision, and automatic commit retain their Git
snapshot checks. Titles, branch names, and commit subjects use tool-free model
generation and the same JSON output decoder.

## Herdr

Inside Herdr, a managed chat opens an OpenCode agent in a sibling pane, waits
for readiness, then attaches its terminal inside Neovim. The host pane regains
focus and zoom. Outside Herdr it uses a direct Neovim terminal.

Managed agents use the `nvim-opencode-td-` prefix and per-agent routing metadata.
Hiding/detaching or exiting Neovim leaves the backing agent alive. Reattachment
updates the route file, so notifications reach the new editor. Explicitly
deleting a managed chat closes its pane. The lifecycle wrapper closes the pane
when OpenCode exits, even while detached.

`<leader>aA`, `:OpenCodeChatAttach`, and `:AgentDashboard` browse Herdr agents.
OpenCode agents can be attached; other kinds can be navigated through the
dashboard. An externally launched agent remains external: attaching does not
retrofit Tandem or notification routing. The UI distinguishes it from managed
sessions. Worktree-only OpenCode launches are likewise independent; launch a
chat from the worktree's Neovim process for Tandem-coordinated editing.

Managed launches load `config/nvim/opencode-plugin/` automatically. No global
`hooks.json` is required. The bridge routes V2 events through
`bin/opencode-nvim-hook`; Herdr owns its native agent status, while the status
dispatcher supports Workmux inside tmux. `:OpenCodeChatResync` repairs routing.

## Verification

```sh
for test_file in tests/*_spec.lua; do
  nvim --headless -u NONE -i NONE -l "$test_file" || exit
done
nvim --headless -u NONE -i NONE -l config/nvim/tests/opencode_commit_test.lua
for test_file in tests/opencode*_spec.sh; do bash "$test_file" || exit; done
python3 -B tests/tandem_integration.py
```

The integration test uses the real OpenCode executable, MCP client, Tandem
daemon, editor plugin, and Conform configuration. Only model responses come
from a deterministic local HTTP fixture; no provider account is used. It checks
unsaved-buffer waiting, stale-revision retries, formatting, shell write denial,
read-only queries, query-to-edit promotion, continuation, and text generation.
Results are written to `artifacts/tandem/`.

Override `TANDEM_NVIM`, `TANDEM_CONFORM`, or `TANDEM_BIN` for nonstandard installs.
`TANDEM_TEST_TMPDIR` selects the temporary directory (default `/tmp/opencode`).
The GitHub workflow runs on Ubuntu 22.04 and 24.04, installs OpenCode V2, builds
the pinned Tandem CLI, and uploads evidence. Automated headless tests do not
claim to exercise a live Herdr terminal UI.

Inside Herdr, run `python3 -B tests/opencode_herdr_smoke.py` for an opt-in live
terminal check. It uses a local model fixture and owned sibling panes to verify
launch, attachment, completion notifications, detach/reattach, routing, and
explicit pane cleanup. It closes its test panes on exit.
