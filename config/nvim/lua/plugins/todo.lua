return {
	"folke/todo-comments.nvim",
	enabled = not vim.g.vscode,
	dependencies = { "nvim-lua/plenary.nvim" },
	config = function()
		require("todo-comments").setup({
			search = { command = "rg" }, -- this avoids fzf-lua provider loading
		})
		vim.keymap.set("n", "<leader>tt", ":TodoTelescope<cr>", { desc = "Todo-comments: Telescope" })
	end,
}
