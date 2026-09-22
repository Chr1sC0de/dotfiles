-- Add the key mappings only for Markdown files in a zk notebook.
if require("zk.util").notebook_root(vim.fn.expand("%:p")) ~= nil then
	local function map(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, {
			buffer = 0,
			noremap = true,
			silent = false,
			desc = desc,
		})
	end

	-- Open the link under the caret.
	map("n", "<CR>", "<Cmd>lua vim.lsp.buf.definition()<CR>", "zk-nvim: Open link under caret")

	-- Create a new note after asking for its title.
	-- This overrides the global `<leader>zn` mapping to create the note in the same directory as the current buffer.
	map(
		"n",
		"<leader>zn",
		"<Cmd>ZkNew { dir = vim.fn.expand('%:p:h'), title = vim.fn.input('Title: ') }<CR>",
		"zk-nvim: Create note in current directory"
	)

	-- Create a new note in the same directory as the current buffer, using the current selection for title.
	map(
		"v",
		"<leader>znt",
		":'<,'>ZkNewFromTitleSelection { dir = vim.fn.expand('%:p:h') }<CR>",
		"zk-nvim: Create note from selection as title"
	)

	-- Create a new note in the same directory as the current buffer, using the current selection for note content and asking for its title.
	map(
		"v",
		"<leader>znc",
		":'<,'>ZkNewFromContentSelection { dir = vim.fn.expand('%:p:h'), title = vim.fn.input('Title: ') }<CR>",
		"zk-nvim: Create note from selection as content"
	)

	-- Open notes linking to the current buffer.
	map("n", "<leader>zb", "<Cmd>ZkBacklinks<CR>", "zk-nvim: Show backlinks")

	-- Open notes linked by the current buffer.
	map("n", "<leader>zl", "<Cmd>ZkLinks<CR>", "zk-nvim: Show linked notes")

	-- Preview a linked note.
	map("n", "K", "<Cmd>lua vim.lsp.buf.hover()<CR>", "zk-nvim: Preview linked note")

	-- Open the code actions for a visual selection.
	map("v", "<leader>za", ":'<,'>lua vim.lsp.buf.range_code_action()<CR>", "zk-nvim: Show code actions")
end
