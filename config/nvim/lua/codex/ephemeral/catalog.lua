local util = require("codex.util")

local M = {}
local TIMEOUT_MS = 10000

local function append_choices(choices, seen, models, cached)
	for _, entry in ipairs(models) do
		if type(entry) == "table" then
			local id = cached and entry.slug or entry.model
			local visible = cached and entry.visibility == "list" or (not cached and entry.hidden ~= true)
			if visible and type(id) == "string" and id ~= "" and not seen[id] then
				local label = cached and entry.display_name or entry.displayName
				seen[id] = true
				table.insert(choices, { model = id, label = type(label) == "string" and label ~= "" and label or id })
			end
		end
	end
end

local function cached_choices()
	local home = vim.env.CODEX_HOME
	if not home or home == "" then
		home = util.join_path(vim.fn.expand("~"), ".codex")
	end
	local ok, value = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(util.join_path(home, "models_cache.json")), "\n"))
	end)
	if not ok or type(value) ~= "table" or type(value.models) ~= "table" then
		return {}
	end
	local choices = {}
	append_choices(choices, {}, value.models, true)
	return choices
end

-- Returns a cancellation function. Cancellation deliberately delivers no result.
function M.fetch(callback)
	local done, job, timer = false, nil, nil
	local pending, request_id, stage = "", 1, "initialize"
	local choices, seen, cursors = {}, {}, {}

	local function cleanup()
		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end
		if job and job > 0 then
			pcall(vim.fn.chanclose, job, "stdin")
			pcall(vim.fn.jobstop, job)
		end
	end

	local function finish(err)
		if done then
			return
		end
		done = true
		cleanup()
		local result = err and cached_choices() or choices
		vim.schedule(function()
			callback(result, err and (#result > 0 and "cached" or "unavailable") or "live", err)
		end)
	end

	local function send(message)
		local ok, sent = pcall(vim.fn.chansend, job, vim.json.encode(message) .. "\n")
		if not ok or sent == 0 then
			finish("could not send catalog request")
			return false
		end
		return true
	end

	local function list(cursor)
		stage = "models"
		request_id = request_id + 1
		send({
			id = request_id,
			method = "model/list",
			params = { limit = 100, includeHidden = false, cursor = cursor },
		})
	end

	local function receive(line)
		if done or line == "" then
			return
		end
		local ok, message = pcall(vim.json.decode, line)
		if not ok or type(message) ~= "table" then
			finish("invalid catalog response")
			return
		end
		if message.id ~= request_id then
			return
		end
		if message.error or type(message.result) ~= "table" then
			finish("Codex rejected the catalog request")
			return
		end
		if stage == "initialize" then
			if send({ method = "initialized", params = vim.empty_dict() }) then
				list()
			end
			return
		end
		local result = message.result
		if type(result.data) ~= "table" or not vim.islist(result.data) then
			finish("invalid model catalog")
			return
		end
		append_choices(choices, seen, result.data, false)
		local cursor = result.nextCursor
		if cursor == nil or cursor == vim.NIL then
			finish()
		elseif type(cursor) ~= "string" or cursor == "" or cursors[cursor] then
			finish("invalid catalog pagination")
		else
			cursors[cursor] = true
			list(cursor)
		end
	end

	local binary = vim.env.CODEX_REAL_BIN
	if not binary or binary == "" then
		binary = "codex"
	end
	local ok, result = pcall(vim.fn.jobstart, { binary, "app-server", "--listen", "stdio://" }, {
		stdin = "pipe",
		on_stdout = function(_, data)
			if done or not data then
				return
			end
			pending = pending .. table.concat(data, "\n")
			while not done do
				local newline = pending:find("\n", 1, true)
				if not newline then
					break
				end
				local line = pending:sub(1, newline - 1)
				pending = pending:sub(newline + 1)
				receive(line)
			end
		end,
		on_exit = function()
			finish("Codex exited before returning the model catalog")
		end,
	})
	if not ok or result <= 0 then
		finish("could not start Codex model discovery")
	else
		job = result
		timer = vim.uv.new_timer()
		timer:start(
			TIMEOUT_MS,
			0,
			vim.schedule_wrap(function()
				finish("model discovery timed out")
			end)
		)
		send({
			id = request_id,
			method = "initialize",
			params = { clientInfo = { name = "nvim_codex_models", title = "Neovim Codex Models", version = "1.0.0" } },
		})
	end
	return function()
		if not done then
			done = true
			cleanup()
		end
	end
end

return M
