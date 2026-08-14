local commit = require("codex.commit")
local state = require("codex.state")
local util = require("codex.util")

local M = {}

local displayed_fingerprint
local displayed_message

local function current_prepared()
	return state.codex_prepared_commit
end

local function review_lines()
	local prepared = current_prepared()
	if not prepared then
		return { "No prepared commit." }
	end

	local lines = {
		"Repository: " .. prepared.root,
		"",
		"Commit message:",
		"",
		"  " .. prepared.message,
		"",
	}
	if state.codex_commit_review_status then
		vim.list_extend(lines, { "Status: " .. state.codex_commit_review_status, "" })
	end
	vim.list_extend(lines, {
		"[a/Enter] accept   [e] edit   [f] feedback   [r] reject   [q/Esc] close",
	})
	return lines
end

local function float_config(lines)
	local columns = vim.o.columns
	local editor_lines = vim.o.lines
	local content_width = 0
	for _, line in ipairs(lines) do
		content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
	end
	local width = math.min(math.max(content_width + 4, 64), math.max(columns - 6, 20))
	local height = math.min(math.max(#lines, 8), math.max(editor_lines - 8, 8))
	return {
		relative = "editor",
		row = math.max(math.floor((editor_lines - height) / 2), 0),
		col = math.max(math.floor((columns - width) / 2), 0),
		width = width,
		height = height,
		border = "rounded",
		style = "minimal",
		title = " Codex Commit Review ",
		title_pos = "center",
	}
end

function M.close()
	if util.is_valid_window(state.codex_commit_review_win) then
		vim.api.nvim_win_close(state.codex_commit_review_win, true)
	end
	state.codex_commit_review_win = nil
	state.codex_commit_review_buf = nil
	displayed_fingerprint = nil
	displayed_message = nil
end

function M.render()
	if not util.is_valid_buffer(state.codex_commit_review_buf) then
		return
	end
	local lines = review_lines()
	vim.bo[state.codex_commit_review_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.codex_commit_review_buf, 0, -1, false, lines)
	vim.bo[state.codex_commit_review_buf].modified = false
	vim.bo[state.codex_commit_review_buf].modifiable = false
	local prepared = current_prepared()
	displayed_fingerprint = prepared and prepared.fingerprint or nil
	displayed_message = prepared and prepared.message or nil
	if util.is_valid_window(state.codex_commit_review_win) then
		vim.api.nvim_win_set_config(state.codex_commit_review_win, float_config(lines))
	end
end

local function candidate_is_current()
	local prepared = current_prepared()
	if not prepared then
		M.close()
		util.notify("No prepared commit; run :CodexPrepareCommit first", vim.log.levels.WARN)
		return false
	end
	if displayed_fingerprint ~= prepared.fingerprint or displayed_message ~= prepared.message then
		M.render()
		util.notify("Prepared commit changed; review popup refreshed", vim.log.levels.WARN)
		return false
	end
	return true
end

local function set_status(status)
	state.codex_commit_review_status = status
	M.render()
end

function M.accept()
	if state.codex_commit_review_status then
		util.notify("Wait for the current commit review operation to finish", vim.log.levels.WARN)
		return
	end
	if not candidate_is_current() then
		return
	end
	M.close()
	commit.commit()
end

function M.edit()
	if state.codex_commit_review_status then
		util.notify("Wait for the current commit review operation to finish", vim.log.levels.WARN)
		return
	end
	if not candidate_is_current() then
		return
	end
	local prepared = current_prepared()

	vim.ui.input({ prompt = "Edit commit message: ", default = prepared.message }, function(message)
		if message == nil then
			return
		end
		if not candidate_is_current() then
			return
		end
		set_status("Validating edited message…")
		commit.update_message(message, function()
			set_status(nil)
			if not current_prepared() then
				M.close()
			end
		end)
	end)
end

function M.feedback()
	if state.codex_commit_review_status then
		util.notify("Wait for the current commit review operation to finish", vim.log.levels.WARN)
		return
	end
	if not candidate_is_current() then
		return
	end

	vim.ui.input({ prompt = "Commit message feedback: " }, function(feedback)
		feedback = util.trim_whitespace(feedback)
		if feedback == "" then
			return
		end
		if not candidate_is_current() then
			return
		end
		set_status("Codex is revising the message…")
		commit.revise(feedback, function()
			set_status(nil)
			if not current_prepared() then
				M.close()
			end
		end)
	end)
end

function M.reject()
	if state.codex_commit_review_status then
		util.notify("Wait for the current commit review operation to finish", vim.log.levels.WARN)
		return
	end
	if not candidate_is_current() then
		return
	end
	if commit.reject() then
		M.close()
	end
end

local function create_buffer()
	local bufnr = vim.api.nvim_create_buf(false, true)
	state.codex_commit_review_buf = bufnr
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].filetype = "markdown"
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].swapfile = false

	local opts = { buffer = bufnr, nowait = true, silent = true }
	vim.keymap.set("n", "a", M.accept, opts)
	vim.keymap.set("n", "<CR>", M.accept, opts)
	vim.keymap.set("n", "e", M.edit, opts)
	vim.keymap.set("n", "f", M.feedback, opts)
	vim.keymap.set("n", "r", M.reject, opts)
	vim.keymap.set("n", "q", M.close, opts)
	vim.keymap.set("n", "<Esc>", M.close, opts)
	return bufnr
end

local function show()
	local lines = review_lines()
	local bufnr = create_buffer()
	state.codex_commit_review_win = vim.api.nvim_open_win(bufnr, true, float_config(lines))
	vim.wo[state.codex_commit_review_win].number = false
	vim.wo[state.codex_commit_review_win].relativenumber = false
	vim.wo[state.codex_commit_review_win].signcolumn = "no"
	vim.wo[state.codex_commit_review_win].wrap = true
	M.render()
end

function M.open()
	if state.codex_commit_active then
		util.notify("A Codex commit operation is already in progress", vim.log.levels.WARN)
		return
	end
	commit.inspect(function(prepared)
		if not prepared then
			M.close()
			return
		end
		if util.is_valid_window(state.codex_commit_review_win) then
			vim.api.nvim_set_current_win(state.codex_commit_review_win)
			M.render()
			return
		end
		show()
	end)
end

return M
