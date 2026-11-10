-- Registered editor fixture. The real Rust CLI/editor/RPC are exercised by
-- tandem_integration.py; unit tests intercept process and UI boundaries.
require("agents.tandem").status = function()
	return { connected = true, editor = "test-editor", root = vim.uv.fs_realpath(vim.fn.getcwd()) }
end
require("agents.tandem").configure({ command = vim.v.progpath })
