-- Run from the dotfiles root with nvim --headless -u NONE -i NONE -l this-file.
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")

local sent
package.loaded["codex.chat"] = {
	paste = function(text)
		sent = text
		return true
	end,
}
local context = require("codex.context")
local jobs = require("codex.ephemeral.jobs")
local panel = require("codex.ephemeral.jobs_panel")
local util = require("codex.util")
util.notify = function() end

local function contains(text)
	assert(sent:find(text, 1, true), text .. " missing from chat payload:\n" .. sent)
end

local function buffer(name, buftype, modified)
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_buf_set_name(buf, name)
	vim.bo[buf].buftype = buftype
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].bufhidden = "hide"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "REFERENCE_FIRST", "REFERENCE_LAST" })
	vim.bo[buf].modified = modified
	return buf
end

local snapshots = 0
util.write_current_buffer_snapshot = function()
	snapshots = snapshots + 1
	assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "REFERENCE_FIRST")
	return "/tmp/codex-send-test-snapshot"
end

-- Reproduce the actual result view -> whole-buffer send path.
local job = jobs.create("command", {
	kind = "prompt",
	path = "",
	context_lines = {},
}, nil, "Explain the proposed change")
job.finished_at, job.status = os.time(), "success"
job.answer_lines = { "UNIQUE_RESULT: use a shared helper.", "", "Preserve the existing behavior." }
assert(panel.open_result(job))
context.send_file()
contains("Explain the proposed change")
contains("UNIQUE_RESULT: use a shared helper.")
contains("Preserve the existing behavior.")
contains("Buffer: codex://job/" .. job.id)
contains("read-only reference context")
assert(not sent:find("Open/read this file", 1, true))
assert(snapshots == 0)

-- Selection sending still includes exactly the chosen text.
local result_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
for line, text in ipairs(result_lines) do
	if text == job.answer_lines[1] then
		context.send_selection({ range = 2, line1 = line, line2 = line })
		contains(job.answer_lines[1])
		assert(not sent:find(job.answer_lines[3], 1, true))
	end
end

-- All non-file references use inline content, including modified buffers.
for _, case in ipairs({
	{ "scratch://reference", "nofile" },
	{ "oil://" .. vim.fn.getcwd() .. "/", "acwrite" },
	{ "custom://reference", "" },
	{ "", "" },
}) do
	for _, modified in ipairs({ false, true }) do
		local buf = buffer(case[1], case[2], modified)
		context.send_file()
		contains("Buffer: ")
		contains("REFERENCE_FIRST\nREFERENCE_LAST")
		contains("Unsaved changes: " .. (vim.bo[buf].modified and "yes" or "no"))
		assert(not sent:find("Read the snapshot", 1, true))
		assert(snapshots == 0)
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

-- Ordinary files keep filesystem context and capture unsaved contents via snapshots.
local buf = buffer(vim.fn.getcwd() .. "/send-context-test.md", "", false)
context.send_file()
contains("File: send-context-test.md")
contains("Read it from disk")
assert(not sent:find("REFERENCE_FIRST", 1, true))
assert(snapshots == 0)
vim.bo[buf].modified = true
context.send_file()
contains("Unsaved buffer snapshot: /tmp/codex-send-test-snapshot")
assert(snapshots == 1)
vim.api.nvim_buf_delete(buf, { force = true })
print("codex_send_context_spec.lua: ok")
