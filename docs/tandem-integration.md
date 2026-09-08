# Tandem integration

The Lazy spec installs a pinned Tandem CLI with Cargo and loads a pinned
`tandem.nvim` at startup. The plugin starts or reconnects to the project's daemon
automatically. Cargo must be available for the first installation; retry a failed
build with `:Lazy build tandem.nvim`. Use `:TandemStatus` to check the connection.
The integration is disabled in VS Code.

Direct Codex chats, new Herdr-backed chats, and ephemeral jobs launched from this
configuration receive a required Tandem MCP server. Native Codex tools run with a
read-only sandbox and approval escalation disabled. Edit jobs can write through
Tandem; analysis and command jobs receive a server that rejects write requests.
Only the enabled Tandem tools receive explicit Codex tool permission, so their
requests can reach the daemon under that sandbox. Existing managed restrictions
still apply.
The selected model, reasoning effort, session hooks, and key bindings are kept.
If Tandem is unavailable or the launch targets another project, launch fails
with a visible error. Build commands that need native project writes are also
restricted by the read-only sandbox.

When a buffer becomes modified, Tandem holds proposals for that file until the
human saves. Other files remain available to agents. After saving, a proposal
based on old bytes is rejected: the agent must read the new revision and
regenerate its edit. Accepted edits run through Neovim and the existing Conform
save hooks. This coordinates file writes; it does not suspend an agent's model
reasoning or cancel an already running external command.

Restart existing agents to use the new launch settings. Herdr discovery uses the
`nvim-codex-td-` prefix so it cannot silently reattach older `nvim-codex-` agents
that had native write access. New agents should be launched from the Neovim
instance attached to the relevant project. Other configured MCP servers,
trusted hooks, and programs launched separately remain outside Tandem's gate.
The separate agent-only `WorktreeAddPrompt` / `<leader>wO` workflows and the
tmux Workmux backend also retain their existing launch behavior; they are not
covered by this integration. Use a Codex chat launched inside the worktree's
Neovim instance when editing the same checkout together with an agent.

## Pop!_OS / Linux prerequisites

Pop!_OS is the primary acceptance target. Install the distribution's
`bubblewrap` package alongside Codex, Neovim, and Cargo. Codex 0.153.4 prefers
system `bwrap`; its bundled helper can fail on hosts with AppArmor user
namespace restrictions. On affected Ubuntu 24.04 based systems, the packaged
`bwrap-userns-restrict` AppArmor profile may also need to be loaded. Follow
[Codex's Linux prerequisites](https://developers.openai.com/codex/sandboxing#prerequisites)
for the distribution package and profile setup.

From this branch, check the actual Pop!_OS host with:

```sh
python3 tests/tandem_linux_check.py
```

This needs Python 3.10+, Codex, and Bubblewrap. It reports the OS/kernel,
relevant namespace settings, executable versions, and a real sandbox probe.
The native read must work and the attempted write must be denied. The check
uses temporary canary files and an isolated Codex configuration, without
making model requests or changing system security settings. A sandbox startup
error is a failure. A pass establishes this host prerequisite; it does not
replace the daemon/editor tests or an interactive Neovim/Herdr smoke test.

## Reproducible evidence

The `Tandem integration` GitHub Actions workflow runs the existing launcher and
UI tests, then `tests/tandem_integration.py` on Ubuntu 22.04 and 24.04. These are
Linux compatibility checks; they are not a substitute for the user's Pop!_OS
kernel and desktop configuration. The process test installs the CLI
using the actual Lazy build callback and loads this repository's Codex setup,
Tandem spec, and unchanged Conform configuration. It uses real Neovim, the real
Codex CLI and native sandbox, the real MCP client, and the real daemon. A local
deterministic Responses API fixture supplies tool calls; no live model, account,
or API key is involved.

The test checks automatic daemon startup, native write rejection, a blocked
proposal during human editing, an independent edit to another file, rejection
of the stale proposal after saving, a fresh edit formatted by Conform, and the
read-only job's inability to invoke the writer. It also checks argument
forwarding through the actual direct-chat and Herdr launch paths. The Actions
summary and per-platform `tandem-integration-evidence-*` artifacts contain versions, revisions,
the tool trace, and results.

The native shell probe must successfully read the test file before its write
is rejected. The initial Ubuntu 24.04 run failed to initialize the Bubblewrap
network sandbox (`failed RTM_NEWADDR`). Linux CI now installs the documented
distribution package/profile prerequisites. It retains the same read-only
policy and does not disable AppArmor or its global user-namespace restriction.
The previous passing macOS run is supplementary evidence, not Linux acceptance.

This covers the integrated modules in a minimal headless Neovim session. It does
not load every unrelated Lazy plugin, drive the Herdr native GUI, or establish
that a live model always chooses the right tool. The launch restrictions and
write gate are enforced independently of that choice. A native Herdr session
and the complete interactive desktop configuration still need a manual smoke
test before claiming those environments have been verified.
