return {
	"alexpasmantier/pymple.nvim",
	enabled = not vim.g.vscode,
	dependencies = {
		"nvim-lua/plenary.nvim",
		"MunifTanjim/nui.nvim",
		-- optional (nicer ui)
		"stevearc/dressing.nvim",
		"nvim-tree/nvim-web-devicons",
	},
	-- System dependencies are provisioned by the shell installer, not Neovim.
	build = function()
		for _, binary in ipairs({ "gg", "fd", vim.fn.has("mac") == 1 and "gsed" or "sed" }) do
			assert(
				vim.fn.executable(binary) == 1,
				"Pymple requires " .. binary .. "; run utils/dependencies-install-all.sh"
			)
			local result = vim.system({ binary, "--version" }, { text = true }):wait(10000)
			assert(result.code == 0, "Pymple dependency failed: " .. binary .. ": " .. (result.stderr or ""))
		end
	end,
	config = function()
		require("pymple").setup({})
	end,
}
