-- Live ANSI snapshots rendered into one Snacks terminal buffer.
local M = {}
local INTERVAL_MS = 100
local ESC = "\27["

-- Crop by display cells, never by bytes or escape-sequence length. Keep SGR
-- state across rows, including changes beyond the right edge of the preview.
local function rows(snapshot, width, height)
	local result, style = {}, ""
	for _, line in ipairs(vim.split(snapshot:gsub("\r\n", "\n"), "\n", { plain = true })) do
		if #result == height then
			break
		end
		local parts, col, offset = { ESC .. "0m", ESC .. "2K", style }, 0, 1
		while offset <= #line do
			local sgr = line:match("^\27%[[%d;:]*m", offset)
			if sgr then
				if sgr == ESC .. "0m" or sgr == ESC .. "m" then
					style = ""
				else
					style = style .. sgr
				end
				parts[#parts + 1] = sgr
				offset = offset + #sgr
			else
				local control = line:match("^\27%[[0-?]*[ -/]*[@-~]", offset)
				local char = line:match("^[%z\1-\127\194-\244][\128-\191]*", offset)
				if control then
					offset = offset + #control
				elseif char then
					offset = offset + #char
					if char == "\t" then
						char = string.rep(" ", 8 - col % 8)
					end
					if not char:find("[%z\1-\31\127]") then
						local cells = vim.fn.strdisplaywidth(char, col)
						if col + cells <= width then
							parts[#parts + 1] = char
						end
						col = col + cells
					end
				else
					offset = offset + 1
				end
			end
		end
		-- Clear before painting: erase-to-end after a full-width row would erase
		-- its last cell with terminal autowrap disabled.
		result[#result + 1] = table.concat(parts) .. ESC .. "0m"
	end
	while #result < height do
		result[#result + 1] = ESC .. "0m" .. ESC .. "2K"
	end
	return result
end

-- Use Snacks to establish its normal preview-buffer lifecycle and terminal.
-- The initial command is finite; subsequent captures never accumulate history.
function M.cmd(command, ctx, opts)
	local job = require("snacks.picker.preview").cmd(command, ctx, opts)
	if not job or not job.chan then
		return job
	end
	local buf, win, chan = job.buf, ctx.win, job.chan
	local timer = assert(vim.uv.new_timer())
	local stopped, pending, previous, size = false, nil, {}, ""
	local group = vim.api.nvim_create_augroup("workmux.agent_preview." .. buf, { clear = true })
	local function stop()
		if stopped then
			return
		end
		stopped = true
		timer:stop()
		timer:close()
		if pending then
			pending:kill(15)
			pending = nil
		end
		job:stop()
		pcall(vim.api.nvim_del_augroup_by_id, group)
	end
	local function valid()
		return not stopped
			and vim.api.nvim_buf_is_valid(buf)
			and vim.api.nvim_win_is_valid(win)
			and vim.api.nvim_win_get_buf(win) == buf
	end
	local function render(snapshot)
		local width, height = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
		local dimensions = width .. ":" .. height
		if size ~= dimensions then
			previous = {}
			size = dimensions
		end
		local current = rows(snapshot, width, height)
		local output = { ESC .. "?7l", ESC .. "?25l" }
		for row = 1, #current do
			if current[row] ~= previous[row] then
				output[#output + 1] = ESC .. row .. ";1H" .. current[row]
			end
		end
		if #output > 2 then
			output[#output + 1] = ESC .. "1;1H"
			vim.api.nvim_chan_send(chan, table.concat(output))
		end
		previous = current
	end
	local poll
	local function completed(result)
		pending = nil
		if not valid() then
			stop()
			return
		end
		if result.code ~= 0 then
			ctx.preview:set_title("Agent preview unavailable")
			stop()
			return
		end
		render(result.stdout or "")
		-- Schedule after completion: slow reads cannot overlap or queue up.
		timer:start(INTERVAL_MS, 0, vim.schedule_wrap(poll))
	end
	poll = function()
		if not valid() then
			stop()
			return
		end
		local ok, process = pcall(vim.system, command, { timeout = 2000 }, vim.schedule_wrap(completed))
		if ok then
			pending = process
		else
			stop()
		end
	end
	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete", "BufWinLeave" }, {
		group = group,
		buffer = buf,
		callback = stop,
	})
	vim.api.nvim_create_autocmd("WinClosed", { group = group, pattern = tostring(win), callback = stop })
	vim.bo[buf].scrollback = 0
	-- Buffer complete snapshots before painting; streaming fragments can show
	-- half a frame and briefly erase its background. Snacks dispatches through
	-- these methods, so its initial job uses the same renderer as later polls.
	local chunks = { "" }
	job.on_output = function(_, data)
		if stopped or #chunks == 0 then
			return
		end
		chunks[#chunks] = chunks[#chunks] .. data[1]
		vim.list_extend(chunks, data, 2)
	end
	job.on_exit = function(_, code)
		local snapshot = table.concat(chunks, "\n")
		chunks = {}
		completed({ code = code, stdout = snapshot })
	end
	-- Bound the first capture too, before periodic captures take over.
	timer:start(
		2000,
		0,
		vim.schedule_wrap(function()
			if valid() then
				ctx.preview:set_title("Agent preview timed out")
			end
			stop()
		end)
	)
	return job
end

M._rows = rows
return M
