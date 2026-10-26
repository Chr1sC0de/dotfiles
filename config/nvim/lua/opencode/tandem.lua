local M = {}
local options = {}

function M.configure(opts)
	options = opts or {}
end

local function inside(root, path)
	return path == root or path:sub(1, #root + 1) == root .. "/"
end

-- Keep the editor connection authoritative. A second project needs its own
-- editor, rather than silently launching an agent with an unrelated gateway.
function M.config(cwd, read_only, path)
	local ok, tandem = pcall(require, "tandem")
	local status = ok and type(tandem.status) == "function" and tandem.status() or {}
	if not status.connected or not status.root then
		return nil, "Tandem is not connected. Check :TandemStatus before starting an agent."
	end
	local root = status.root
	local real_cwd = vim.uv.fs_realpath(cwd)
	if not real_cwd or not inside(root, real_cwd) then
		return nil, "Agent cwd is outside Tandem's project. Open that project in another Neovim process."
	end
	if path and not inside(root, vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))) then
		return nil, "The target file is outside Tandem's project."
	end
	local binary = options.command or (vim.fn.stdpath("data") .. "/tandem/bin/tandem")
	if vim.fn.executable(binary) ~= 1 then
		return nil, "Tandem CLI is missing; install the pinned CLI and reconnect."
	end
	local command = { binary, "--root", root, "--state-home",
		options.state_home or vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state"), "mcp" }
	if read_only then
		table.insert(command, "--read-only")
	end
	return {
		mcp = { servers = { tandem = { type = "local", command = command, codemode = false } } },
	}, nil, root
end

return M
