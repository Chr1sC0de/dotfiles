return {
	"stevearc/overseer.nvim",
	enabled = not vim.g.vscode,
	config = function()
		require("overseer").setup({})
		vim.keymap.set("n", "<leader>oo", ":OverseerToggle<cr>", { desc = "Overseer: Toggle" })
		vim.keymap.set("n", "<leader>or", ":OverseerRun<cr>", { desc = "Overseer: Run" })
	end,
}
