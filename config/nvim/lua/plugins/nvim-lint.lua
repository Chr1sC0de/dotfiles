return {
	"mfussenegger/nvim-lint",
	enabled = not vim.g.vscode,
	event = {
		"BufReadPre",
		"BufNewFile",
	},
	config = function()
		local lint = require("lint")

		-- Custom zuban linter (mypy-compatible output: file.py:10: error: msg  [code])
		lint.linters["zuban"] = {
			name = "zuban",
			cmd = "zuban",
			args = { "mypy", "--strict" },
			stdin = false,
			append_fname = true,
			stream = "stdout",
			ignore_exitcode = true,
			parser = require("lint.parser").from_pattern(
				"([^:]+):(%d+): (%a+): (.+)",
				{ "file", "lnum", "severity", "message" },
				{
					error = vim.diagnostic.severity.ERROR,
					warning = vim.diagnostic.severity.WARN,
					note = vim.diagnostic.severity.INFO,
				},
				{ source = "zuban" }
			),
		}

		-- python is excluded here; zuban runs only on BufWritePost below
		lint.linters_by_ft = {}

		local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

		vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
			group = lint_augroup,
			callback = function()
				lint.try_lint()
			end,
		})

		-- zuban is a type checker — only run on save, not on every keystroke/enter
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = lint_augroup,
			pattern = "*.py",
			callback = function()
				lint.try_lint("zuban")
			end,
		})

		vim.keymap.set("n", "<leader>l", function()
			lint.try_lint()
		end, { desc = "Trigger linting for current file" })
	end,
}
