# Tandem editor integration

Use the built-in shell to invoke the Tandem CLI as `"$TANDEM_BIN"`. `TANDEM_ROOT` and `TANDEM_EDITOR` select the workspace and Neovim editor. Paths passed to Tandem are relative to `TANDEM_ROOT`.

Use normal tools for tests, builds, package installs, Git, and filesystem operations. Prefer Tandem for source reads and edits so you see unsaved Neovim buffers and coordinate concurrent edits.

Use `"$TANDEM_BIN" buffers`, `"$TANDEM_BIN" read PATH` (or `read --buffer ID`), then `"$TANDEM_BIN" write PATH --expect REVISION --content-file -` with full replacement text on stdin.

Reads include unsaved edits; writes merge compatible concurrent changes. Tandem automatically saves only clean, unchanged named buffers through normal save hooks; existing or concurrent drafts remain unsaved. Check `saved` and `save_error` in the result; do not separately save drafts without user authorization. Disk tools, tests, and Git only see saved content.

On `merge_conflict` or `snapshot_expired`, reread and reconsider; never attach a fresh revision to stale content. On `outcome_unknown`, run `"$TANDEM_BIN" outcome ATTEMPT_ID` and inspect the buffer; never blindly replay the write.

Reading a path loads its Neovim buffer if needed. If unavailable, report it and suggest `:TandemStatus`.
