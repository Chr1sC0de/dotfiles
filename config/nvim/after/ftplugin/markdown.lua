-- Add the key mappings only for Markdown files in a zk notebook.
local function check_zk()
	if vim.fn.executable("zk") == 1 then
		if require("zk.util").notebook_root(vim.fn.expand("%:p")) ~= nil then
			return true
		end
	end
	return false
end

if check_zk() then
	local function map(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, {
			buffer = 0,
			noremap = true,
			silent = false,
			desc = desc,
		})
	end

	-- A cancelled or blank title must not create an untitled note.
	local function has_title(title)
		return title ~= nil and vim.trim(title) ~= ""
	end

	local function prompt_title()
		vim.fn.inputsave()
		local ok, title = pcall(vim.fn.input, "Title: ")
		vim.fn.inputrestore()
		if ok and has_title(title) then
			return title
		end
	end

	-- Open the link under the caret.
	map("n", "<CR>", "<Cmd>lua vim.lsp.buf.definition()<CR>", "zk-nvim: Open link under caret")

	-- Create a new note after asking for its title.
	-- This overrides the global `<leader>zn` mapping to create the note in the same directory as the current buffer.
	map("n", "<leader>zn", function()
		local title = prompt_title()
		if title then
			require("zk.commands").get("ZkNew")({ dir = vim.fn.expand("%:p:h"), title = title })
		end
	end, "zk-nvim: Create note in current directory")

	-- Create a new note in the same directory as the current buffer, using the current selection for title.
	map("v", "<leader>znt", function()
		vim.cmd("normal! \27")
		if has_title(require("zk.util").get_selected_text()) then
			require("zk.commands").get("ZkNewFromTitleSelection")({ dir = vim.fn.expand("%:p:h") })
		end
	end, "zk-nvim: Create note from selection as title")

	-- Create a new note in the same directory as the current buffer, using the current selection for note content and asking for its title.
	map("v", "<leader>znc", function()
		vim.cmd("normal! \27")
		local title = prompt_title()
		if title then
			require("zk.commands").get("ZkNewFromContentSelection")({
				dir = vim.fn.expand("%:p:h"),
				title = title,
			})
		end
	end, "zk-nvim: Create note from selection as content")

	-- Open notes linking to the current buffer.
	map("n", "<leader>zb", "<Cmd>ZkBacklinks<CR>", "zk-nvim: Show backlinks")

	-- Open notes linked by the current buffer.
	map("n", "<leader>zl", "<Cmd>ZkLinks<CR>", "zk-nvim: Show linked notes")

	-- Preview a linked note.
	map("n", "K", "<Cmd>lua vim.lsp.buf.hover()<CR>", "zk-nvim: Preview linked note")

	-- Open the code actions for a visual selection.
	map("v", "<leader>za", ":'<,'>lua vim.lsp.buf.range_code_action()<CR>", "zk-nvim: Show code actions")

	-- Open notes.
	vim.api.nvim_set_keymap(
		"n",
		"<leader>zo",
		"<Cmd>ZkNotes { sort = { 'modified' } }<CR>",
		{ desc = "zk-nvim: show notes" }
	)
	-- Open notes associated with the selected tags.
	vim.api.nvim_set_keymap("n", "<leader>zt", "<Cmd>ZkTags<CR>", { desc = "zk-nvim: open associated" })

	-- Search for the notes matching a given query.
	vim.api.nvim_set_keymap(
		"n",
		"<leader>zf",
		"<Cmd>ZkNotes { sort = { 'modified' }, match = { vim.fn.input('Search: ') } }<CR>",
		{ desc = "zk-nvim: search for notes matching a given query" }
	)
	-- Search for the notes matching the current visual selection.
	vim.api.nvim_set_keymap(
		"v",
		"<leader>zf",
		":'<,'>ZkMatch<CR>",
		{ desc = "zk-nvim: search for notes matching the current visual selection" }
	)
end
