local M = {}

-- ============================================================
-- Configuration
-- ============================================================

M.tmpfile = vim.fn.stdpath("cache") .. "/nvim_sql.sql"

-- ============================================================
-- Find SQL injection under cursor
-- ============================================================

local function position_in_range(row, col, sr, sc, er, ec)
	return (row > sr or (row == sr and col >= sc)) and (row < er or (row == er and col < ec))
end

local function get_node_text(bufnr, sr, sc, er, ec)
	return table.concat(vim.api.nvim_buf_get_text(bufnr, sr, sc, er, ec, {}), "\n")
end

local function get_python_string_body(node)
	while node and node:type() ~= "string" do
		node = node:parent()
	end

	if not node then
		return nil
	end

	local string_start
	local string_end

	for child in node:iter_children() do
		if child:type() == "string_start" then
			string_start = child
		elseif child:type() == "string_end" then
			string_end = child
		end
	end

	if not string_start or not string_end then
		return nil
	end

	local _, _, sr, sc = string_start:range()
	local er, ec = string_end:range()

	return sr, sc, er, ec
end

local function get_sql_text(bufnr)
	local parser = vim.treesitter.get_parser(bufnr)

	if not parser then
		return nil
	end

	parser:parse()

	local trees = parser:trees()

	if #trees == 0 then
		return nil
	end

	local tree = trees[1]
	local root = tree:root()

	local cursor = vim.api.nvim_win_get_cursor(0)

	local row = cursor[1] - 1
	local col = cursor[2]

	-- Find the smallest node containing the cursor.
	local node = root:named_descendant_for_range({
		row,
		col,
		row,
		col,
	})

	if not node then
		return nil
	end

	-- Walk upwards looking for the node that represents
	-- the injected SQL content.
	--
	-- This assumes your injection query looks roughly like:
	--
	--   (string_content) @injection.content
	--
	-- or:
	--
	--   (string (string_content) @injection.content)
	--
	--
	-- Because "injection.content" is a capture rather than
	-- a node type, we inspect the injection query below.

	local lang = parser:lang()

	local query = vim.treesitter.query.get(lang, "injections")

	if not query then
		return nil
	end

	for id, capture_node, metadata in query:iter_captures(root, bufnr, 0, -1) do
		local capture_name = query.captures[id]

		if capture_name == "injection.content" and metadata["injection.language"] == "sql" then
			if lang == "python" then
				local sr, sc, er, ec = get_python_string_body(capture_node)

				if sr and position_in_range(row, col, sr, sc, er, ec) then
					return get_node_text(bufnr, sr, sc, er, ec)
				end
			end

			local sr, sc, er, ec = capture_node:range()

			if position_in_range(row, col, sr, sc, er, ec) then
				return vim.treesitter.get_node_text(capture_node, bufnr)
			end
		end
	end

	return nil
end

-- ============================================================
-- Create/load temp buffer
-- ============================================================

local function get_tmp_buffer()
	local buf = vim.fn.bufadd(M.tmpfile)

	vim.fn.bufload(buf)

	-- Make sure Conform sees this as SQL.
	vim.bo[buf].filetype = "sql"

	return buf
end

-- ============================================================
-- Run Conform
-- ============================================================

local function format_with_conform(bufnr)
	local conform = require("conform")

	local ok, err = pcall(function()
		conform.format({
			bufnr = bufnr,
			async = false,
			lsp_fallback = true,
		})
	end)

	if not ok then
		vim.notify("Conform failed: " .. tostring(err), vim.log.levels.ERROR)

		return false
	end

	return true
end

-- ============================================================
-- Main command
-- ============================================================

function M.sql_to_tmp()
	local source_buf = vim.api.nvim_get_current_buf()

	local sql = get_sql_text(source_buf)

	if not sql then
		vim.notify("No SQL block found under cursor", vim.log.levels.WARN)

		return
	end

	if sql == "" then
		vim.notify("SQL block is empty", vim.log.levels.WARN)

		return
	end

	-- Ensure ~/.cache/nvim exists.
	vim.fn.mkdir(vim.fn.fnamemodify(M.tmpfile, ":h"), "p")

	-- Write raw SQL to temp file.
	vim.fn.writefile(
		vim.split(sql, "\n", {
			plain = true,
		}),
		M.tmpfile
	)

	-- Load the temp file as a buffer.
	local tmp_buf = get_tmp_buffer()

	-- Run Conform.
	if not format_with_conform(tmp_buf) then
		return
	end

	-- Write formatted buffer back to disk.
	vim.api.nvim_buf_call(tmp_buf, function()
		vim.cmd("write")
	end)

	vim.notify("SQL extracted and formatted: " .. M.tmpfile, vim.log.levels.INFO)
end

-- ============================================================
-- User command
-- ============================================================

vim.api.nvim_create_user_command("SQLToTmp", function()
	M.sql_to_tmp()
end, {})

return M
