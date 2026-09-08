-- Connection fixture for launcher/UI unit tests. The integration test uses
-- the actual plugin, Rust MCP server, Codex executable, and Conform config.
package.loaded["tandem"] = {
	codex_args = function(options)
		local args = { "--root", options.cwd, "mcp" }
		if options.read_only then args[#args + 1] = "--read-only" end
		return {
			"--sandbox", "read-only", "-c", 'approval_policy="never"',
			"-c", "mcp_servers.tandem.args=" .. vim.json.encode(args):gsub("\\/", "/"),
		}
	end,
}
