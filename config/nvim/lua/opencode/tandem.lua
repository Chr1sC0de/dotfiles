-- Direct RPC registration; no companion plugin or MCP server.
local M = {}
local options, connection = {}, {}
local timer, generation = nil, 0

function M.configure(opts) options = opts or {} end
function M.status() return vim.deepcopy(connection) end
function M.stop()
	generation = generation + 1
	if timer and not timer:is_closing() then timer:stop(); timer:close() end
	timer = nil
end

function M.setup(opts)
	M.stop()
	M.configure(opts)
	local current, failures = generation, 0
	local root = vim.uv.fs_realpath(options.root or vim.fn.getcwd())
	local socket = vim.v.servername
	if socket == "" then socket = vim.fn.serverstart() end
	connection = { connected = false, root = root, socket = socket }
	timer = vim.uv.new_timer()
	local function register()
		if current ~= generation then return end
		local args = { options.command or vim.env.TANDEM_BIN or "tandem", "--root", root }
		if options.state_home then vim.list_extend(args, { "--state-home", options.state_home }) end
		vim.list_extend(args, { "editor", "register", "--socket", socket })
		local function finish(result)
			vim.schedule(function()
				if current ~= generation then return end
				local ok, data = pcall(vim.json.decode, result.stdout or "")
				connection.connected = result.code == 0 and ok and type(data) == "table" and data.ok == true and type(data.editor) == "string"
				connection.editor = connection.connected and data.editor or nil
				if connection.connected then
					connection.error = nil
				else
					connection.error = result.stderr ~= "" and result.stderr or "Registration failed"
				end
				failures = connection.connected and 0 or math.min(failures + 1, 10)
				timer:start(math.min(options.backoff_cap_ms or 60000, (options.interval_ms or 5000) * 2 ^ failures), 0, vim.schedule_wrap(register))
			end)
		end
		local ok, err = pcall(vim.system, args, { text = true, timeout = 10000 }, finish)
		if not ok then finish({ code = 1, stderr = tostring(err) }) end
	end
	local group = vim.api.nvim_create_augroup("TandemRegistration", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.stop })
	vim.api.nvim_create_user_command("TandemStatus", function() vim.notify(vim.inspect(M.status())) end, { force = true })
	vim.schedule(register)
end

local function inside(root, path) return path == root or path:sub(1, #root + 1) == root .. "/" end
function M.config(cwd, _, path)
	local status = M.status()
	if not status.connected or not status.editor then
		return nil, "Tandem is not registered. Check :TandemStatus and the local CLI installation."
	end
	local root, real_cwd = status.root, vim.uv.fs_realpath(cwd)
	if not real_cwd or not inside(root, real_cwd) then
		return nil, "Agent cwd is outside Tandem's project. Open that project in another Neovim process."
	end
	if path and not inside(root, vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))) then return nil, "The target file is outside Tandem's project." end
	local binary = options.command or vim.env.TANDEM_BIN or "tandem"
	if vim.fn.executable(binary) ~= 1 then return nil, "Tandem CLI is missing; run bash utils/install-tandem.sh." end
	return { tandem = { command = vim.fn.exepath(binary), root = root, editor = status.editor, state_home = options.state_home } }, nil, root
end
return M
