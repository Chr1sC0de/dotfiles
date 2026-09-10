-- Run from the dotfiles root:
-- TANDEM_NVIM_PATH=/path/to/tandem.nvim nvim --headless -u NONE -i NONE -l tests/codex_non_file_launch_spec.lua
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root .. "/config/nvim")
local tandem_path = vim.env.TANDEM_NVIM_PATH or vim.fn.stdpath("data") .. "/lazy/tandem.nvim"
vim.opt.runtimepath:append(tandem_path)
local validator = require("tandem.codex")
local connection = { connected = true, root = vim.uv.fs_realpath(root), command = vim.v.progpath, state_home = root }
local last_options
package.loaded["tandem"] = {
	codex_args = function(options)
		last_options = options
		options.developer_instructions = ""
		return validator.args(connection, options)
	end,
}
local targets = require("codex.context.targets")
local diagnostics = require("codex.context.diagnostics")
local jobs = require("codex.ephemeral.jobs")
local panel = require("codex.ephemeral.jobs_panel")
local state = require("codex.state")
local util = require("codex.util")
local notices = {}
util.notify = function(message)
	notices[#notices + 1] = message
end
local launch_count, prompt, command = 0, nil, nil
vim.fn.executable = function()
	return 1
end
vim.fn.tempname = function()
	return root .. "/unused-test-result"
end
vim.fn.jobstart = function(args)
	launch_count = launch_count + 1
	command = args
	return 12345
end
vim.fn.chansend = function(_, text)
	prompt = text
end
vim.fn.chanclose = function() end
local spinner = require("codex.ephemeral.spinner")
spinner.start_spinner = function()
	return function() end
end
spinner.start_diagnostic = function()
	return function() end
end

local function contains(text, expected)
	assert(text:find(expected, 1, true), expected .. " missing from " .. text)
end
local function current_job()
	return state.ephemeral_jobs[state.ephemeral_job_order[#state.ephemeral_job_order]]
end
local function buffer(name, buftype, filetype)
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(buf)
	if name ~= "" then
		vim.api.nvim_buf_set_name(buf, name)
	end
	if buftype ~= "terminal" then
		vim.bo[buf].buftype = buftype
	end
	vim.bo[buf].filetype = filetype
	vim.bo[buf].bufhidden = "hide"
	vim.api.nvim_buf_set_lines(
		buf,
		0,
		-1,
		false,
		{ "first reference line", "selected reference line", "last reference line" }
	)
	if buftype == "terminal" then
		local channel = vim.api.nvim_open_term(buf, {})
		vim.api.nvim_chan_send(channel, "first reference line\r\nselected reference line\r\nlast reference line")
		assert(vim.wait(1000, function()
			return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "first reference line"
		end))
	end
	return buf
end

local cases = {
	{ "oil://" .. root .. "/", "acwrite", "oil" },
	{ "term://" .. root .. "//123:bash", "terminal", "terminal" },
	{ root .. "/help.txt", "help", "help" },
	{ root .. "/scratch", "nofile", "text" },
	{ "", "", "text" },
	{ root, "", "text" },
	{ "custom://reference", "", "text" },
}
for _, case in ipairs(cases) do
	for _, modified in ipairs({ false, true }) do
		local buf = buffer(unpack(case))
		vim.bo[buf].modified = modified
		local target = targets.build_file({ include_modified_snapshot = true })
		assert(target.file_path == nil and target.source_buf == buf)
		assert(target.snapshot_path == nil)
		local text = table.concat(target.context_lines, "\n")
		contains(text, "Buffer: " .. target.path)
		contains(text, "Filetype: " .. case[3])
		contains(text, "first reference line\nselected reference line\nlast reference line")
		assert(not text:find("available in the workspace", 1, true))

		local selected = targets.build_selection({ range = 2, line1 = 2, line2 = 2 })
		assert(selected.file_path == nil and selected.source_buf == buf)
		local selected_context = table.concat(selected.context_lines, "\n")
		contains(selected_context, "selected reference line")
		assert(not selected_context:find("first reference line", 1, true))
		assert(not selected_context:find("last reference line", 1, true))

		local ns = vim.api.nvim_create_namespace("non-file-launch-test")
		vim.diagnostic.set(ns, buf, { { lnum = 1, col = 0, message = "test diagnostic" } })
		for _, scope in ipairs({ "file", "selection" }) do
			local first = scope == "selection" and 2 or nil
			local diagnostic = diagnostics.build_target(scope, first, first)
			assert(diagnostic.file_path == nil and diagnostic.source_buf == buf)
			local context = table.concat(diagnostic.context_lines, "\n")
			contains(context, "Buffer: ")
			contains(context, "selected reference line")
			if first then
				assert(not context:find("first reference line", 1, true))
			end
			jobs.run("command", diagnostic, "explain diagnostic")
			assert(last_options.path == nil and current_job().status == "running")
		end

		-- Launch after switching buffers: source identity and text must remain captured.
		local other = buffer(root .. "/ordinary-new-file.lua", "", "lua")
		jobs.run("command", target, "explain")
		assert(last_options.path == nil and last_options.read_only == true)
		assert(last_options.cwd == root)
		contains(prompt, "first reference line\nselected reference line\nlast reference line")
		contains(prompt, "Do not modify files.")
		local parent = current_job()
		panel.jump_to_source(parent)
		assert(vim.api.nvim_get_current_buf() == buf)
		vim.api.nvim_set_current_buf(other)
		parent.finished_at, parent.status, parent.thread_id = os.time(), "success", "thread-" .. buf
		assert(jobs.follow_up(parent, "explain more"))
		assert(last_options.path == nil and current_job().source_buf == buf)
		assert(prompt == "explain more")
		contains(table.concat(command, "\n"), "resume\nthread-" .. buf)

		jobs.run("command", selected, "explain selection")
		assert(last_options.path == nil)
		contains(prompt, "selected reference line")
		assert(not prompt:find("first reference line", 1, true))
		local before = launch_count
		jobs.run("edit", target, "edit")
		jobs.run("edit", selected, "edit")
		local asked = false
		vim.ui.input = function()
			asked = true
		end
		jobs.prompt_and_run("edit", target)
		assert(launch_count == before and not asked)
		contains(notices[#notices], "require a file buffer")
		vim.api.nvim_buf_delete(buf, { force = true })
		panel.jump_to_source(parent)
		assert(vim.api.nvim_get_current_buf() == other)
		contains(notices[#notices], "unavailable")
		-- Closing a non-file source still allows resuming its captured thread.
		current_job().status = "success"
		local follow = state.ephemeral_jobs[parent.id + 1]
		follow.status = "success"
		assert(jobs.follow_up(parent, "after close"))
		assert(last_options.path == nil)
		vim.api.nvim_buf_delete(other, { force = true })
	end
end

-- Named ordinary buffers, including files not yet saved, still use real path validation.
for _, name in ipairs({ root .. "/README.md", root .. "/new-file-not-saved.lua", "/outside-tandem.lua" }) do
	local buf = buffer(name, "", "lua")
	local target = targets.build_file()
	assert(target.file_path == name)
	jobs.run("command", target, "inspect")
	assert(last_options.path == name)
	if name == "/outside-tandem.lua" then
		assert(current_job().status == "failed_to_start")
		contains(notices[#notices], "outside Tandem's project")
	else
		assert(current_job().status == "running")
		jobs.run("edit", target, "edit")
		assert(current_job().status == "running" and last_options.read_only == false)
	end
	vim.api.nvim_buf_delete(buf, { force = true })
end

connection.connected = false
local buf = buffer("", "", "text")
jobs.run("command", targets.build_file(), "offline")
assert(current_job().status == "failed_to_start")
contains(notices[#notices], "not connected")
vim.api.nvim_buf_delete(buf, { force = true })
print("codex_non_file_launch_spec.lua: ok (14 non-file cases, real Tandem validation)")
