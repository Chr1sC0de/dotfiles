return {
	"folke/todo-comments.nvim",
	enabled = not vim.g.vscode,
	dependencies = { "nvim-lua/plenary.nvim" },
	config = function()
		require("todo-comments").setup({
			search = { command = "rg" }, -- this avoids fzf-lua provider loading
		})

		local todo_snacks = require("todo-comments.snacks")
		Snacks.picker.sources.todo = todo_snacks.source
		vim.keymap.set("n", "<leader>tt", todo_snacks.pick, { desc = "Todo-comments: Snacks" })
	end,
}
