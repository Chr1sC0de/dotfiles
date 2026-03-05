vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.keymap.set("n", "<c-s>", ":w<cr>", { desc = "Save file" })
vim.keymap.set("n", "<c-z>", "u", { desc = "Undo" })

-- SETUP A TOGGLE FOR THE VIRTUAL EDIT COMMAND
TOGGLE_VIRTUALEDIT = false
vim.opt.virtualedit = nil
vim.keymap.set("n", "<leader>ve", function()
	if TOGGLE_VIRTUALEDIT then
		print("Setting virtualedit=nil")
		vim.opt.virtualedit = nil
		TOGGLE_VIRTUALEDIT = true
	else
		print("Setting virtualedit=all")
		vim.opt.virtualedit = "all"
		TOGGLE_VIRTUALEDIT = true
	end
end, { desc = "Toggle virtualedit mode from nil <-> all" })

vim.keymap.set("n", "<leader>cc", ":cclose<cr>", { desc = "close quick fix list" })
vim.keymap.set("n", "<leader>ot", ":ObsidianTags<cr>", { desc = "Obsidian Tags" })

vim.keymap.set("n", "<C-Tab>", ":tabnext<cr>", { desc = "tabnext", silent = false })
vim.keymap.set("n", "<C-S-Tab>", ":tabprevious<cr>", { desc = "tabprevious", silent = false })

-- SORT IMPORTS
vim.keymap.set("n", "<leader>si", function()
	vim.lsp.buf.code_action({ context = { only = { "source.organizeImports" } }, apply = true })
end, { desc = "sort imports" })

-- copy paths
vim.keymap.set("n", "<leader>cp", function()
	local path = vim.fn.expand("%")
	vim.fn.setreg("+", path)
	print("Copied: " .. path)
end, { desc = "Copy relative path to clipboard" })

vim.keymap.set("n", "<leader>cP", function()
	local path = vim.fn.expand("%:p")
	vim.fn.setreg("+", path)
	print("Copied: " .. path)
end, { desc = "Copy absolute path to clipboard" })

-- Copy just filename to clipboard
vim.keymap.set("n", "<leader>cf", function()
	local filename = vim.fn.expand("%:t")
	vim.fn.setreg("+", filename)
	print("Copied: " .. filename)
end, { desc = "Copy filename to clipboard" })

-- toggle between terminals

-- Keymap to toggle last terminal or create a new one
local last_term_buf = nil

vim.keymap.set("n", "<leader>jt", function()
	-- If last terminal buffer exists and is valid, switch to it
	if last_term_buf and vim.api.nvim_buf_is_valid(last_term_buf) then
		vim.api.nvim_set_current_buf(last_term_buf)
	else
		-- Otherwise, create a new terminal
		vim.cmd("terminal")
		-- Save the new terminal buffer handle
		last_term_buf = vim.api.nvim_get_current_buf()
	end
end, { noremap = true, desc = "Toggle or create terminal" })

-- Optional: update last_term_buf when entering a terminal manually
vim.api.nvim_create_autocmd("TermOpen", {
	pattern = "*",
	callback = function(args)
		last_term_buf = args.buf
	end,
})

-- THE PRIMEGEN REMAPS --
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

vim.keymap.set("n", "J", "mzJ`z")
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

vim.keymap.set("x", "<leader>p", [["_dP]])

vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]])
vim.keymap.set({ "n", "v" }, "<c-c>", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])
vim.keymap.set({ "n", "v" }, "<leader>D", [["_d]])

vim.keymap.set("n", "Q", "<nop>")

vim.keymap.set("n", "<C-s-k>", "<cmd>cnext<CR>zz")
vim.keymap.set("n", "<C-s-j>", "<cmd>cprev<CR>zz")
vim.keymap.set("n", "<leader>ek", "<cmd>lnext<CR>zz")
vim.keymap.set("n", "<leader>ej", "<cmd>lprev<CR>zz")

vim.keymap.set(
	"n",
	"<leader>rw",
	[[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
	{ desc = "rename text under cursor" }
)
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

vim.keymap.set("n", "<leader>so", function()
	vim.cmd("so")
end)

vim.api.nvim_set_keymap("t", "<M-t>", [[<C-\><C-n>]], { noremap = true, desc = "exit terminal mode using escape" })

-- map global marks to lowercase

-- marking
for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
	local upper = c:upper()
	vim.keymap.set("n", "m" .. c, "m" .. upper)
end

-- jumping
for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
	local upper = c:upper()
	vim.keymap.set("n", "'" .. c, "'" .. upper)
end

-- jumping
for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
	local upper = c:upper()
	vim.keymap.set("n", "`" .. c, "'" .. upper)
end
