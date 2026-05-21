local M = {}
local uv = vim.uv or vim.loop

local function snacks()
	return _G.Snacks or require("snacks")
end

local function picker()
	return snacks().picker
end

local function current_buffer_dir()
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		return uv.cwd()
	end

	local dir = vim.fs.dirname(name)
	if dir == nil or vim.fn.isdirectory(dir) == 0 then
		return uv.cwd()
	end

	return dir
end

local function system_lines(cmd)
	local lines = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 and #lines == 0 then
		return { "Command failed: " .. table.concat(cmd, " ") }
	end

	return lines
end

local function directory_preview(ctx)
	local path = ctx.item and ctx.item.file
	if not path then
		ctx.preview:notify("directory not found", "error", { item = false })
		return
	end

	local cmd
	if vim.fn.executable("eza") == 1 then
		cmd = { "eza", "--all", "--long", "--icons", "--git", path }
	else
		cmd = { "ls", "-la", path }
	end

	ctx.preview:reset()
	ctx.preview:minimal()
	ctx.preview:set_title(vim.fn.fnamemodify(path, ":~"))
	ctx.preview:set_lines(system_lines(cmd))
end

function M.folders()
	local cwd = uv.cwd()
	local lines = system_lines({ "fd", "--type", "d", "--hidden", "--exclude", ".git" })
	local items = {}

	for _, line in ipairs(lines) do
		if line ~= "" then
			local file = vim.fs.normalize(cwd .. "/" .. line)
			table.insert(items, {
				text = line,
				file = file,
			})
		end
	end

	picker().pick({
		title = "Folders",
		items = items,
		format = "file",
		preview = directory_preview,
		confirm = function(p, item)
			p:close()
			if item then
				require("oil").open(item.file)
			end
		end,
	})
end

local function listed_file_buffers()
	local current = vim.api.nvim_get_current_buf()
	local items = {}

	for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1, bufloaded = 1 })) do
		local bufnr = info.bufnr
		local name = vim.api.nvim_buf_get_name(bufnr)
		local stat = uv.fs_stat(name)

		if bufnr ~= current and vim.bo[bufnr].buftype == "" and name ~= "" and stat and stat.type == "file" then
			table.insert(items, {
				buf = bufnr,
				file = name,
				text = vim.fn.fnamemodify(name, ":~:."),
				lastused = info.lastused or 0,
			})
		end
	end

	table.sort(items, function(a, b)
		return a.lastused > b.lastused
	end)

	return items
end

function M.buffers()
	picker().pick({
		title = "Buffers",
		finder = listed_file_buffers,
		format = "file",
		preview = "file",
		actions = {
			delete_buffer = function(p)
				for _, item in ipairs(p:selected({ fallback = true })) do
					if item.buf and vim.api.nvim_buf_is_valid(item.buf) then
						vim.api.nvim_buf_delete(item.buf, { force = true })
					end
				end

				p:close()
				vim.schedule(M.buffers)
			end,
		},
		win = {
			input = {
				keys = {
					["<C-d>"] = { "delete_buffer", mode = { "n", "i" } },
				},
			},
			list = {
				keys = {
					dd = "delete_buffer",
				},
			},
		},
	})
end

