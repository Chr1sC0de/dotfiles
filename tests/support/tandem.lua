-- Connected gateway fixture. The real Rust CLI/editor/MCP are exercised by
-- tandem_integration.py; unit tests intercept process and UI boundaries.
package.loaded["tandem"] = {
	status = function() return { connected = true, root = vim.uv.fs_realpath(vim.fn.getcwd()) } end,
}
require("opencode.tandem").configure({ command = vim.v.progpath })
