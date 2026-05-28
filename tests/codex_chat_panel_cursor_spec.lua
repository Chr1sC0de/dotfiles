vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:append(".")
package.path = table.concat({
	vim.fn.getcwd() .. "/config/nvim/lua/?.lua",
	vim.fn.getcwd() .. "/config/nvim/lua/?/init.lua",
	package.path,
}, ";")

vim.g.codex_chat_test = true

local state = require("codex.state")
local panel = require("codex.chat_panel")

local created_buffers = {}

local function valid_window(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function valid_buffer(bufnr)
	return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

local function close_panel()
	pcall(panel.close)
end

local function reset_state()
	close_panel()
	for _, bufnr in ipairs(created_buffers) do
		if valid_buffer(bufnr) then
			pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
		end
	end
	created_buffers = {}

	for key, _ in pairs(state) do
		state[key] = nil
	end

	state.codex_chat_line_highlights = {}
	state.codex_chat_line_to_buf = {}
	state.codex_deleted_jobs = {}
	state.codex_session_order = {}
	state.codex_sessions = {}
	state.next_codex_session_id = 1
end

local function make_session(id)
	local bufnr = vim.api.nvim_create_buf(false, true)
	table.insert(created_buffers, bufnr)
	vim.api.nvim_buf_set_name(bufnr, "codex-test-chat-" .. id)
	vim.b[bufnr].codex_chat = true
	vim.b[bufnr].codex_session_id = id

	local session = {
		id = id,
		bufnr = bufnr,
		cwd = vim.fn.getcwd(),
		started_at = os.time(),
		task_status = "IDLE",
	}

	state.codex_sessions[bufnr] = session
	table.insert(state.codex_session_order, bufnr)
	return session
end

local function first_mapped_line()
	local first_line = nil
	for line, _ in pairs(state.codex_chat_line_to_buf) do
		if not first_line or line < first_line then
			first_line = line
		end
	end
	return first_line
end

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local tests = {}

tests["new panel opens on first selectable chat row"] = function()
	reset_state()
	make_session(1)
	local newest = make_session(2)

	panel.open()

	assert_equal(valid_window(state.codex_chat_buffers_win), true, "chat buffers window")
	assert_equal(vim.api.nvim_win_get_cursor(state.codex_chat_buffers_win)[1], first_mapped_line(), "cursor line")
	assert_equal(panel.selected(), newest.bufnr, "selected chat")
end

tests["empty panel opens without a selectable row"] = function()
	reset_state()

	local ok, err = pcall(panel.open)

	assert_equal(ok, true, "panel.open result: " .. tostring(err))
	assert_equal(valid_window(state.codex_chat_buffers_win), true, "chat buffers window")
	assert_equal(first_mapped_line(), nil, "first mapped line")
	local cursor = vim.api.nvim_win_get_cursor(state.codex_chat_buffers_win)
	local line_count = vim.api.nvim_buf_line_count(state.codex_chat_buffers_buf)
	assert_equal(cursor[1] >= 1 and cursor[1] <= line_count, true, "cursor remains valid")
end

tests["refresh and already-open focus preserve current row"] = function()
	reset_state()
	make_session(1)
	make_session(2)

	panel.open()
	local first_line = first_mapped_line()
	local manual_line = first_line + 1
	vim.api.nvim_win_set_cursor(state.codex_chat_buffers_win, { manual_line, 0 })

	panel.refresh_open()
	assert_equal(vim.api.nvim_win_get_cursor(state.codex_chat_buffers_win)[1], manual_line, "refresh cursor line")

	panel.open()
	assert_equal(vim.api.nvim_win_get_cursor(state.codex_chat_buffers_win)[1], manual_line, "already-open cursor line")
end

for name, test in pairs(tests) do
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

reset_state()
print("codex_chat_panel_cursor_spec.lua: ok")
