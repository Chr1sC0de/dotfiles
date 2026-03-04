return {
	"numToStr/FTerm.nvim",
	enabled = not vim.g.vscode,
	config = function()
		require("FTerm").setup({
			border = "rounded",
			dimensions = {
				height = 0.9,
				width = 0.9,
			},
			auto_close = true,
		})
		-- Example keybindings
		vim.keymap.set("n", "<A-i>", '<CMD>lua require("FTerm").toggle()<CR>', { desc = "Toggle Terminal: Terminal 1" })
		vim.keymap.set(
			"t",
			"<A-i>",
			'<C-\\><C-n><CMD>lua require("FTerm").toggle()<CR>',
			{ desc = "Toggle Terminal: Terminal 1" }
		)

		local float_terminal = require("FTerm")

		vim.keymap.set("n", "<leader>tmg", function()
			term = require("FTerm"):new({ auto_close = true })
			term:run("tms;exit")
		end, { desc = "Float Term: tmux sessionizer github" })

		vim.keymap.set("n", "<leader>tms", function()
			term = require("FTerm"):new({ auto_close = true })
			term:run("tms switch;exit")
		end, { desc = "Float Term: tmux sessionizer switch" })
	end,
}
