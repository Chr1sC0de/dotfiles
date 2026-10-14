if not vim.g.vscode then
	vim.cmd.colorscheme("catppuccin-nvim")
end

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.autoread = true

vim.opt.splitbelow = true

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
	filename = {
		["CMakeLists.txt"] = "cmake",
		[".env"] = "env",
		[".secrets"] = "env",
	},
	pattern = {
		[".*%.duckdbsql.j2"] = "duckdbsql",
		[".*%.duckdbsql.jinja"] = "duckdbsql",
		[".*%.j2"] = "jinja",
		[".*%.jinja"] = "jinja",
		["Caddyfile"] = "caddy",
		[".*gitconfig"] = "gitconfig",
		[".*tmux.conf"] = "tmux",
		[".*/%.vscode/.*%.json"] = "jsonc",
		[".*%.container"] = "ini",
		[".*%.pod"] = "ini",
		[".*%.volume"] = "ini",
		[".*%.network"] = "ini",
		[".sqruff"] = "ini",
		[".sqlfluff"] = "ini",
	},
})

-- Detect extensionless Bash and Python scripts when opened or saved.
vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
	group = vim.api.nvim_create_augroup("ExtensionlessScriptFiletype", { clear = true }),
	desc = "Detect extensionless Bash and Python scripts from their shebang",
	callback = function(event)
		local name = vim.api.nvim_buf_get_name(event.buf)
		if vim.bo[event.buf].buftype ~= "" or name == "" or vim.fn.fnamemodify(name, ":e") ~= "" then
			return
		end

		local first_line = vim.api.nvim_buf_get_lines(event.buf, 0, 1, false)[1] or ""

		local shebang = first_line:match("^#!%s*(.*)")
		if not shebang then
			return
		end

		local tokens = vim.split(shebang, "%s+", { trimempty = true })
		local index = 1

		if tokens[index] and vim.fs.basename(tokens[index]) == "env" then
			index = index + 1
			if tokens[index] == "-S" then
				index = index + 1
			end
		end

		local interpreter = tokens[index] and vim.fs.basename(tokens[index]) or ""
		local filetype
		if interpreter == "bash" then
			filetype = "bash"
		elseif
			interpreter == "python"
			or interpreter:match("^python%d+$")
			or interpreter:match("^python%d+%.%d+$")
			or (interpreter == "uv" and tokens[index + 1] == "run")
		then
			filetype = "python"
		end

		if filetype and vim.bo[event.buf].filetype ~= filetype then
			vim.bo[event.buf].filetype = filetype
		end
	end,
})

-- create command to route jinja injections
vim.treesitter.query.add_directive("inject-lang-jinja!", function(_, _, bufnr, _, metadata)
	local fname = vim.fs.basename(vim.api.nvim_buf_get_name(bufnr))
	local _, _, ext, _ = string.find(fname, ".*%.(%a+)(%.%a+)")
	if vim.tbl_contains({ "container", "pod", "volume", "network" }, ext) then
		metadata["injection.language"] = "ini"
	elseif vim.tbl_contains({ "sql" }, ext) then
		metadata["injection.language"] = "sql"
	else
		metadata["injection.language"] = ext
	end

	local _, _, caddyext = string.find(fname, "(Caddyfile)%..+")
	if vim.tbl_contains({ "Caddyfile" }, caddyext) then
		metadata["injection.language"] = "caddy"
	end
end, {})

-- set the shell

-- Normalize shell name from a full path or just the name
local function normalize_shell(shell_path)
	-- get the basename if it's a path
	local name = shell_path:match("^.+[\\/]([^\\/]+)$") or shell_path
	-- remove optional ".exe" on Windows
	name = name:gsub("%.exe$", "")
	-- lowercase for comparison
	return name:lower()
end

local shell = vim.g.SHELL or vim.o.shell
local sh = normalize_shell(shell)

if sh == "cmd" then
	vim.opt.shell = shell
	vim.opt.shellcmdflag = "/c"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
elseif sh == "pwsh" then
	vim.opt.shell = shell
	vim.opt.shellcmdflag = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command"
	vim.opt.shellredir = "2>&1 | Out-File -Encoding utf8 %s"
	vim.opt.shellpipe = "2>&1 | Out-File -Encoding utf8 %s"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
elseif sh == "bash" then
	vim.opt.shell = shell .. " -l"
	vim.opt.shellcmdflag = "-c"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
else
	vim.opt.shell = shell .. " -l"
	vim.opt.shellcmdflag = "-c"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
end

vim.opt.signcolumn = "yes"

vim.env.IN_NEOVIM_TERMINAL = true

if vim.env.TMUX then
	vim.g.clipboard = "osc52"
end
