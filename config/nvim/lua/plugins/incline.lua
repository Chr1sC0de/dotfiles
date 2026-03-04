return {
	"b0o/incline.nvim",
	enabled = not vim.g.vscode,
	config = function()
		require("incline").setup()
	end,
}
