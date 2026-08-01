if not vim.g.vscode then
	vim.cmd.colorscheme("catppuccin-nvim")
end

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.autoread = true

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
	desc = "Reload files changed outside Neovim",
	command = "checktime",
})

vim.api.nvim_create_autocmd("FileChangedShellPost", {
	desc = "Redraw after external file changes",
	command = "redraw!",
})

-- vim.cmd("hi Normal guibg=NONE ctermbg=NONE")

-- Set a color for all line numbers
vim.cmd("hi LineNrAbove guifg=#888888 guibg=NONE")
vim.cmd("hi LineNr guifg=#d3e0eb guibg=NONE")
vim.cmd("hi LineNrBelow guifg=#888888 guibg=NONE")

-- disable swap files
---@diagnostic disable-next-line: undefined-field
local home = vim.loop.os_homedir()
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = home .. "/.vim/undodir"
vim.opt.undofile = true

-- incremental search
vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.scrolloff = 10
vim.opt.cmdheight = 2
vim.opt.conceallevel = 2

vim.opt.updatetime = 50
vim.opt.scrolloff = 10

vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4

vim.g.neovide_opacity = 0.4
vim.g.neovide_normal_opacity = 0.4

-- disable word wrappings

vim.o.wrap = false

-- enable exrc for workspace enabled

vim.o.exrc = true

--  allow treesitter to take priority for highlighting
vim.highlight.priorities.semantic_tokens = 95

-- adding filetypes

vim.filetype.add({
	pattern = {
		[".*%.sql%.j.*"] = "sql",
		[".*%.j2"] = "jinja",
		["Caddyfile"] = "caddy",
		[".*/%.vscode/.*%.json"] = "jsonc",
		[".*"] = {
			---@diagnostic disable-next-line: unused-local
			function(path, bufnr)
				local first_line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
				if first_line and first_line:match("^#!.*bash") then
					return "bash"
				end
			end,
		},
		[".*%.container"] = "ini",
		[".*%.pod"] = "ini",
		[".*%.volume"] = "ini",
		[".*%.network"] = "ini",
		[".sqruff"] = "ini",
		[".sqlfluff"] = "ini",
	},

	filename = {
		["CMakeLists.txt"] = "cmake",
	},
})

-- create command to route jinja injections

vim.treesitter.query.add_directive("inject-lang-jinja!", function(_, _, bufnr, _, metadata)
	local fname = vim.fs.basename(vim.api.nvim_buf_get_name(bufnr))
	local _, _, ext, _ = string.find(fname, ".*%.(%a+)(%.%a+)")
	if vim.tbl_contains({ "container", "pod", "volume", "network" }, ext) then
		metadata["injection.language"] = "ini"
	elseif vim.tbl_contains({ "sql" }, ext) then
		metadata["injection.language"] = "sql"
	end
	local _, _, caddyext = string.find(fname, "(Caddyfile)%..+")
	if vim.tbl_contains({ "Caddyfile" }, caddyext) then
		metadata["injection.language"] = "caddy"
	end
end, {})

vim.api.nvim_create_autocmd("TermOpen", {
	desc = "Enable relative line numbers in terminal buffers",
	callback = function()
		vim.opt_local.number = false
		vim.opt_local.relativenumber = false
	end,
})
