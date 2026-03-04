return {
	"lervag/vimtex",
	enabled = not vim.g.vscode,
	lazy = false, -- we don't want to lazy load VimTeX
	init = function()
		vim.g.vimtex_view_method = "zathura"
	end,
}
