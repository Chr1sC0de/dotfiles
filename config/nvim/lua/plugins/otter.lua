return {
	"jmbuhr/otter.nvim",
	enabled = not vim.g.vscode,
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
	},
	opts = {
		buffers = {
			preambles = {
				bash = { "#!/usr/bin/env bash" },
			},
			ignore_pattern = {
				bash = "^%s*#!",
			},
		},
	},
}