local function terminal_items()
	local current = vim.api.nvim_get_current_buf()
	local items = {}

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(bufnr)
		if
			vim.api.nvim_buf_is_loaded(bufnr)
			and bufnr ~= current
			and vim.bo[bufnr].buftype == "terminal"
			and vim.startswith(name, "term:")
		then
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local max_lines = 200
			if #lines > max_lines then
				lines = vim.list_slice(lines, #lines - max_lines, #lines)
			end

			table.insert(items, {
				buf = bufnr,
				text = name ~= "" and name or ("term://" .. bufnr),
				preview = {
					text = table.concat(lines, "\n"),
				},
			})
		end
	end

	return items
end

local function delete_terminal_buffer(item)
	local bufnr = item and item.buf
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local chan = vim.b[bufnr].terminal_job_id
	if chan then
		pcall(vim.fn.jobstop, chan)
	end

	vim.api.nvim_buf_delete(bufnr, { force = true })
end

function M.terminals()
	picker().pick({
		title = "Terminal Buffers",
		finder = terminal_items,
		format = "text",
		preview = "preview",
		confirm = function(p, item)
			p:close()
			if item and item.buf and vim.api.nvim_buf_is_valid(item.buf) then
				vim.api.nvim_set_current_buf(item.buf)
			end
		end,
		actions = {
			delete_terminal = function(p)
				for _, item in ipairs(p:selected({ fallback = true })) do
					delete_terminal_buffer(item)
				end

				p:close()
				vim.schedule(M.terminals)
			end,
		},
		win = {
			input = {
				keys = {
					["<C-d>"] = { "delete_terminal", mode = { "n", "i" } },
				},
			},
			list = {
				keys = {
					dd = "delete_terminal",
				},
			},
		},
	})
end

local function tab_items()
	local current = vim.api.nvim_get_current_tabpage()
	local items = {}

	for index, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local wins = vim.api.nvim_tabpage_list_wins(tab)
		local current_win = vim.api.nvim_tabpage_get_win(tab)
		local current_buf = vim.api.nvim_win_get_buf(current_win)
		local current_name = vim.api.nvim_buf_get_name(current_buf)
		local label = current_name ~= "" and vim.fn.fnamemodify(current_name, ":~:.") or "[No Name]"
		local preview = {}

		for _, win in ipairs(wins) do
			local bufnr = vim.api.nvim_win_get_buf(win)
			local name = vim.api.nvim_buf_get_name(bufnr)
			table.insert(preview, name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]")
		end

		table.insert(items, {
			text = string.format("%s%d: %s", tab == current and "* " or "  ", index, label),
			tab = tab,
			preview = {
				text = table.concat(preview, "\n"),
			},
		})
	end

	return items
end

function M.tabs()
	picker().pick({
		title = "Tabs",
		finder = tab_items,
		format = "text",
		preview = "preview",
		confirm = function(p, item)
			p:close()
			if item and vim.api.nvim_tabpage_is_valid(item.tab) then
				vim.api.nvim_set_current_tabpage(item.tab)
			end
		end,
	})
end

local function start_remote_host(host_id)
	local remote_nvim = require("remote-nvim")
	local devpod_utils = require("remote-nvim.providers.devpod.devpod_utils")
	local workspace_config = remote_nvim.session_provider:get_config_provider():get_workspace_config(vim.trim(host_id))

	if vim.tbl_isempty(workspace_config) then
		vim.notify("Unknown host identifier. Run :RemoteStart to connect to a new host", vim.log.levels.ERROR)
		return
	end

	remote_nvim.session_provider
		:get_or_initialize_session({
			host = workspace_config.host,
			provider_type = workspace_config.provider,
			conn_opts = { workspace_config.connection_options },
			unique_host_id = host_id,
			devpod_opts = devpod_utils.get_workspace_devpod_opts(workspace_config),
		})
		:launch_neovim()
end

local function remote_host_items()
	local remote_nvim = require("remote-nvim")
	local configs = remote_nvim.session_provider:get_config_provider():get_workspace_config()
	local items = {}

	for host_id, config in pairs(configs) do
		table.insert(items, {
			text = host_id,
			host_id = host_id,
			preview = {
				text = vim.inspect(config),
				ft = "lua",
			},
		})
	end

	table.sort(items, function(a, b)
		return a.text < b.text
	end)

	return items
end

local function remote_start_picker()
	local items = remote_host_items()
	if #items == 0 then
		vim.notify("No remote host configurations found", vim.log.levels.WARN)
		return
	end

	picker().pick({
		title = "Remote Hosts",
		items = items,
		format = "text",
		preview = "preview",
		confirm = function(p, item)
			p:close()
			if item then
				start_remote_host(item.host_id)
			end
		end,
	})
end

function M.setup_remote_start()
	vim.api.nvim_create_user_command("RemoteStart", function(opts)
		local host_identifier = vim.trim(opts.args)
		if host_identifier == "" then
			remote_start_picker()
		else
			start_remote_host(host_identifier)
		end
	end, {
		force = true,
		nargs = "?",
		desc = "Start Neovim on remote machine",
		complete = function(_, line)
			local remote_nvim = require("remote-nvim")
			local args = vim.split(vim.trim(line), "%s+")
			table.remove(args, 1)

			local valid_hosts = vim.tbl_keys(remote_nvim.session_provider:get_config_provider():get_workspace_config())
			if #args == 0 then
				return valid_hosts
			end

			return vim.fn.matchfuzzy(valid_hosts, args[1])
		end,
	})
end

function M.setup()
	local snacks_picker = picker()

	vim.keymap.set("n", "<leader>fd", M.folders, { desc = "Snacks: open folder in Oil" })
	vim.keymap.set("n", "<leader>ff", snacks_picker.smart, { desc = "Snacks: find files" })
	vim.keymap.set("n", "<leader>fF", function()
		snacks_picker.files({ cwd = current_buffer_dir() })
	end, { desc = "Snacks: find files near current buffer" })
	vim.keymap.set("n", "<leader>fT", snacks_picker.treesitter, { desc = "Snacks: treesitter" })
	vim.keymap.set("n", "<leader>fs", snacks_picker.grep_word, { desc = "Snacks: search for string under cursor" })
	vim.keymap.set("n", "<leader>fg", snacks_picker.grep, { desc = "Snacks: live grep" })
	vim.keymap.set("n", "<leader>f,", snacks_picker.lines, { desc = "Snacks: search inside the current open buffer" })
	vim.keymap.set("n", "<leader>ld", snacks_picker.lsp_symbols, { desc = "Snacks: lsp document symbols" })
	vim.keymap.set("n", "<leader>-", snacks_picker.explorer, { desc = "Snacks: File Explorer" })
	vim.keymap.set(
		"n",
		"<leader>lw",
		snacks_picker.lsp_workspace_symbols,
		{ desc = "Snacks: dynamic workspace lsp symbols" }
	)
	vim.keymap.set(
		"n",
		"<leader>lr",
		snacks_picker.lsp_references,
		{ desc = "Snacks: search for references for symbol under cursor" }
	)
	vim.keymap.set("n", "<leader>lic", snacks_picker.lsp_incoming_calls, { desc = "Snacks: lsp incoming calls" })
	vim.keymap.set("n", "<leader>fmm", snacks_picker.marks, { desc = "Snacks: search marks" })
	vim.keymap.set("n", "gd", snacks_picker.lsp_definitions, { desc = "Snacks: definitions", noremap = true })
	vim.keymap.set("n", "<leader>lim", snacks_picker.lsp_implementations, {
		desc = "Snacks: lsp implementations",
		noremap = true,
	})
	vim.keymap.set("n", "<leader>f'", snacks_picker.diagnostics_buffer, { desc = "Snacks: list buffer diagnostics" })
	vim.keymap.set("n", '<leader>f"', snacks_picker.diagnostics, { desc = "Snacks: list diagnostics" })
	vim.keymap.set("n", "<leader>fk", snacks_picker.keymaps, { desc = "Snacks: search keymaps" })
	vim.keymap.set("n", "<leader>gk", snacks_picker.git_log_file, { desc = "Snacks: buffer commits" })
	vim.keymap.set("n", "<leader>gK", snacks_picker.git_log, { desc = "Snacks: list git commits" })
	vim.keymap.set("n", "<leader>gs", snacks_picker.git_status, { desc = "Snacks: git status" })
	vim.keymap.set("n", "<leader>gS", snacks_picker.git_stash, { desc = "Snacks: git stash" })
	vim.keymap.set("n", "<leader>gf", snacks_picker.git_files, { desc = "Snacks: git files" })
	vim.keymap.set("n", "<leader>gb", function()
		snacks_picker.git_branches({ all = true })
	end, { desc = "Snacks: git branches" })
	vim.keymap.set("n", "<leader>f.", M.buffers, { desc = "Snacks: search buffers" })
	vim.keymap.set("n", "<leader>fM", snacks_picker.man, { desc = "Snacks: search man pages" })
	vim.keymap.set("n", "<leader>fht", snacks_picker.help, { desc = "Snacks: search help tags" })
	vim.keymap.set("n", "<leader>:", snacks_picker.commands, { desc = "Snacks: commands" })
	vim.keymap.set("n", "<leader>f/", M.terminals, { desc = "Snacks: terminal buffers" })
	vim.keymap.set("n", "<leader>ft", M.tabs, { desc = "Snacks: tabs" })

	vim.api.nvim_create_user_command("SnacksTerminals", M.terminals, {})
end

return M
