-- Loaded before init.lua so startup errors cannot silently pass the audit.
local errors = {}
-- Observe error messages independently of plugins that replace vim.notify.
vim.ui_attach(
	vim.api.nvim_create_namespace("dotfiles-install-audit"),
	{ ext_messages = true },
	function(event, kind, content)
		if event == "msg_show" then
			local chunks = {}
			for _, chunk in ipairs(content) do
				table.insert(chunks, chunk[2])
			end
			local message = table.concat(chunks)
			-- ext_messages owns display; preserve messages in the stage log too.
			io.stderr:write(message .. "\n")
			if kind == "emsg" or kind == "lua_error" or kind == "echoerr" then
				table.insert(errors, message)
			end
		end
	end
)
local notify = vim.notify
vim.notify = function(message, level, opts)
	if level == vim.log.levels.ERROR then
		table.insert(errors, tostring(message))
	end
	return notify(message, level, opts)
end

local function plugins()
	require("lazy").restore({ wait = true })
	local configured = require("lazy.core.config").plugins
	local names = vim.tbl_keys(configured)
	table.sort(names)
	for _, name in ipairs(names) do
		local plugin = configured[name]
		assert(plugin._.installed, "Plugin not installed: " .. name)
		for _, task in ipairs(plugin._.tasks or {}) do
			assert(not task:has_errors(), "Plugin task failed: " .. name)
		end
		if plugin._.cond ~= false then
			require("lazy").load({ plugins = { name } })
			assert(plugin._.loaded, "Plugin did not load: " .. name)
			print("Loaded plugin: " .. name)
		else
			print("Skipped conditional plugin: " .. name)
		end
	end
end

local function mason()
	-- Read the real configuration rather than maintaining a second tool list.
	local installer = require("mason-tool-installer")
	local setup, settings = installer.setup, nil
	installer.setup = function(opts)
		settings = opts
	end
	local ok, err = pcall(require("plugins.mason-tool-installer").config)
	installer.setup = setup
	assert(ok, err)
	assert(settings and #settings.ensure_installed > 0, "No Mason tools configured")
	local registry = require("mason-registry")
	-- LSP aliases are derived from registry metadata, absent on a fresh install.
	local refreshed, refresh_ok = false, false
	registry.refresh(function(ok)
		refreshed, refresh_ok = true, ok
	end)
	assert(vim.wait(120000, function()
		return refreshed
	end) and refresh_ok, "Mason registry refresh failed or timed out")
	local mappings = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
	local dap = require("mason-nvim-dap.mappings.source").nvim_dap_to_package
	-- A duplicate pending package is not given a second completion callback by
	-- mason-tool-installer, so its synchronous command can wait forever.
	local seen = {}
	for _, entry in ipairs(settings.ensure_installed) do
		local name = type(entry) == "table" and entry[1] or entry
		name = mappings[name] or dap[name] or name
		assert(not seen[name], "Duplicate Mason tool (can hang synchronous installation): " .. name)
		seen[name] = true
	end
	vim.cmd("MasonToolsInstallSync")
	local missing = {}
	for _, entry in ipairs(settings.ensure_installed) do
		local name = type(entry) == "table" and entry[1] or entry
		if type(entry) ~= "table" or not entry.condition or entry.condition() then
			name = mappings[name] or dap[name] or name
			if not registry.has_package(name) or not registry.get_package(name):is_installed() then
				table.insert(missing, name)
			else
				print("Installed Mason tool: " .. name)
			end
		end
	end
	assert(#missing == 0, "Missing Mason tools: " .. table.concat(missing, ", "))
end

_G.dotfiles_install_audit = function()
	local ok, err = xpcall(function()
		if vim.env.NVIM_AUDIT_STAGE == "plugins" then
			plugins()
		elseif vim.env.NVIM_AUDIT_STAGE == "treesitter" then
			dofile("tests/nvim_treesitter_audit.lua")
		elseif vim.env.NVIM_AUDIT_STAGE == "pymple" then
			dofile("tests/nvim_pymple_audit.lua")
		elseif vim.env.NVIM_AUDIT_STAGE == "mason" then
			mason()
		else
			error("Unknown audit stage: " .. tostring(vim.env.NVIM_AUDIT_STAGE))
		end
		-- Flush scheduled error notifications before deciding the exit status.
		vim.wait(1000, function()
			return false
		end)
		-- silent! commands can leave v:errmsg set even when the error was handled.
		-- Only fail for errors actually reported in message history.
		local messages = vim.fn.execute("messages")
		assert(not messages:match("E%d+:"), messages)
		assert(#errors == 0, table.concat(errors, "\n"))
	end, debug.traceback)
	print(vim.fn.execute("messages"))
	if not ok then
		io.stderr:write(tostring(err) .. "\n")
		vim.cmd("cquit 1")
	else
		print("Neovim " .. vim.env.NVIM_AUDIT_STAGE .. " audit passed")
		vim.cmd("qa!")
	end
end
