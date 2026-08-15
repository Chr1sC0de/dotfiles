vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/config/nvim")

local formatter_calls = 0

package.loaded.conform = {
	format = function()
		formatter_calls = formatter_calls + 1
	end,
}

local sql_to_temp = require("user-commands.sql-to-temp")

local function extract(lines, cursor)
	local source_buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_set_current_buf(source_buf)
	vim.bo[source_buf].filetype = "python"
	vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, cursor)
	vim.treesitter.start(source_buf, "python")

	local tmpfile = vim.fn.tempname() .. ".sql"

	sql_to_temp.tmpfile = tmpfile
	sql_to_temp.sql_to_tmp()

	local extracted = table.concat(vim.fn.readfile(tmpfile), "\n")

	vim.api.nvim_buf_delete(source_buf, { force = true })
	vim.fn.delete(tmpfile)

	return extracted
end

local plain_sql = extract({
	'some_sql = """',
	"SELECT *",
	"FROM users",
	'"""',
}, { 2, 3 })

assert(plain_sql == "SELECT *\nFROM users", "plain SQL string should be extracted without delimiters")

local fstring_lines = {
	'user_sql = f"""',
	"SELECT *",
	"FROM users",
	"WHERE id = {user_id}",
	'"""',
}
local expected_fstring = "SELECT *\nFROM users\nWHERE id = {user_id}"

assert(extract(fstring_lines, { 2, 3 }) == expected_fstring, "cursor before interpolation should extract full f-string")
assert(extract(fstring_lines, { 4, 14 }) == expected_fstring, "cursor on interpolation should extract full f-string")
assert(extract(fstring_lines, { 4, 20 }) == expected_fstring, "cursor after interpolation should extract full f-string")

local multiple_interpolations = extract({
	'user_sql = f"SELECT {column!r} FROM {table_name} WHERE id = {user_id}"',
}, { 1, 40 })

assert(
	multiple_interpolations == "SELECT {column!r} FROM {table_name} WHERE id = {user_id}",
	"multiple interpolations should be preserved verbatim"
)

local tab_indented = extract({
	'user_sql = f"""',
	"\t\tSELECT",
	"\t\t\t{column},",
	"\t\t\tother_column",
	"\t\tFROM {table_name}",
	'"""',
}, { 3, 4 })

assert(
	tab_indented == "SELECT\n\t{column},\n\tother_column\nFROM {table_name}",
	"common tabs should be removed while relative indentation is preserved"
)

local space_indented = extract({
	'user_sql = """',
	"    SELECT",
	"      nested_column",
	"    FROM users",
	'"""',
}, { 3, 8 })

assert(
	space_indented == "SELECT\n  nested_column\nFROM users",
	"common spaces should be removed while relative indentation is preserved"
)

local notifications = {}
local original_notify = vim.notify

vim.notify = function(message, level)
	table.insert(notifications, { message = message, level = level })
end

local non_sql_buf = vim.api.nvim_create_buf(false, true)

vim.api.nvim_set_current_buf(non_sql_buf)
vim.bo[non_sql_buf].filetype = "python"
vim.api.nvim_buf_set_lines(non_sql_buf, 0, -1, false, { 'some_bash = "echo hello"' })
vim.api.nvim_win_set_cursor(0, { 1, 15 })
vim.treesitter.start(non_sql_buf, "python")
sql_to_temp.sql_to_tmp()

vim.notify = original_notify

assert(#notifications == 1, "non-SQL injection should produce one notification")
assert(notifications[1].message == "No SQL block found under cursor", "non-SQL injection should be rejected")

notifications = {}
vim.notify = function(message, level)
	table.insert(notifications, { message = message, level = level })
end

local empty_sql_buf = vim.api.nvim_create_buf(false, true)

vim.api.nvim_set_current_buf(empty_sql_buf)
vim.bo[empty_sql_buf].filetype = "python"
vim.api.nvim_buf_set_lines(empty_sql_buf, 0, -1, false, {
	'empty_sql = """',
	"\t\t",
	'"""',
})
vim.api.nvim_win_set_cursor(0, { 2, 1 })
vim.treesitter.start(empty_sql_buf, "python")

local calls_before_empty_sql = formatter_calls

sql_to_temp.sql_to_tmp()
vim.notify = original_notify

assert(#notifications == 1, "empty SQL should produce one notification")
assert(notifications[1].message == "SQL block is empty", "normalized empty SQL should be rejected")
assert(formatter_calls == calls_before_empty_sql, "empty SQL should not trigger formatting")
