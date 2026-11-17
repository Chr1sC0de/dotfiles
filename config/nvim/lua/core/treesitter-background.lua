-- Interactive orchestration only. The synchronous installer runs in a clean child.
local M = {}
local worker = debug.getinfo(1, "S").source:sub(2):gsub("treesitter%-background.lua$", "treesitter-worker.lua")

local function refresh()
	vim.treesitter.query.get:clear()
	local config = require("tree-sitter-manager.config").cfg
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local ft = vim.bo[buf].filetype
			local lang = vim.treesitter.language.get_lang(ft)
			local highlight = config.highlight == true
				or (type(config.highlight) == "table" and vim.tbl_contains(config.highlight, lang))
			if lang and highlight and not vim.tbl_contains(config.nohighlight or {}, ft) then
				-- A loaded parser library cannot safely be replaced in this process.
				-- Only start highlighting buffers that did not already have a parser.
				if not vim.treesitter.highlighter.active[buf] then
					pcall(vim.treesitter.start, buf, lang)
				end
			end
		end
	end
end

function M.start(mode, selected)
	assert(mode == "ensure" or mode == "reconcile" or mode == "rebuild", "Unknown Tree-sitter operation")
	local backend = require("core.treesitter-backend")
	local languages = backend.languages(selected)
	if mode == "ensure" and vim.iter(languages):all(backend.installed) then
		return { done = true, code = 0 }
	end
	if M.active and not M.active.done then
		if mode == "ensure" then
			return M.active
		end
		error("Tree-sitter provisioning already running; see :DotfilesTSLog")
	end
	local config = require("tree-sitter-manager.config")
	local root = vim.fn.stdpath("state") .. "/dotfiles-treesitter-v1"
	vim.fn.mkdir(root, "p")
	local log = root .. "/worker-" .. vim.fn.getpid() .. "-" .. tostring(vim.uv.hrtime()) .. ".log"
	local request = log .. ".json"
	vim.fn.writefile({}, log)
	vim.fn.writefile({
		vim.json.encode({
			runtimepath = vim.opt.runtimepath:get(),
			config = config.cfg,
			repos = config.effective_repos,
			mode = mode,
			selected = selected,
			log = log,
		}),
	}, request)
	local job = { done = false, log = log }
	M.active, M.log = job, log
	local ok, process = pcall(
		vim.system,
		{
			vim.v.progpath,
			"--headless",
			"-u",
			"NONE",
			"-i",
			"NONE",
			"-n",
			"-l",
			worker,
			request,
		},
		{ text = true, detach = true },
		vim.schedule_wrap(function(result)
			job.done, job.code = true, result.code
			vim.fn.delete(request)
			if result.code == 0 then
				refresh()
				vim.notify("Tree-sitter provisioning complete", vim.log.levels.INFO)
			else
				vim.fn.writefile(vim.split(result.stderr or "", "\n"), log, "a")
				vim.notify("Tree-sitter provisioning failed; see :DotfilesTSLog", vim.log.levels.ERROR)
			end
		end)
	)
	if not ok then
		job.done, job.code = true, 1
		vim.fn.delete(request)
		error(process)
	end
	job.process = process
	vim.notify("Tree-sitter provisioning in background; see :DotfilesTSLog", vim.log.levels.INFO)
	return job
end

-- Lazy function build hooks run inside lazy.async. Yield, rather than vim.wait,
-- so the task keeps its completion/error semantics while input remains usable.
function M.build()
	local async = require("lazy.async")
	assert(async.running(), "Tree-sitter build must run in Lazy's async task")
	-- A scheduled startup ensure may have won the race with Lazy. Let it
	-- finish before reconciling, without failing the plugin build task.
	while M.active and not M.active.done do
		async.sleep(50)
	end
	local job = M.start("reconcile")
	while not job.done do
		async.sleep(50)
	end
	assert(job.code == 0, "Tree-sitter build failed; see :DotfilesTSLog")
end

function M.setup_commands()
	vim.api.nvim_create_user_command("DotfilesTSLog", function()
		assert(M.log, "No Tree-sitter worker started in this editor")
		vim.cmd("botright split " .. vim.fn.fnameescape(M.log))
		vim.bo.readonly = true
		vim.bo.modifiable = false
	end, { force = true, desc = "Open Tree-sitter worker log (:edit! to refresh)" })
end

return M
