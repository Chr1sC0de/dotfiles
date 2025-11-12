return -- install with yarn or npm
{
	"Carus11/markdown-preview.nvim",
	cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
	build = "cd app && yarn install",
	init = function()
		vim.g.mkdp_filetypes = { "markdown" }
	end,
	ft = { "markdown" },

	config = function()
		vim.keymap.set("n", "<leader>mdp", ":MarkdownPreview<cr>", { desc = "Markdown Preview: Start" })
		vim.keymap.set("n", "<leader>mdx", ":MarkdownPreviewStop<cr>", { desc = "Markdown Preview: Stop" })
		vim.keymap.set("n", "<leader>mdt", ":MarkdownPreviewToggle<cr>", { desc = "Markdown Preview: Toggle" })
	end,
}
