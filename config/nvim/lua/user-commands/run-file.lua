-- command to run file
vim.api.nvim_create_user_command("RunFile", function()
	local file = vim.fn.expand("%:p")

	vim.cmd("botright split")
	vim.cmd("terminal " .. vim.fn.shellescape(file))

	local buf = vim.api.nvim_get_current_buf()
	vim.bo[buf].bufhidden = "wipe"

	vim.cmd("startinsert")
end, {})
