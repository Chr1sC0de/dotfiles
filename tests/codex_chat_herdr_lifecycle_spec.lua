vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:append(".")
package.path = table.concat({
	vim.fn.getcwd() .. "/config/nvim/lua/?.lua",
	vim.fn.getcwd() .. "/config/nvim/lua/?/init.lua",
	package.path,
}, ";")

vim.g.codex_chat_test = true

local chat = require("codex.chat")
local herdr = require("codex.herdr")
local state = require("codex.state")

vim.notify = function() end

local function assert_equal(actual, expected, label)
	if not vim.deep_equal(actual, expected) then
		error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function reset_state()
	state.codex_active_buf = nil
	state.codex_buf = nil
	state.codex_deleted_jobs = {}
	state.codex_job_id = nil
	state.codex_session_order = {}
	state.codex_sessions = {}
	state.next_codex_session_id = 1
end

local function make_session(job_id)
	reset_state()
	local bufnr = vim.api.nvim_create_buf(false, true)
	local session = {
		id = 1,
		bufnr = bufnr,
		cwd = vim.fn.getcwd(),
		started_at = os.time(),
		job_id = job_id,
		exited = false,
		launch_mode = "herdr",
		launch_status = "attached",
		herdr_agent_name = "nvim-codex-test-1",
		herdr_pane_id = "w1:p2",
		herdr_route_path = "/tmp/codex-test.route",
		herdr_tab_id = "w1:t2",
		task_status = "IDLE",
	}

	vim.b[bufnr].codex_chat = true
	vim.b[bufnr].codex_session_id = session.id
	vim.b[bufnr].codex_job_id = job_id
	state.codex_sessions[bufnr] = session
	state.codex_session_order = { bufnr }
	state.codex_active_buf = bufnr
	state.codex_buf = bufnr
	state.codex_job_id = job_id
	return session
end

local tests = {}

tests["chat buffers show persistent virtual keybinding help"] = function()
	local bufnr = vim.api.nvim_create_buf(false, true)
	local session = {
		id = 9,
		bufnr = bufnr,
		cwd = vim.fn.getcwd(),
		started_at = os.time(),
		launch_mode = "direct",
		launch_status = "starting",
		task_status = "IDLE",
	}
	chat._test.initialize_chat_buffer(session)
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, chat._test.chat_help_namespace, 0, -1, { details = true })
	assert_equal(#marks, 1, "help extmark")
	local text = marks[1][4].virt_lines[1][1][1]
	assert_equal(text:find("<leader>aa toggle", 1, true) ~= nil, true, "toggle help")
	assert_equal(text:find("<leader>an new", 1, true) ~= nil, true, "new chat help")
	vim.api.nvim_buf_delete(bufnr, { force = true })
	state.codex_sessions[bufnr] = nil
end

tests["attachment loss preserves a live Herdr agent"] = function()
	local session = make_session(41)
	local close_calls = 0
	local original_agent_exists = herdr.agent_exists
	local original_close_pane = herdr.close_pane
	herdr.agent_exists = function(_, callback)
		callback(true, {})
	end
	herdr.close_pane = function()
		close_calls = close_calls + 1
	end

	chat._test.handle_herdr_attachment_exit(session, 41, 0)
	assert_equal(
		vim.wait(1000, function()
			return session.launch_status == "detached"
		end),
		true,
		"detach callback"
	)
	assert_equal(state.codex_sessions[session.bufnr], session, "session retained")
	assert_equal(vim.api.nvim_buf_is_valid(session.bufnr), true, "buffer retained")
	assert_equal(state.codex_active_buf, nil, "active target cleared")
	assert_equal(close_calls, 0, "pane not closed")

	herdr.agent_exists = original_agent_exists
	herdr.close_pane = original_close_pane
	vim.api.nvim_buf_delete(session.bufnr, { force = true })
end

tests["agent exit closes the owned pane and deletes the buffer"] = function()
	local session = make_session(42)
	local bufnr = session.bufnr
	local replacement_bufnr = vim.api.nvim_create_buf(false, true)
	local replacement = {
		id = 2,
		bufnr = replacement_bufnr,
		cwd = vim.fn.getcwd(),
		started_at = os.time(),
		exited = false,
		launch_mode = "herdr",
		launch_status = "starting",
		task_status = "IDLE",
	}
	vim.b[replacement_bufnr].codex_chat = true
	vim.b[replacement_bufnr].codex_session_id = replacement.id
	state.codex_sessions[replacement_bufnr] = replacement
	state.codex_session_order = { bufnr, replacement_bufnr }
	local close_calls = 0
	local route_removals = 0
	local original_agent_exists = herdr.agent_exists
	local original_close_pane = herdr.close_pane
	local original_remove_route = herdr.remove_route
	herdr.agent_exists = function(_, callback)
		callback(false, {})
	end
	herdr.close_pane = function(target)
		assert_equal(target.herdr_pane_id, "w1:p2", "closed pane")
		close_calls = close_calls + 1
	end
	herdr.remove_route = function(target)
		assert_equal(target.herdr_route_path, "/tmp/codex-test.route", "removed route")
		route_removals = route_removals + 1
	end

	chat._test.handle_herdr_attachment_exit(session, 42, 23)
	assert_equal(
		vim.wait(1000, function()
			return state.codex_sessions[bufnr] == nil
		end),
		true,
		"exit callback"
	)
	assert_equal(vim.api.nvim_buf_is_valid(bufnr), false, "buffer deleted")
	assert_equal(state.codex_active_buf, replacement_bufnr, "replacement activated")
	assert_equal(close_calls, 1, "fallback pane close")
	assert_equal(route_removals, 1, "route cleanup")

	herdr.agent_exists = original_agent_exists
	herdr.close_pane = original_close_pane
	herdr.remove_route = original_remove_route
	vim.api.nvim_buf_delete(replacement_bufnr, { force = true })
end

tests["explicit deletion suppresses attachment-exit cleanup"] = function()
	local session = make_session(43)
	local agent_checks = 0
	local original_agent_exists = herdr.agent_exists
	herdr.agent_exists = function()
		agent_checks = agent_checks + 1
	end
	state.codex_deleted_jobs[43] = true

	chat._test.handle_herdr_attachment_exit(session, 43, 0)
	assert_equal(state.codex_deleted_jobs[43], nil, "deletion marker consumed")
	assert_equal(state.codex_sessions[session.bufnr], session, "session left to delete callback")
	assert_equal(agent_checks, 0, "agent lookup suppressed")

	herdr.agent_exists = original_agent_exists
	vim.api.nvim_buf_delete(session.bufnr, { force = true })
end

for name, test in pairs(tests) do
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

print("codex_chat_herdr_lifecycle_spec.lua: ok")
