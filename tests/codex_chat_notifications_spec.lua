vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")
vim.opt.runtimepath:append(".")
package.path = table.concat({
	vim.fn.getcwd() .. "/config/nvim/lua/?.lua",
	vim.fn.getcwd() .. "/config/nvim/lua/?/init.lua",
	package.path,
}, ";")

vim.g.codex_chat_test = true

local state = require("codex.state")
local chat = require("codex.chat")

local notifications = {}
vim.notify = function(message, level, opts)
	table.insert(notifications, {
		message = tostring(message),
		level = level,
		opts = opts,
	})
end

local function reset_state()
	for key, _ in pairs(state) do
		state[key] = nil
	end

	state.codex_deleted_jobs = {}
	state.codex_session_order = {}
	state.codex_sessions = {}
	state.next_codex_session_id = 1
	state.codex_hook_token = "test-token"
	notifications = {}
end

local function make_session()
	reset_state()

	local bufnr = vim.api.nvim_create_buf(false, true)
	local session = {
		id = 1,
		bufnr = bufnr,
		cwd = vim.fn.getcwd(),
		started_at = os.time(),
		task_status = "IDLE",
		task_generation = 0,
		hook_started_with_env = true,
		hook_token = state.codex_hook_token,
	}

	vim.b[bufnr].codex_chat = true
	vim.b[bufnr].codex_session_id = session.id
	state.codex_sessions[bufnr] = session
	state.codex_session_order = { bufnr }

	return session
end

local function send_hook(event)
	local payload = table.concat({
		"1",
		state.codex_hook_token,
		vim.json.encode(event),
	}, "\n")

	assert(chat.handle_hook_event(vim.base64.encode(payload)) == true)
end

local function messages()
	local result = {}
	for _, notification in ipairs(notifications) do
		table.insert(result, notification.message)
	end
	return table.concat(result, "\n")
end

local function assert_equal(actual, expected, label)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s\n%s", label, vim.inspect(expected), vim.inspect(actual), messages()))
	end
end

local function assert_contains(haystack, needle, label)
	if not haystack:find(needle, 1, true) then
		error(string.format("%s: expected %q in %q", label, needle, haystack))
	end
end

local tests = {}

tests["UserPromptSubmit followed by ordinary Stop emits one completion"] = function()
	make_session()

	send_hook({ hook_event_name = "UserPromptSubmit", turn_id = "turn-1" })
	send_hook({ hook_event_name = "Stop", turn_id = "turn-1", last_assistant_message = "Implemented and verified." })

	assert_equal(#notifications, 1, "notification count")
	assert_contains(notifications[1].message, "Codex task completed", "completion notification")
end

tests["duplicate Stop does not duplicate completion"] = function()
	make_session()

	send_hook({ hook_event_name = "UserPromptSubmit", turn_id = "turn-1" })
	send_hook({ hook_event_name = "Stop", turn_id = "turn-1", last_assistant_message = "Done." })
	send_hook({ hook_event_name = "Stop", turn_id = "turn-1", last_assistant_message = "Done." })

	assert_equal(#notifications, 1, "notification count")
	assert_contains(notifications[1].message, "Codex task completed", "completion notification")
end

tests["PermissionRequest emits one input-required notification"] = function()
	make_session()

	send_hook({ hook_event_name = "UserPromptSubmit", turn_id = "turn-1" })
	send_hook({
		hook_event_name = "PermissionRequest",
		tool_use_id = "tool-1",
		tool_name = "Bash",
		tool_input = { command = "npm test" },
	})
	send_hook({
		hook_event_name = "PermissionRequest",
		tool_use_id = "tool-1",
		tool_name = "Bash",
		tool_input = { command = "npm test" },
	})

	assert_equal(#notifications, 1, "notification count")
	assert_contains(notifications[1].message, "Codex needs input", "input notification")
end

tests["Stop with direct question emits input-required notification"] = function()
	make_session()

	send_hook({ hook_event_name = "UserPromptSubmit", turn_id = "turn-1" })
	send_hook({
		hook_event_name = "Stop",
		turn_id = "turn-1",
		last_assistant_message = "I found two implementations. Which option should I use?",
	})

	assert_equal(#notifications, 1, "notification count")
	assert_contains(notifications[1].message, "Codex needs input", "input notification")
end

tests["Stop with optional follow-up wording does not emit input-required notification"] = function()
	make_session()

	send_hook({ hook_event_name = "UserPromptSubmit", turn_id = "turn-1" })
	send_hook({
		hook_event_name = "Stop",
		turn_id = "turn-1",
		last_assistant_message = "Implemented and tested. I can also add more coverage if you want.",
	})

	assert_equal(#notifications, 1, "notification count")
	assert_contains(notifications[1].message, "Codex task completed", "completion notification")
end

tests["direct question plus optional wording still emits input-required notification"] = function()
	make_session()

	send_hook({ hook_event_name = "UserPromptSubmit", turn_id = "turn-1" })
	send_hook({
		hook_event_name = "Stop",
		turn_id = "turn-1",
		last_assistant_message = "I can also add more coverage if you want. Do you want that now?",
	})

	assert_equal(#notifications, 1, "notification count")
	assert_contains(notifications[1].message, "Codex needs input", "input notification")
end

tests["terminal and idle status changes do not emit desktop notifications"] = function()
	local session = make_session()

	chat._test.mark_task_activity(session, { force = true, source = "terminal" })
	chat._test.set_task_status(session, "DONE", { source = "quiet" })
	chat._test.mark_task_waiting(session, "approval prompt", "terminal-wait", { source = "terminal", force = true })

	assert_equal(#notifications, 0, "notification count")
end

for name, test in pairs(tests) do
	local ok, err = xpcall(test, debug.traceback)
	if not ok then
		error(name .. "\n" .. err)
	end
end

print("codex_chat_notifications_spec.lua: ok")
