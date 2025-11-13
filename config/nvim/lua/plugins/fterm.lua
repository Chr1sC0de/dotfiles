CMD = os.getenv("SHELL") or vim.fn.exepath("bash")

-- sometimes the shell might not be set so we should set it
vim.env.SHELL = CMD

return {
	"numToStr/FTerm.nvim",
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

		local float_terminal_2 = float_terminal:new({
			ft = "FTerm2", -- You can also override the default filetype, if you want
			cmd = CMD,
			dimensions = {
				height = 0.9,
				width = 0.9,
			},
		})

		vim.keymap.set("n", "<A-e>", function()
			float_terminal_2:toggle()
		end, { desc = "Toggle Terminal: Terminal 2" })

		vim.keymap.set("t", "<A-e>", function()
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, true, true), "n", false)
			float_terminal_2:toggle()
		end, { desc = "Toggle Terminal: Terminal 2" })

		vim.keymap.set("n", "<leader>tmg", function()
			require("FTerm").run({ "tms" })
		end, { desc = "Float Term: tmux sessionizer github" })

		vim.keymap.set("n", "<leader>tms", function()
			require("FTerm").run({ "tms switch" })
		end, { desc = "Float Term: tmux sessionizer switch" })
	end,
}
