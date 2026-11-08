return {
	"CoreyKaylor/diffbandit.nvim",
	config = function()
		require("diffbandit").setup()

		local function map(mode, l, r, desc)
			vim.keymap.set(mode, l, r, { desc = desc, silent = true })
		end

		map("n", "<leader>ghd", ":DiffBanditGitCurrent<cr>", "diff bandit: git current")
		map("n", "<leader>dbc", ":DiffBanditCommitPanel<cr>", "diff bandit: commit panel")
	end,
}
